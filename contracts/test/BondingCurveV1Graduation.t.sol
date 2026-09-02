// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BondingCurveV1 } from "../src/BondingCurveV1.sol";
import { ILaunchErrors } from "../src/interfaces/ILaunchErrors.sol";
import { LaunchToken } from "../src/LaunchToken.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";
import { BondingCurveV1Harness } from "./harness/BondingCurveV1Harness.sol";

// This WETH fixture intentionally retains ETH as backing for its minted test balance.
// forge-lint: disable-next-line(locked-ether)
contract GraduationWETH is ERC20 {
    error DepositFailed();

    bool private _failDeposit;
    bool private _failTransfer;
    uint256 public totalDeposited;

    constructor() ERC20("Wrapped Ether", "WETH") { }

    function setFailDeposit(bool fail) external {
        _failDeposit = fail;
    }

    function setFailTransfer(bool fail) external {
        _failTransfer = fail;
    }

    function mintDonation(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

    function deposit() external payable {
        if (_failDeposit) revert DepositFailed();
        totalDeposited += msg.value;
        _mint(msg.sender, msg.value);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (_failTransfer) return false;
        return super.transfer(recipient, amount);
    }
}

contract GraduationV2Factory {
    address private _pair;

    // Zero and non-canonical addresses are intentional adversarial test states.
    // forge-lint: disable-next-line(missing-zero-check)
    function setPair(address pair_) external {
        _pair = pair_;
    }

    function getPair(address, address) external view returns (address) {
        return _pair;
    }
}

contract GraduationV2Pair {
    using SafeCast for uint256;

    address public factory;
    address public token0;
    address public token1;
    uint256 public totalSupply;
    mapping(address account => uint256 amount) public balanceOf;

    uint112 private _reserve0;
    uint112 private _reserve1;
    bool private _returnZero;
    bool private _reenter;
    address private _curve;

    bool public reentryAttempted;
    bool public reentrySucceeded;
    address public lastMintRecipient;
    uint256 public lastAmount0;
    uint256 public lastAmount1;

    // The production curve validates these addresses; setters create adversarial states.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address factory_, address token0_, address token1_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
    }

    // forge-lint: disable-next-line(missing-zero-check)
    function setFactory(address factory_) external {
        factory = factory_;
    }

    // forge-lint: disable-next-line(missing-zero-check)
    function setTokens(address token0_, address token1_) external {
        token0 = token0_;
        token1 = token1_;
    }

    function setTotalSupply(uint256 supply) external {
        totalSupply = supply;
    }

    function setReserves(uint112 reserve0, uint112 reserve1) external {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    function setReturnZero(bool returnZero) external {
        _returnZero = returnZero;
    }

    // forge-lint: disable-next-line(missing-zero-check)
    function setReentry(address curve_, bool reenter) external {
        _curve = curve_;
        _reenter = reenter;
    }

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        return (_reserve0, _reserve1, 0);
    }

    function sync() external {
        _reserve0 = IERC20(token0).balanceOf(address(this)).toUint112();
        _reserve1 = IERC20(token1).balanceOf(address(this)).toUint112();
    }

    function mint(address to) external returns (uint256 liquidity) {
        require(to != address(0), "ZERO_ADDRESS");
        if (_reenter) {
            reentryAttempted = true;
            (reentrySucceeded,) = _curve.call(
                abi.encodeCall(
                    BondingCurveV1.buy, (address(this), address(this), 0, type(uint256).max)
                )
            );
        }

        if (_returnZero) return 0;

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        lastAmount0 = balance0 - _reserve0;
        lastAmount1 = balance1 - _reserve1;
        liquidity = lastAmount0 < lastAmount1 ? lastAmount0 : lastAmount1;
        if (liquidity == 0) return 0;

        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        lastMintRecipient = to;
        _reserve0 = balance0.toUint112();
        _reserve1 = balance1.toUint112();
    }
}

contract GraduationLaunchFactory {
    bool public tradingPaused;

    function setTradingPaused(bool paused) external {
        tradingPaused = paused;
    }

    function initializeCurve(
        BondingCurveV1Harness curve,
        LaunchTypes.CurveInitialization calldata initialization
    ) external {
        curve.initialize(initialization);
    }
}

// This fixture deliberately retains a successfully claimed refund.
// forge-lint: disable-next-line(locked-ether)
contract GraduationRefundRecipient {
    bool private _reject = true;

    function setReject(bool reject_) external {
        _reject = reject_;
    }

    function claim(BondingCurveV1 curve) external returns (uint256) {
        return curve.claimRefund();
    }

    receive() external payable {
        if (_reject) revert("ETH_REJECTED");
    }
}

contract BondingCurveV1GraduationTest is Test {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;
    uint256 private constant DEADLINE = type(uint256).max;
    address private constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address private constant CREATOR = address(0x2000);
    address private constant TREASURY = address(0x3000);
    address private constant ALICE = address(0xA11CE);
    address private constant DONOR = address(0xD0D0);

    bytes32 private constant GRADUATED_TOPIC =
        keccak256("Graduated(address,address,uint256,uint256,uint256)");

    BondingCurveV1Harness private implementation;
    BondingCurveV1Harness private curve;
    LaunchToken private launchToken;
    GraduationWETH private weth;
    GraduationV2Factory private uniswapFactory;
    GraduationV2Pair private pair;
    GraduationLaunchFactory private launchFactory;

    function setUp() external {
        implementation = new BondingCurveV1Harness();
        launchFactory = new GraduationLaunchFactory();
        uniswapFactory = new GraduationV2Factory();
        weth = new GraduationWETH();
        curve = BondingCurveV1Harness(Clones.clone(address(implementation)));
        launchToken = new LaunchToken("Launch", "LCH", address(curve), TOTAL_SUPPLY);
        pair = new GraduationV2Pair(address(uniswapFactory), address(launchToken), address(weth));
        uniswapFactory.setPair(address(pair));
        launchToken.initializePair(address(pair));
        launchFactory.initializeCurve(curve, _defaultInitialization());
        vm.deal(ALICE, 100 ether);
    }

    function testFinalBuyGraduatesAndMintsInitialLpDirectlyToBurnAddress() external {
        // Only gross, refund, and the graduation flag are needed for this path.
        // forge-lint: disable-next-line(unused-return)
        (uint256 grossUsed,,,, uint256 refund, bool graduates) = curve.quoteBuy(10 ether);
        vm.recordLogs();

        vm.prank(ALICE);
        (
            uint256 tokensOut,
            uint256 actualGrossUsed
            // The test intentionally funds the final curve buy.
            // forge-lint: disable-next-line(arbitrary-send-eth)
        ) = curve.buy{ value: 10 ether }(ALICE, ALICE, 0, DEADLINE);

        assertTrue(graduates);
        assertEq(actualGrossUsed, grossUsed);
        assertEq(tokensOut, CURVE_TOKENS);
        assertEq(grossUsed + refund, 10 ether);
        assertEq(uint8(curve.phase()), uint8(LaunchTypes.Phase.Graduated));
        assertTrue(launchToken.graduated());
        assertEq(curve.tokensSold(), CURVE_TOKENS);
        assertEq(curve.realCurveEth(), GRADUATION_ETH);
        assertEq(launchToken.balanceOf(ALICE), CURVE_TOKENS);
        assertEq(launchToken.balanceOf(address(pair)), LP_TOKENS);
        assertEq(weth.balanceOf(address(pair)), GRADUATION_ETH);
        assertEq(launchToken.balanceOf(address(curve)), 0);
        assertEq(weth.balanceOf(address(curve)), 0);
        assertEq(weth.totalDeposited(), GRADUATION_ETH);
        assertEq(pair.lastMintRecipient(), LP_BURN_ADDRESS);
        assertGt(pair.balanceOf(LP_BURN_ADDRESS), 0);
        assertEq(pair.balanceOf(address(curve)), 0);
        assertEq(pair.balanceOf(address(launchFactory)), 0);
        assertEq(pair.balanceOf(ALICE), 0);
        _assertGraduatedEvent(vm.getRecordedLogs(), pair.balanceOf(LP_BURN_ADDRESS));
        _assertPostGraduationAccounting();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.WrongPhase.selector,
                uint8(LaunchTypes.Phase.Curve),
                uint8(LaunchTypes.Phase.Graduated)
            )
        );
        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 1 ether }(ALICE, ALICE, 0, DEADLINE);
    }

    function testExactBoundaryBuyGraduatesWithoutRefund() external {
        // Only the exact gross boundary is needed from this overfill quote.
        // forge-lint: disable-next-line(unused-return)
        (uint256 grossUsed,,,,,) = curve.quoteBuy(10 ether);
        // Only refund and the graduation flag are needed at the exact boundary.
        // forge-lint: disable-next-line(unused-return)
        (,,,, uint256 refund, bool graduates) = curve.quoteBuy(grossUsed);

        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: grossUsed }(ALICE, ALICE, 0, DEADLINE);

        assertTrue(graduates);
        assertEq(refund, 0);
        assertEq(curve.pendingRefund(ALICE), 0);
        assertEq(uint8(curve.phase()), uint8(LaunchTypes.Phase.Graduated));
        _assertPostGraduationAccounting();
    }

    function testFinalRefundFailureRemainsClaimableAfterGraduation() external {
        GraduationRefundRecipient recipient = new GraduationRefundRecipient();
        // Only the final-fill refund is needed for the pull-claim assertion.
        // forge-lint: disable-next-line(unused-return)
        (,,,, uint256 refund,) = curve.quoteBuy(10 ether);

        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 10 ether }(ALICE, address(recipient), 0, DEADLINE);

        assertEq(curve.pendingRefund(address(recipient)), refund);
        assertEq(weth.balanceOf(address(pair)), GRADUATION_ETH);
        _assertPostGraduationAccounting();

        recipient.setReject(false);
        uint256 balanceBefore = address(recipient).balance;
        assertEq(recipient.claim(curve), refund);
        assertEq(address(recipient).balance, balanceBefore + refund);
        assertEq(curve.pendingRefund(address(recipient)), 0);
        _assertPostGraduationAccounting();
    }

    function testGraduationSupportsReversePairOrdering() external {
        pair.setTokens(address(weth), address(launchToken));

        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 10 ether }(ALICE, ALICE, 0, DEADLINE);

        // The mock timestamp is irrelevant to token ordering.
        // forge-lint: disable-next-line(unused-return)
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(reserve0, GRADUATION_ETH);
        assertEq(reserve1, LP_TOKENS);
        assertEq(pair.lastAmount0(), GRADUATION_ETH);
        assertEq(pair.lastAmount1(), LP_TOKENS);
    }

    function testUnsyncedWethDonationBecomesExtraLiquidity() external {
        uint256 donation = 0.5 ether;
        weth.mintDonation(DONOR, donation);
        vm.prank(DONOR);
        assertTrue(weth.transfer(address(pair), donation));

        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 10 ether }(ALICE, ALICE, 0, DEADLINE);

        assertEq(weth.totalDeposited(), GRADUATION_ETH);
        assertEq(weth.balanceOf(address(pair)), donation + GRADUATION_ETH);
        assertEq(pair.lastAmount1(), donation + GRADUATION_ETH);
        _assertPostGraduationAccounting();
    }

    function testSyncedWethDonationBecomesExtraLiquidity() external {
        uint256 donation = 0.5 ether;
        weth.mintDonation(DONOR, donation);
        vm.prank(DONOR);
        assertTrue(weth.transfer(address(pair), donation));
        pair.sync();

        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 10 ether }(ALICE, ALICE, 0, DEADLINE);

        assertEq(weth.totalDeposited(), GRADUATION_ETH);
        assertEq(weth.balanceOf(address(pair)), donation + GRADUATION_ETH);
        assertEq(pair.lastAmount1(), GRADUATION_ETH);
        // The mock timestamp is irrelevant to reserve contribution assertions.
        // forge-lint: disable-next-line(unused-return)
        (uint112 tokenReserve, uint112 wethReserve,) = pair.getReserves();
        assertEq(tokenReserve, LP_TOKENS);
        assertEq(wethReserve, donation + GRADUATION_ETH);
        _assertPostGraduationAccounting();
    }

    function testGraduationRevalidatesCanonicalPairIdentity() external {
        uniswapFactory.setPair(address(0xBAD));
        _expectFinalBuyRevert(
            abi.encodeWithSelector(
                ILaunchErrors.PairNotCanonical.selector, address(0xBAD), address(pair)
            )
        );

        uniswapFactory.setPair(address(pair));
        pair.setFactory(address(0xBAD));
        _expectFinalBuyRevert(
            abi.encodeWithSelector(
                ILaunchErrors.PairFactoryMismatch.selector, address(uniswapFactory), address(0xBAD)
            )
        );

        pair.setFactory(address(uniswapFactory));
        pair.setTokens(address(launchToken), address(0xBAD));
        _expectFinalBuyRevert(
            abi.encodeWithSelector(
                ILaunchErrors.PairTokensMismatch.selector, address(launchToken), address(0xBAD)
            )
        );
    }

    function testGraduationRejectsTokenAndCurvePairMismatch() external {
        address mismatchedPair = address(0xBAD);
        vm.store(
            address(launchToken), bytes32(uint256(7)), bytes32(uint256(uint160(mismatchedPair)))
        );
        _expectFinalBuyRevert(
            abi.encodeWithSelector(
                ILaunchErrors.PairNotCanonical.selector, address(pair), mismatchedPair
            )
        );
    }

    function testExistingLpSupplyFailsWithoutPartialState() external {
        pair.setTotalSupply(1);
        _expectFinalBuyRevert(abi.encodeWithSelector(ILaunchErrors.PairSupplyNotZero.selector, 1));
    }

    function testLaunchedTokenReserveFailsWithoutPartialState() external {
        pair.setReserves(1, 0);
        _expectFinalBuyRevert(
            abi.encodeWithSelector(ILaunchErrors.PairTokenReserveNotZero.selector, 1)
        );
    }

    function testLaunchedTokenBalanceFailsWithoutPartialState() external {
        uint256 donation = 1 ether;
        vm.prank(address(curve));
        assertTrue(launchToken.transfer(address(pair), donation));

        _expectFinalBuyRevert(
            abi.encodeWithSelector(ILaunchErrors.PairTokenBalanceNotZero.selector, donation)
        );
        assertEq(launchToken.balanceOf(address(pair)), donation);
    }

    function testWethDepositFailureRevertsEntireFinalBuy() external {
        weth.setFailDeposit(true);
        _expectFinalBuyRevert(abi.encodeWithSelector(GraduationWETH.DepositFailed.selector));
    }

    function testWethTransferFailureRevertsEntireFinalBuy() external {
        weth.setFailTransfer(true);
        _expectFinalBuyRevert(
            abi.encodeWithSelector(
                ILaunchErrors.WethTransferFailed.selector, address(pair), GRADUATION_ETH
            )
        );
    }

    function testZeroLiquidityRevertsEntireFinalBuy() external {
        pair.setReturnZero(true);
        _expectFinalBuyRevert(abi.encodeWithSelector(ILaunchErrors.PairLiquidityZero.selector));
    }

    function testGraduationBlocksPairMintReentrancy() external {
        pair.setReentry(address(curve), true);

        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 10 ether }(ALICE, ALICE, 0, DEADLINE);

        assertTrue(pair.reentryAttempted());
        assertFalse(pair.reentrySucceeded());
        assertEq(uint8(curve.phase()), uint8(LaunchTypes.Phase.Graduated));
        assertTrue(launchToken.graduated());
        _assertPostGraduationAccounting();
    }

    function _expectFinalBuyRevert(bytes memory reason) private {
        uint256 aliceEthBefore = ALICE.balance;
        uint256 aliceTokensBefore = launchToken.balanceOf(ALICE);
        uint256 curveTokensBefore = launchToken.balanceOf(address(curve));
        uint256 pairTokensBefore = launchToken.balanceOf(address(pair));
        uint256 xBefore = curve.virtualEthReserve();
        uint256 yBefore = curve.virtualTokenReserve();
        uint256 curveEthBefore = address(curve).balance;
        uint256 depositedBefore = weth.totalDeposited();

        vm.expectRevert(reason);
        vm.prank(ALICE);
        // forge-lint: disable-next-line(arbitrary-send-eth, unused-return)
        curve.buy{ value: 10 ether }(ALICE, ALICE, 0, DEADLINE);

        assertEq(ALICE.balance, aliceEthBefore);
        assertEq(launchToken.balanceOf(ALICE), aliceTokensBefore);
        assertEq(launchToken.balanceOf(address(curve)), curveTokensBefore);
        assertEq(launchToken.balanceOf(address(pair)), pairTokensBefore);
        assertEq(curve.virtualEthReserve(), xBefore);
        assertEq(curve.virtualTokenReserve(), yBefore);
        assertEq(address(curve).balance, curveEthBefore);
        assertEq(weth.totalDeposited(), depositedBefore);
        assertEq(curve.unclaimedCreatorFees(), 0);
        assertEq(curve.unclaimedProtocolFees(), 0);
        assertEq(uint8(curve.phase()), uint8(LaunchTypes.Phase.Curve));
        assertFalse(launchToken.graduated());
    }

    function _assertGraduatedEvent(Vm.Log[] memory logs, uint256 expectedLiquidity) private view {
        uint256 matches = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != address(curve)) continue;
            if (logs[i].topics.length != 3 || logs[i].topics[0] != GRADUATED_TOPIC) continue;
            assertEq(abi.decode(abi.encode(logs[i].topics[1]), (address)), address(launchToken));
            assertEq(abi.decode(abi.encode(logs[i].topics[2]), (address)), address(pair));
            (uint256 ethToPool, uint256 tokensToPool, uint256 liquidity) =
                abi.decode(logs[i].data, (uint256, uint256, uint256));
            assertEq(ethToPool, GRADUATION_ETH);
            assertEq(tokensToPool, LP_TOKENS);
            assertEq(liquidity, expectedLiquidity);
            ++matches;
        }
        assertEq(matches, 1);
    }

    function _assertPostGraduationAccounting() private view {
        uint256 required = curve.unclaimedCreatorFees() + curve.unclaimedProtocolFees()
            + curve.totalPendingRefunds();
        assertEq(address(curve).balance, required);
    }

    function _defaultInitialization()
        private
        view
        returns (LaunchTypes.CurveInitialization memory)
    {
        return LaunchTypes.CurveInitialization({
            factory: address(launchFactory),
            implementation: address(implementation),
            token: address(launchToken),
            creator: CREATOR,
            protocolTreasury: TREASURY,
            weth: address(weth),
            uniswapFactory: address(uniswapFactory),
            lpPair: address(pair),
            parameters: LaunchTypes.CurveParameters({
                totalSupply: TOTAL_SUPPLY,
                curveTokens: CURVE_TOKENS,
                lpTokens: LP_TOKENS,
                graduationEth: GRADUATION_ETH,
                initialVirtualEth: INITIAL_VIRTUAL_ETH,
                initialVirtualToken: INITIAL_VIRTUAL_TOKEN,
                tradeFeeBps: TRADE_FEE_BPS,
                protocolShareBps: PROTOCOL_SHARE_BPS
            })
        });
    }
}
