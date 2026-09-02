// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { BondingCurveV1 } from "../src/BondingCurveV1.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { LaunchFactory } from "../src/LaunchFactory.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";
import { DeploymentValidation } from "../script/deployment/DeploymentValidation.sol";
import { LocalUniswapV2Factory } from "../script/local/LocalUniswapV2Factory.sol";
import { LocalUniswapV2Pair } from "../script/local/LocalUniswapV2Pair.sol";
import { LocalWETH } from "../script/local/LocalWETH.sol";

contract DeploymentValidationHarness {
    function validateChain(DeploymentValidation.Target target, uint256 chainId) external pure {
        DeploymentValidation.validateChain(target, chainId);
    }

    function validateAuthorities(
        DeploymentValidation.Target target,
        address deployer,
        address pauseAuthority,
        address timelock,
        address protocolTreasury
    ) external pure {
        DeploymentValidation.validateAuthorities(
            target, deployer, pauseAuthority, timelock, protocolTreasury
        );
    }

    function validateDependencies(
        DeploymentValidation.Target target,
        DeploymentValidation.Dependencies memory dependencies,
        bool reviewed
    ) external returns (DeploymentValidation.DependencyEvidence memory) {
        return DeploymentValidation.validateDependencies(target, dependencies, reviewed);
    }
}

contract CanonicalPairHashFactory {
    function pairCodeHash() external pure returns (bytes32) {
        return 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    }
}

contract CodeBearingWETH { }

contract DeploymentTest is Test {
    uint16 private constant ENGINE_VERSION = 1;
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;
    address private constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address private constant MAINNET_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    address private constant MAINNET_WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    bytes32 private constant CANONICAL_PAIR_HASH =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    bytes32 private constant FIELD_PAUSE_AUTHORITY = "pauseAuthority";
    bytes32 private constant FIELD_WETH = "weth";

    address private constant PAUSE_AUTHORITY = address(0xA11CE);
    address private constant TIMELOCK = address(0xB0B);
    address private constant TREASURY = address(0xCAFE);
    address private constant CREATOR = address(0xC0FFEE);

    DeploymentValidationHarness private validator;

    function setUp() external {
        validator = new DeploymentValidationHarness();
    }

    function testAnvilStackDeploysLaunchpadAndGraduatesThroughLocalPair() external {
        (LocalWETH weth, LocalUniswapV2Factory uniswapFactory) = _validatedLocalStack();
        BondingCurveV1 implementation = new BondingCurveV1();
        LaunchFactory factory =
            _factory(address(implementation), address(weth), address(uniswapFactory));
        assertEq(factory.pauseAuthority(), PAUSE_AUTHORITY);
        assertEq(factory.timelock(), TIMELOCK);
        assertNotEq(factory.pauseAuthority(), address(this));
        assertNotEq(factory.timelock(), address(this));
        _assertLocalGraduation(factory, weth, uniswapFactory);
    }

    function _validatedLocalStack()
        private
        returns (LocalWETH weth, LocalUniswapV2Factory uniswapFactory)
    {
        weth = new LocalWETH();
        uniswapFactory = new LocalUniswapV2Factory();
        bytes32 pairCodeHash = uniswapFactory.pairCodeHash();
        DeploymentValidation.DependencyEvidence memory evidence = validator.validateDependencies(
            DeploymentValidation.Target.Anvil,
            _dependencies(address(weth), address(uniswapFactory), pairCodeHash),
            false
        );
        assertEq(evidence.wethRuntimeCodeHash, address(weth).codehash);
        assertEq(evidence.uniswapFactoryRuntimeCodeHash, address(uniswapFactory).codehash);
        assertTrue(evidence.pairInitCodeHashVerified);
    }

    function _assertLocalGraduation(
        LaunchFactory factory,
        LocalWETH weth,
        LocalUniswapV2Factory uniswapFactory
    ) private {
        vm.deal(CREATOR, 6 ether);
        vm.prank(CREATOR);
        (address tokenAddress, address curveAddress, address pairAddress) =
            factory.launch(_request());
        IBondingCurveV1 curve = IBondingCurveV1(curveAddress);
        vm.prank(CREATOR);
        // The recipient is a fixed test actor, not attacker-controlled input.
        // forge-lint: disable-start(arbitrary-send-eth)
        (uint256 tokensOut, uint256 ethGrossUsed) =
            curve.buy{ value: 5 ether }(CREATOR, CREATOR, 0, block.timestamp);
        // forge-lint: disable-end(arbitrary-send-eth)

        LocalUniswapV2Pair pair = LocalUniswapV2Pair(pairAddress);
        assertEq(curve.token(), tokenAddress);
        assertGt(tokensOut, 0);
        assertGt(ethGrossUsed, 0);
        assertEq(uint256(curve.phase()), uint256(LaunchTypes.Phase.Graduated));
        assertGt(pair.totalSupply(), 0);
        assertGt(pair.balanceOf(LP_BURN_ADDRESS), 0);
        assertEq(uniswapFactory.getPair(curve.token(), address(weth)), pairAddress);
    }

    function testTestnetRejectsMainnetDependencies() external {
        DeploymentValidation.Dependencies memory dependencies =
            _dependencies(MAINNET_WETH, address(new LocalUniswapV2Factory()), CANONICAL_PAIR_HASH);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeploymentValidation.TestnetUsesMainnetDependency.selector, FIELD_WETH, MAINNET_WETH
            )
        );
        // forge-lint: disable-start(unused-return)
        validator.validateDependencies(
            DeploymentValidation.Target.RobinhoodTestnet, dependencies, true
        );
        // forge-lint: disable-end(unused-return)
    }

    function testExternalDependenciesRequireExplicitReview() external {
        LocalWETH weth = new LocalWETH();
        LocalUniswapV2Factory factory = new LocalUniswapV2Factory();
        bytes32 pairCodeHash = factory.pairCodeHash();
        vm.expectRevert(DeploymentValidation.DependencyReviewRequired.selector);
        // forge-lint: disable-start(unused-return)
        validator.validateDependencies(
            DeploymentValidation.Target.RobinhoodTestnet,
            _dependencies(address(weth), address(factory), pairCodeHash),
            false
        );
        // forge-lint: disable-end(unused-return)
    }

    function testPairInitCodeHashMismatchFailsClosed() external {
        LocalWETH weth = new LocalWETH();
        LocalUniswapV2Factory factory = new LocalUniswapV2Factory();
        bytes32 incorrect = bytes32(uint256(factory.pairCodeHash()) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeploymentValidation.InvalidPairInitCodeHash.selector,
                incorrect,
                factory.pairCodeHash()
            )
        );
        // forge-lint: disable-start(unused-return)
        validator.validateDependencies(
            DeploymentValidation.Target.Anvil,
            _dependencies(address(weth), address(factory), incorrect),
            false
        );
        // forge-lint: disable-end(unused-return)
    }

    function testReviewedRuntimeCodeHashMismatchFailsClosed() external {
        LocalWETH weth = new LocalWETH();
        LocalUniswapV2Factory factory = new LocalUniswapV2Factory();
        DeploymentValidation.Dependencies memory dependencies =
            _dependencies(address(weth), address(factory), factory.pairCodeHash());
        dependencies.expectedWethRuntimeCodeHash = bytes32(uint256(address(weth).codehash) + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeploymentValidation.DependencyRuntimeCodeHashMismatch.selector,
                FIELD_WETH,
                dependencies.expectedWethRuntimeCodeHash,
                address(weth).codehash
            )
        );
        // forge-lint: disable-start(unused-return)
        validator.validateDependencies(
            DeploymentValidation.Target.RobinhoodTestnet, dependencies, true
        );
        // forge-lint: disable-end(unused-return)
    }

    function testProductionCandidateUsesFinalAuthoritiesAndLeavesNoDeployerAuthority() external {
        CanonicalPairHashFactory canonicalFactory = new CanonicalPairHashFactory();
        CodeBearingWETH codeBearingWeth = new CodeBearingWETH();
        vm.etch(MAINNET_FACTORY, address(canonicalFactory).code);
        vm.etch(MAINNET_WETH, address(codeBearingWeth).code);

        DeploymentValidation.Dependencies memory dependencies =
            _dependencies(MAINNET_WETH, MAINNET_FACTORY, CANONICAL_PAIR_HASH);
        dependencies.expectedWethRuntimeCodeHash = MAINNET_WETH.codehash;
        dependencies.expectedUniswapFactoryRuntimeCodeHash = MAINNET_FACTORY.codehash;
        DeploymentValidation.DependencyEvidence memory evidence = validator.validateDependencies(
            DeploymentValidation.Target.RobinhoodMainnet, dependencies, true
        );
        assertTrue(evidence.pairInitCodeHashVerified);
        validator.validateAuthorities(
            DeploymentValidation.Target.RobinhoodMainnet,
            address(this),
            PAUSE_AUTHORITY,
            TIMELOCK,
            TREASURY
        );

        LaunchFactory factory =
            _factory(address(new BondingCurveV1()), MAINNET_WETH, MAINNET_FACTORY);
        assertEq(factory.pauseAuthority(), PAUSE_AUTHORITY);
        assertEq(factory.timelock(), TIMELOCK);
        assertEq(factory.protocolTreasury(), TREASURY);
        assertNotEq(factory.pauseAuthority(), address(this));
        assertNotEq(factory.timelock(), address(this));
        (bool pauseSuccess,) =
            address(factory).call(abi.encodeCall(LaunchFactory.setTradingPaused, (true)));
        (bool configSuccess,) =
            address(factory).call(abi.encodeCall(LaunchFactory.setFutureTreasury, (address(0xFEE))));
        assertFalse(pauseSuccess);
        assertFalse(configSuccess);
    }

    function testChainAndAuthorityMismatchesFailClosed() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeploymentValidation.ChainIdMismatch.selector, uint256(46_630), uint256(31_337)
            )
        );
        validator.validateChain(DeploymentValidation.Target.RobinhoodTestnet, 31_337);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeploymentValidation.AuthorityIsDeployer.selector,
                FIELD_PAUSE_AUTHORITY,
                address(this)
            )
        );
        validator.validateAuthorities(
            DeploymentValidation.Target.RobinhoodMainnet,
            address(this),
            address(this),
            TIMELOCK,
            TREASURY
        );
    }

    function _factory(address implementation, address weth, address uniswapFactory)
        private
        returns (LaunchFactory)
    {
        return new LaunchFactory(
            LaunchTypes.FactoryInitialization({
                pauseAuthority: PAUSE_AUTHORITY,
                timelock: TIMELOCK,
                protocolTreasury: TREASURY,
                engineVersion: ENGINE_VERSION,
                implementation: implementation,
                defaults: LaunchTypes.FactoryDefaults({
                    parameters: _parameters(),
                    weth: weth,
                    uniswapFactory: uniswapFactory,
                    launchFee: 0
                })
            })
        );
    }

    function _dependencies(address weth, address factory, bytes32 pairInitCodeHash)
        private
        pure
        returns (DeploymentValidation.Dependencies memory)
    {
        return DeploymentValidation.Dependencies({
            weth: weth,
            uniswapFactory: factory,
            pairInitCodeHash: pairInitCodeHash,
            expectedWethRuntimeCodeHash: bytes32(0),
            expectedUniswapFactoryRuntimeCodeHash: bytes32(0)
        });
    }

    function _parameters() private pure returns (LaunchTypes.CurveParameters memory) {
        return LaunchTypes.CurveParameters({
            totalSupply: TOTAL_SUPPLY,
            curveTokens: CURVE_TOKENS,
            lpTokens: LP_TOKENS,
            graduationEth: GRADUATION_ETH,
            initialVirtualEth: INITIAL_VIRTUAL_ETH,
            initialVirtualToken: INITIAL_VIRTUAL_TOKEN,
            tradeFeeBps: TRADE_FEE_BPS,
            protocolShareBps: PROTOCOL_SHARE_BPS
        });
    }

    function _request() private view returns (LaunchTypes.LaunchRequest memory) {
        return LaunchTypes.LaunchRequest({
            name: "Local Token",
            symbol: "LOCAL",
            engineVersion: ENGINE_VERSION,
            developerBuyGross: 0,
            minDeveloperTokensOut: 0,
            deadline: block.timestamp
        });
    }
}
