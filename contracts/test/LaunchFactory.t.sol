// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BondingCurveV1 } from "../src/BondingCurveV1.sol";
import { LaunchFactory } from "../src/LaunchFactory.sol";
import { LaunchToken } from "../src/LaunchToken.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { ILaunchErrors } from "../src/interfaces/ILaunchErrors.sol";
import { ILaunchFactory } from "../src/interfaces/ILaunchFactory.sol";
import { ILaunchToken } from "../src/interfaces/ILaunchToken.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";

// This fixture deliberately retains deposited ETH as WETH backing.
// forge-lint: disable-next-line(locked-ether)
contract FactoryWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract FactoryPair {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;

    uint112 private _reserve0;
    uint112 private _reserve1;

    // Adversarial fixtures intentionally permit arbitrary token/factory addresses.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address factory_, address tokenA, address tokenB) {
        factory = factory_;
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        return (_reserve0, _reserve1, 0);
    }

    function mint(address recipient) external returns (uint256 liquidity) {
        uint256 amount0 = IERC20(token0).balanceOf(address(this)) - _reserve0;
        uint256 amount1 = IERC20(token1).balanceOf(address(this)) - _reserve1;
        liquidity = amount0 < amount1 ? amount0 : amount1;
        if (liquidity == 0) return 0;

        totalSupply += liquidity;
        balanceOf[recipient] += liquidity;
        _reserve0 = SafeCast.toUint112(IERC20(token0).balanceOf(address(this)));
        _reserve1 = SafeCast.toUint112(IERC20(token1).balanceOf(address(this)));
    }

    function sync() external {
        _reserve0 = SafeCast.toUint112(IERC20(token0).balanceOf(address(this)));
        _reserve1 = SafeCast.toUint112(IERC20(token1).balanceOf(address(this)));
    }
}

contract FactoryV2 {
    mapping(bytes32 key => address pair) private _pairs;

    bool public failCreate;
    uint256 public pairCount;
    bool public observedPairUnset;
    bool public observedEntireSupplyOnCurve;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    address private _reentryTarget;
    bytes private _reentryData;

    function setFailCreate(bool fail) external {
        failCreate = fail;
    }

    // Reentry calldata is intentionally arbitrary for the adversarial fixture.
    // forge-lint: disable-next-line(missing-zero-check)
    function setReentry(address target, bytes calldata data) external {
        _reentryTarget = target;
        _reentryData = data;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _pairs[_key(tokenA, tokenB)];
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (failCreate) revert("CREATE_FAILED");
        require(_pairs[_key(tokenA, tokenB)] == address(0), "PAIR_EXISTS");

        address curve = ILaunchToken(tokenA).curve();
        observedPairUnset = ILaunchToken(tokenA).lpPair() == address(0);
        uint256 curveBalance = IERC20(tokenA).balanceOf(curve);
        uint256 supply = IERC20(tokenA).totalSupply();
        // Exact equality is the invariant this callback is intended to observe.
        // forge-lint: disable-next-line(incorrect-strict-equality)
        observedEntireSupplyOnCurve = curveBalance == supply;

        if (_reentryTarget != address(0)) {
            reentryAttempted = true;
            // Deliberate callback before pair registration probes the launch guard.
            // forge-lint: disable-next-line(reentrancy-no-eth)
            (reentrySucceeded,) = _reentryTarget.call(_reentryData);
        }

        pair = address(new FactoryPair(address(this), tokenA, tokenB));
        _pairs[_key(tokenA, tokenB)] = pair;
        ++pairCount;
    }

    function precreatePair(address tokenA, address tokenB) external returns (address pair) {
        require(_pairs[_key(tokenA, tokenB)] == address(0), "PAIR_EXISTS");
        pair = address(new FactoryPair(address(this), tokenA, tokenB));
        _pairs[_key(tokenA, tokenB)] = pair;
        ++pairCount;
    }

    function _key(address tokenA, address tokenB) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }
}

contract WrongVersionEngine {
    // forge-lint: disable-next-line(mixed-case-function)
    function ENGINE_VERSION() external pure returns (uint16) {
        return 2;
    }
}

// This adversarial treasury intentionally retains a successful fee claim.
// forge-lint: disable-next-line(locked-ether)
contract ReentrantLaunchFeeTreasury {
    LaunchFactory private immutable _factory;
    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor(LaunchFactory factory_) {
        _factory = factory_;
    }

    function claim() external returns (uint256) {
        return _factory.claimLaunchFees();
    }

    receive() external payable {
        reentryAttempted = true;
        (reentrySucceeded,) =
            address(_factory).call(abi.encodeCall(LaunchFactory.claimLaunchFees, ()));
    }
}

contract LaunchFactoryTest is Test {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint256 private constant LAUNCH_FEE = 0.0005 ether;
    uint256 private constant DEVELOPER_BUY = 0.001 ether;
    uint16 private constant ENGINE_VERSION = 1;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;
    address private constant PAUSE_AUTHORITY = address(0xA11CE);
    address private constant TIMELOCK = address(0x710E10C);
    address private constant TREASURY = address(0x7000);
    address private constant NEW_TREASURY = address(0x7001);
    address private constant CREATOR = address(0xC0FFEE);
    address private constant SPENDER = address(0xB0B);
    address private constant BAD_ADDRESS = address(0xBAD);
    bytes32 private constant FIELD_PAUSE_AUTHORITY = "pauseAuthority";
    bytes32 private constant FIELD_TIMELOCK = "timelock";
    bytes32 private constant FIELD_PROTOCOL_TREASURY = "protocolTreasury";

    bytes32 private constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant TOKEN_LAUNCHED_TOPIC = keccak256(
        "TokenLaunched(address,address,address,address,address,address,uint16,string,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint16,uint16)"
    );
    bytes32 private constant TRADE_TOPIC = keccak256(
        "Trade(address,address,bool,uint256,uint256,uint256,uint256,uint256,uint256,uint256)"
    );

    event LaunchPauseSet(bool paused);
    event TradingPauseSet(bool paused);
    event EngineConfigured(
        uint16 indexed engineVersion, address indexed implementation, bool enabled
    );
    event FutureDefaultsConfigured(bytes32 indexed configHash);
    event FutureTreasuryConfigured(address indexed previousTreasury, address indexed newTreasury);

    struct TokenLaunchedPayload {
        address lpPair;
        address weth;
        address protocolTreasury;
        uint16 engineVersion;
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 virtualEth;
        uint256 virtualToken;
        uint256 curveTokens;
        uint256 lpTokens;
        uint256 graduationEth;
        uint256 launchFeePaid;
        uint16 tradeFeeBps;
        uint16 protocolShareBps;
    }

    BondingCurveV1 private implementation;
    FactoryWETH private weth;
    FactoryV2 private uniswapFactory;
    LaunchFactory private factory;

    function setUp() external {
        implementation = new BondingCurveV1();
        weth = new FactoryWETH();
        uniswapFactory = new FactoryV2();
        factory = _deployFactory(
            PAUSE_AUTHORITY, TIMELOCK, TREASURY, implementation, weth, uniswapFactory
        );
        vm.deal(CREATOR, 100 ether);
    }

    function testConstructorStoresConcreteDefaultsAndFinalAuthorities() external view {
        assertEq(factory.pauseAuthority(), PAUSE_AUTHORITY);
        assertEq(factory.timelock(), TIMELOCK);
        assertEq(factory.protocolTreasury(), TREASURY);
        assertEq(factory.curveImplementation(ENGINE_VERSION), address(implementation));
        assertTrue(factory.engineEnabled(ENGINE_VERSION));

        LaunchTypes.FactoryDefaults memory defaults = factory.futureDefaults();
        assertEq(defaults.parameters.totalSupply, TOTAL_SUPPLY);
        assertEq(defaults.parameters.curveTokens, CURVE_TOKENS);
        assertEq(defaults.parameters.lpTokens, LP_TOKENS);
        assertEq(defaults.parameters.graduationEth, GRADUATION_ETH);
        assertEq(defaults.parameters.initialVirtualEth, INITIAL_VIRTUAL_ETH);
        assertEq(defaults.parameters.initialVirtualToken, INITIAL_VIRTUAL_TOKEN);
        assertEq(defaults.parameters.tradeFeeBps, TRADE_FEE_BPS);
        assertEq(defaults.parameters.protocolShareBps, PROTOCOL_SHARE_BPS);
        assertEq(defaults.weth, address(weth));
        assertEq(defaults.uniswapFactory, address(uniswapFactory));
        assertEq(defaults.launchFee, LAUNCH_FEE);
        assertEq(factory.futureDefaultsHash(), keccak256(abi.encode(defaults)));
    }

    function testConstructorRejectsZeroAuthoritiesAndTreasury() external {
        LaunchTypes.FactoryInitialization memory initialization = _initialization(
            PAUSE_AUTHORITY, TIMELOCK, TREASURY, implementation, weth, uniswapFactory
        );

        initialization.pauseAuthority = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, FIELD_PAUSE_AUTHORITY)
        );
        new LaunchFactory(initialization);

        initialization.pauseAuthority = PAUSE_AUTHORITY;
        initialization.timelock = address(0);
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, FIELD_TIMELOCK));
        new LaunchFactory(initialization);

        initialization.timelock = TIMELOCK;
        initialization.protocolTreasury = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, FIELD_PROTOCOL_TREASURY)
        );
        new LaunchFactory(initialization);
    }

    function testConstructorRejectsDeployerOrSharedAuthority() external {
        LaunchTypes.FactoryInitialization memory initialization = _initialization(
            address(this), TIMELOCK, TREASURY, implementation, weth, uniswapFactory
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidAuthority.selector, FIELD_PAUSE_AUTHORITY, address(this)
            )
        );
        new LaunchFactory(initialization);

        initialization.pauseAuthority = PAUSE_AUTHORITY;
        initialization.timelock = address(this);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidAuthority.selector, FIELD_TIMELOCK, address(this)
            )
        );
        new LaunchFactory(initialization);

        initialization.timelock = PAUSE_AUTHORITY;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidAuthority.selector, FIELD_TIMELOCK, PAUSE_AUTHORITY
            )
        );
        new LaunchFactory(initialization);
    }

    function testAtomicLaunchOrdersEventsAndWiresCanonicalPair() external {
        LaunchTypes.LaunchRequest memory request = _request(DEVELOPER_BUY);
        vm.recordLogs();

        vm.prank(CREATOR);
        (address tokenAddress, address curveAddress, address pairAddress) =
            _launchWithValue(request, LAUNCH_FEE + DEVELOPER_BUY);

        LaunchToken token = LaunchToken(tokenAddress);
        IBondingCurveV1 curve = IBondingCurveV1(curveAddress);
        assertEq(token.curve(), curveAddress);
        assertEq(token.lpPair(), pairAddress);
        assertEq(curve.lpPair(), pairAddress);
        assertEq(curve.token(), tokenAddress);
        assertEq(curve.implementation(), address(implementation));
        assertEq(curve.protocolTreasury(), TREASURY);
        assertEq(curve.weth(), address(weth));
        assertEq(curve.uniswapFactory(), address(uniswapFactory));
        assertEq(uniswapFactory.getPair(tokenAddress, address(weth)), pairAddress);
        assertTrue(uniswapFactory.observedPairUnset());
        assertTrue(uniswapFactory.observedEntireSupplyOnCurve());
        assertGt(token.balanceOf(CREATOR), 0);
        assertLe(token.balanceOf(CREATOR), TOTAL_SUPPLY / 100);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(factory.launchFeesByTreasury(TREASURY), LAUNCH_FEE);
        assertEq(address(factory).balance, LAUNCH_FEE);

        _assertLaunchLogs(vm.getRecordedLogs(), tokenAddress, curveAddress, pairAddress, request);
    }

    function testLaunchUsesPrecreatedCanonicalPair() external {
        uint256 nextFactoryNonce = vm.getNonce(address(factory));
        address predictedToken = vm.computeCreateAddress(address(factory), nextFactoryNonce + 1);
        address precreatedPair = uniswapFactory.precreatePair(predictedToken, address(weth));

        vm.prank(CREATOR);
        (address token,, address pair) = _launchWithValue(_request(0), LAUNCH_FEE);

        assertEq(token, predictedToken);
        assertEq(pair, precreatedPair);
        assertEq(uniswapFactory.pairCount(), 1);
        assertEq(ILaunchToken(token).lpPair(), precreatedPair);
    }

    function testTokenLaunchedEncoderSupportsEmptyAndMultiwordStrings() external {
        LaunchTypes.LaunchRequest memory request = _request(0);
        request.name = "";
        request.symbol = "";
        vm.recordLogs();
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE);
        TokenLaunchedPayload memory emptyPayload = _findLaunchPayload(vm.getRecordedLogs());
        assertEq(emptyPayload.name, "");
        assertEq(emptyPayload.symbol, "");

        request.name = "A launch token name that crosses two complete ABI words without truncation";
        request.symbol = "12345678901234567890123456789012";
        vm.recordLogs();
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE);
        TokenLaunchedPayload memory longPayload = _findLaunchPayload(vm.getRecordedLogs());
        assertEq(longPayload.name, request.name);
        assertEq(longPayload.symbol, request.symbol);
    }

    function testLaunchRejectsAmbiguousValueAndUnusedMinimum() external {
        LaunchTypes.LaunchRequest memory request = _request(DEVELOPER_BUY);
        uint256 expected = LAUNCH_FEE + DEVELOPER_BUY;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.LaunchValueMismatch.selector, expected, expected + 1
            )
        );
        vm.prank(CREATOR);
        _launchWithValue(request, expected + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.LaunchValueMismatch.selector, expected, expected - 1
            )
        );
        vm.prank(CREATOR);
        _launchWithValue(request, expected - 1);

        request = _request(0);
        request.minDeveloperTokensOut = 1;
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.SlippageExceeded.selector, 1, 0));
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE);
    }

    function testUnknownAndDisabledEnginesCannotLaunch() external {
        LaunchTypes.LaunchRequest memory request = _request(0);
        request.engineVersion = 2;
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.UnknownEngine.selector, 2));
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE);

        vm.prank(TIMELOCK);
        factory.configureEngine(ENGINE_VERSION, address(implementation), false);
        request.engineVersion = ENGINE_VERSION;
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.EngineDisabled.selector, ENGINE_VERSION)
        );
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE);
    }

    function testEngineConfigurationRejectsInvalidCodeAndVersion() external {
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.InvalidEngineImplementation.selector, BAD_ADDRESS)
        );
        vm.prank(TIMELOCK);
        factory.configureEngine(2, BAD_ADDRESS, true);

        WrongVersionEngine wrongVersion = new WrongVersionEngine();
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.EngineVersionMismatch.selector, 1, 2));
        vm.prank(TIMELOCK);
        factory.configureEngine(1, address(wrongVersion), true);
    }

    function testFutureDefaultsRejectInvalidCurveParametersWithoutMutation() external {
        bytes32 originalHash = factory.futureDefaultsHash();
        LaunchTypes.FactoryDefaults memory defaults = _defaults(weth, uniswapFactory);
        --defaults.parameters.totalSupply;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidSupplyAllocation.selector,
                defaults.parameters.totalSupply,
                CURVE_TOKENS,
                LP_TOKENS
            )
        );
        vm.prank(TIMELOCK);
        factory.setFutureDefaults(defaults);

        assertEq(factory.futureDefaultsHash(), originalHash);
    }

    function testDeveloperBuyCapRevertsTheEntireLaunch() external {
        LaunchTypes.LaunchRequest memory request = _request(0.02 ether);
        uint256 factoryNonceBefore = vm.getNonce(address(factory));
        uint256 pairCountBefore = uniswapFactory.pairCount();

        vm.expectPartialRevert(ILaunchErrors.DeveloperBuyCapExceeded.selector);
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE + request.developerBuyGross);

        assertEq(vm.getNonce(address(factory)), factoryNonceBefore);
        assertEq(uniswapFactory.pairCount(), pairCountBefore);
        assertEq(factory.launchFeesByTreasury(TREASURY), 0);
        assertEq(address(factory).balance, 0);
    }

    function testDeveloperMinimumAboveCapRevertsTheEntireLaunch() external {
        LaunchTypes.LaunchRequest memory request = _request(DEVELOPER_BUY);
        request.minDeveloperTokensOut = (TOTAL_SUPPLY / 100) + 1;
        uint256 factoryNonceBefore = vm.getNonce(address(factory));

        vm.expectPartialRevert(ILaunchErrors.SlippageExceeded.selector);
        vm.prank(CREATOR);
        _launchWithValue(request, LAUNCH_FEE + DEVELOPER_BUY);

        assertEq(vm.getNonce(address(factory)), factoryNonceBefore);
        assertEq(uniswapFactory.pairCount(), 0);
        assertEq(factory.launchFeesByTreasury(TREASURY), 0);
    }

    function testAnyLaunchFailureRollsBackCreatedContractsAndPair() external {
        uniswapFactory.setFailCreate(true);
        uint256 factoryNonceBefore = vm.getNonce(address(factory));

        vm.expectRevert("CREATE_FAILED");
        vm.prank(CREATOR);
        _launchWithValue(_request(0), LAUNCH_FEE);

        assertEq(vm.getNonce(address(factory)), factoryNonceBefore);
        assertEq(uniswapFactory.pairCount(), 0);
        assertEq(factory.launchFeesByTreasury(TREASURY), 0);
    }

    function testPauseAuthorityAndTimelockAreStrictlySeparated() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.UnauthorizedPauseAuthority.selector, address(this), PAUSE_AUTHORITY
            )
        );
        factory.setLaunchesPaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.UnauthorizedTimelock.selector, address(this), TIMELOCK
            )
        );
        factory.setFutureTreasury(NEW_TREASURY);

        vm.expectEmit(false, false, false, true, address(factory));
        // Test-side expected-event declaration, not protocol state.
        // forge-lint: disable-next-line(reentrancy-events)
        emit LaunchPauseSet(true);
        vm.prank(PAUSE_AUTHORITY);
        factory.setLaunchesPaused(true);

        vm.expectEmit(false, false, false, true, address(factory));
        // forge-lint: disable-next-line(reentrancy-events)
        emit TradingPauseSet(true);
        vm.prank(PAUSE_AUTHORITY);
        factory.setTradingPaused(true);

        vm.expectEmit(true, true, false, true, address(factory));
        // forge-lint: disable-next-line(reentrancy-events)
        emit FutureTreasuryConfigured(TREASURY, NEW_TREASURY);
        vm.prank(TIMELOCK);
        factory.setFutureTreasury(NEW_TREASURY);

        BondingCurveV1 nextImplementation = new BondingCurveV1();
        vm.expectEmit(true, true, false, true, address(factory));
        // forge-lint: disable-next-line(reentrancy-events)
        emit EngineConfigured(ENGINE_VERSION, address(nextImplementation), true);
        vm.prank(TIMELOCK);
        factory.configureEngine(ENGINE_VERSION, address(nextImplementation), true);

        LaunchTypes.FactoryDefaults memory defaults = _defaults(weth, uniswapFactory);
        defaults.launchFee = LAUNCH_FEE + 1;
        vm.expectEmit(true, false, false, true, address(factory));
        // forge-lint: disable-next-line(reentrancy-events)
        emit FutureDefaultsConfigured(keccak256(abi.encode(defaults)));
        vm.prank(TIMELOCK);
        factory.setFutureDefaults(defaults);
    }

    function testTradingPauseRejectsDeveloperBuyButAllowsLaunchWithoutOne() external {
        vm.prank(PAUSE_AUTHORITY);
        factory.setTradingPaused(true);

        vm.expectRevert(ILaunchErrors.TradingPaused.selector);
        vm.prank(CREATOR);
        _launchWithValue(_request(DEVELOPER_BUY), LAUNCH_FEE + DEVELOPER_BUY);

        vm.prank(CREATOR);
        (address token, address curve,) = _launchWithValue(_request(0), LAUNCH_FEE);
        assertEq(ILaunchToken(token).curve(), curve);
    }

    function testLaunchPauseBlocksAllNewLaunches() external {
        vm.prank(PAUSE_AUTHORITY);
        factory.setLaunchesPaused(true);

        vm.expectRevert(ILaunchErrors.LaunchesPaused.selector);
        vm.prank(CREATOR);
        _launchWithValue(_request(0), LAUNCH_FEE);
    }

    function testExistingLaunchKeepsAllSnapshotsAfterGovernanceChanges() external {
        vm.prank(CREATOR);
        (address oldToken, address oldCurve, address oldPair) =
            _launchWithValue(_request(0), LAUNCH_FEE);

        BondingCurveV1 nextImplementation = new BondingCurveV1();
        FactoryWETH nextWeth = new FactoryWETH();
        FactoryV2 nextUniswapFactory = new FactoryV2();
        LaunchTypes.FactoryDefaults memory nextDefaults = _defaults(nextWeth, nextUniswapFactory);
        nextDefaults.launchFee = LAUNCH_FEE + 1;

        vm.startPrank(TIMELOCK);
        factory.configureEngine(ENGINE_VERSION, address(nextImplementation), true);
        factory.setFutureDefaults(nextDefaults);
        factory.setFutureTreasury(NEW_TREASURY);
        vm.stopPrank();

        IBondingCurveV1 existing = IBondingCurveV1(oldCurve);
        assertEq(existing.token(), oldToken);
        assertEq(existing.implementation(), address(implementation));
        assertEq(existing.protocolTreasury(), TREASURY);
        assertEq(existing.weth(), address(weth));
        assertEq(existing.uniswapFactory(), address(uniswapFactory));
        assertEq(existing.lpPair(), oldPair);
        assertEq(existing.virtualEthReserve(), INITIAL_VIRTUAL_ETH);
        assertEq(existing.virtualTokenReserve(), INITIAL_VIRTUAL_TOKEN);

        vm.prank(CREATOR);
        (address newToken, address newCurve, address newPair) =
            _launchWithValue(_request(0), nextDefaults.launchFee);
        IBondingCurveV1 createdLater = IBondingCurveV1(newCurve);
        assertEq(createdLater.token(), newToken);
        assertEq(createdLater.implementation(), address(nextImplementation));
        assertEq(createdLater.protocolTreasury(), NEW_TREASURY);
        assertEq(createdLater.weth(), address(nextWeth));
        assertEq(createdLater.uniswapFactory(), address(nextUniswapFactory));
        assertEq(createdLater.lpPair(), newPair);
    }

    function testTreasuryRotationDoesNotMoveAccruedLaunchFees() external {
        vm.prank(CREATOR);
        _launchWithValue(_request(0), LAUNCH_FEE);

        vm.prank(TIMELOCK);
        factory.setFutureTreasury(NEW_TREASURY);

        vm.prank(CREATOR);
        _launchWithValue(_request(0), LAUNCH_FEE);

        assertEq(factory.launchFeesByTreasury(TREASURY), LAUNCH_FEE);
        assertEq(factory.launchFeesByTreasury(NEW_TREASURY), LAUNCH_FEE);

        uint256 oldBalance = TREASURY.balance;
        vm.prank(TREASURY);
        assertEq(factory.claimLaunchFees(), LAUNCH_FEE);
        assertEq(TREASURY.balance, oldBalance + LAUNCH_FEE);
        assertEq(factory.launchFeesByTreasury(TREASURY), 0);

        vm.expectRevert(ILaunchErrors.NothingToClaim.selector);
        // The expected revert is the assertion; no return value exists on this path.
        // forge-lint: disable-next-line(unused-return)
        factory.claimLaunchFees();
    }

    function testClaimsRemainAvailableWhileBothPauseFlagsAreSet() external {
        vm.prank(CREATOR);
        (, address curveAddress,) =
            _launchWithValue(_request(DEVELOPER_BUY), LAUNCH_FEE + DEVELOPER_BUY);
        IBondingCurveV1 curve = IBondingCurveV1(curveAddress);

        vm.startPrank(PAUSE_AUTHORITY);
        factory.setLaunchesPaused(true);
        factory.setTradingPaused(true);
        vm.stopPrank();

        vm.expectRevert(ILaunchErrors.TradingPaused.selector);
        vm.prank(CREATOR);
        // The expected revert precedes value delivery and any return value.
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 1 }(CREATOR, CREATOR, 0, type(uint256).max);

        vm.prank(CREATOR);
        assertGt(curve.claimCreatorFees(), 0);
        vm.prank(TREASURY);
        assertGt(curve.claimProtocolFees(), 0);
        vm.prank(TREASURY);
        assertEq(factory.claimLaunchFees(), LAUNCH_FEE);
    }

    function testLaunchFeeClaimBlocksReentrancyWithoutLosingClaim() external {
        ReentrantLaunchFeeTreasury reentrantTreasury = new ReentrantLaunchFeeTreasury(factory);
        vm.prank(TIMELOCK);
        factory.setFutureTreasury(address(reentrantTreasury));

        vm.prank(CREATOR);
        _launchWithValue(_request(0), LAUNCH_FEE);

        assertEq(reentrantTreasury.claim(), LAUNCH_FEE);
        assertTrue(reentrantTreasury.reentryAttempted());
        assertFalse(reentrantTreasury.reentrySucceeded());
        assertEq(address(reentrantTreasury).balance, LAUNCH_FEE);
        assertEq(factory.launchFeesByTreasury(address(reentrantTreasury)), 0);
    }

    function testFactoryLaunchPathBlocksPairFactoryReentrancy() external {
        bytes memory reentryData = abi.encodeCall(ILaunchFactory.launch, (_request(0)));
        uniswapFactory.setReentry(address(factory), reentryData);

        vm.prank(CREATOR);
        _launchWithValue(_request(0), LAUNCH_FEE);

        assertTrue(uniswapFactory.reentryAttempted());
        assertFalse(uniswapFactory.reentrySucceeded());
        assertEq(uniswapFactory.pairCount(), 1);
    }

    function testThirdPartyCannotPreseedCanonicalPairWithLaunchToken() external {
        vm.prank(CREATOR);
        (address tokenAddress,, address pairAddress) =
            _launchWithValue(_request(DEVELOPER_BUY), LAUNCH_FEE + DEVELOPER_BUY);
        LaunchToken token = LaunchToken(tokenAddress);
        FactoryPair pair = FactoryPair(pairAddress);
        uint256 amount = token.balanceOf(CREATOR) / 2;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.TransferRestricted.selector, CREATOR, CREATOR, pairAddress
            )
        );
        vm.prank(CREATOR);
        // Both calls intentionally revert, so their ERC-20 return values are unreachable.
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(pairAddress, amount);

        vm.prank(CREATOR);
        assertTrue(token.approve(SPENDER, amount));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.TransferRestricted.selector, SPENDER, CREATOR, pairAddress
            )
        );
        vm.prank(SPENDER);
        // This adversarial call intentionally uses another approved owner and reverts.
        // forge-lint: disable-next-line(arbitrary-send-erc20, erc20-unchecked-transfer)
        token.transferFrom(CREATOR, pairAddress, amount);

        weth.mint(pairAddress, 1 ether);
        assertEq(pair.mint(SPENDER), 0);
        assertEq(pair.totalSupply(), 0);
        assertEq(token.balanceOf(pairAddress), 0);
    }

    function _assertLaunchLogs(
        Vm.Log[] memory logs,
        address token,
        address curve,
        address pair,
        LaunchTypes.LaunchRequest memory request
    ) private view {
        uint256 initialTransferIndex = type(uint256).max;
        uint256 launchIndex = type(uint256).max;
        uint256 tradeIndex = type(uint256).max;

        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == token && logs[i].topics.length == 3
                    && logs[i].topics[0] == TRANSFER_TOPIC && logs[i].topics[1] == bytes32(0)
            ) {
                initialTransferIndex = i;
            }
            if (logs[i].emitter == address(factory) && logs[i].topics[0] == TOKEN_LAUNCHED_TOPIC) {
                launchIndex = i;
                assertEq(_topicAddress(logs[i].topics[1]), token);
                assertEq(_topicAddress(logs[i].topics[2]), curve);
                assertEq(_topicAddress(logs[i].topics[3]), CREATOR);
                TokenLaunchedPayload memory payload = _decodeLaunchPayload(logs[i].data);
                assertEq(payload.lpPair, pair);
                assertEq(payload.weth, address(weth));
                assertEq(payload.protocolTreasury, TREASURY);
                assertEq(payload.engineVersion, ENGINE_VERSION);
                assertEq(payload.name, request.name);
                assertEq(payload.symbol, request.symbol);
                assertEq(payload.totalSupply, TOTAL_SUPPLY);
                assertEq(payload.virtualEth, INITIAL_VIRTUAL_ETH);
                assertEq(payload.virtualToken, INITIAL_VIRTUAL_TOKEN);
                assertEq(payload.curveTokens, CURVE_TOKENS);
                assertEq(payload.lpTokens, LP_TOKENS);
                assertEq(payload.graduationEth, GRADUATION_ETH);
                assertEq(payload.launchFeePaid, LAUNCH_FEE);
                assertEq(payload.tradeFeeBps, TRADE_FEE_BPS);
                assertEq(payload.protocolShareBps, PROTOCOL_SHARE_BPS);
            }
            if (logs[i].emitter == curve && logs[i].topics[0] == TRADE_TOPIC) {
                tradeIndex = i;
                assertEq(_topicAddress(logs[i].topics[1]), token);
                assertEq(_topicAddress(logs[i].topics[2]), CREATOR);
            }
        }

        assertLt(initialTransferIndex, launchIndex);
        assertLt(launchIndex, tradeIndex);
    }

    function _findLaunchPayload(Vm.Log[] memory logs)
        private
        view
        returns (TokenLaunchedPayload memory payload)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(factory) && logs[i].topics[0] == TOKEN_LAUNCHED_TOPIC) {
                return _decodeLaunchPayload(logs[i].data);
            }
        }
        revert("TOKEN_LAUNCHED_NOT_FOUND");
    }

    function _decodeLaunchPayload(bytes memory eventData)
        private
        pure
        returns (TokenLaunchedPayload memory)
    {
        bytes memory tupleEncoded = abi.encodePacked(bytes32(uint256(32)), eventData);
        return abi.decode(tupleEncoded, (TokenLaunchedPayload));
    }

    function _deployFactory(
        address pauseAuthority_,
        address timelock_,
        address treasury_,
        BondingCurveV1 implementation_,
        FactoryWETH weth_,
        FactoryV2 uniswapFactory_
    ) private returns (LaunchFactory deployed) {
        return new LaunchFactory(
            _initialization(
                pauseAuthority_, timelock_, treasury_, implementation_, weth_, uniswapFactory_
            )
        );
    }

    function _launchWithValue(LaunchTypes.LaunchRequest memory request, uint256 value)
        private
        returns (address token, address curve, address pair)
    {
        // The fixture's factory is fixed in setUp; callers choose value to exercise validation.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        return factory.launch{ value: value }(request);
    }

    function _initialization(
        address pauseAuthority_,
        address timelock_,
        address treasury_,
        BondingCurveV1 implementation_,
        FactoryWETH weth_,
        FactoryV2 uniswapFactory_
    ) private pure returns (LaunchTypes.FactoryInitialization memory) {
        return LaunchTypes.FactoryInitialization({
                pauseAuthority: pauseAuthority_,
                timelock: timelock_,
                protocolTreasury: treasury_,
                engineVersion: ENGINE_VERSION,
                implementation: address(implementation_),
                defaults: _defaults(weth_, uniswapFactory_)
            });
    }

    function _defaults(FactoryWETH weth_, FactoryV2 uniswapFactory_)
        private
        pure
        returns (LaunchTypes.FactoryDefaults memory)
    {
        return LaunchTypes.FactoryDefaults({
            parameters: LaunchTypes.CurveParameters({
                totalSupply: TOTAL_SUPPLY,
                curveTokens: CURVE_TOKENS,
                lpTokens: LP_TOKENS,
                graduationEth: GRADUATION_ETH,
                initialVirtualEth: INITIAL_VIRTUAL_ETH,
                initialVirtualToken: INITIAL_VIRTUAL_TOKEN,
                tradeFeeBps: TRADE_FEE_BPS,
                protocolShareBps: PROTOCOL_SHARE_BPS
            }),
            weth: address(weth_),
            uniswapFactory: address(uniswapFactory_),
            launchFee: LAUNCH_FEE
        });
    }

    function _request(uint256 developerBuyGross)
        private
        pure
        returns (LaunchTypes.LaunchRequest memory)
    {
        return LaunchTypes.LaunchRequest({
            name: "Launch Token",
            symbol: "LCH",
            engineVersion: ENGINE_VERSION,
            developerBuyGross: developerBuyGross,
            minDeveloperTokensOut: 0,
            deadline: type(uint256).max
        });
    }

    function _topicAddress(bytes32 topic) private pure returns (address) {
        // Event topics contain a canonical left-padded 160-bit address.
        // forge-lint: disable-next-line(unsafe-typecast)
        return address(uint160(uint256(topic)));
    }
}
