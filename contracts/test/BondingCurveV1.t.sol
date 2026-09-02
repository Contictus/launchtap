// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { ILaunchErrors } from "../src/interfaces/ILaunchErrors.sol";
import { CurveMath } from "../src/libraries/CurveMath.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";
import { BondingCurveV1Harness } from "./harness/BondingCurveV1Harness.sol";
import { CurveMathHarness } from "./harness/CurveMathHarness.sol";

contract MockV2Factory {
    address private _pair;

    // Zero is intentional so canonical-pair rejection can be exercised.
    // forge-lint: disable-next-line(missing-zero-check)
    function setPair(address pair_) external {
        _pair = pair_;
    }

    function getPair(address, address) external view returns (address) {
        return _pair;
    }
}

contract MockV2Pair {
    address private _factory;
    address private _token0;
    address private _token1;

    // Zero values are intentional so pair validation can be exercised.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address factory_, address token0_, address token1_) {
        _factory = factory_;
        _token0 = token0_;
        _token1 = token1_;
    }

    // Zero is intentional so pair-factory rejection can be exercised.
    // forge-lint: disable-next-line(missing-zero-check)
    function setFactory(address factory_) external {
        _factory = factory_;
    }

    // Zero values are intentional so pair-token rejection can be exercised.
    // forge-lint: disable-next-line(missing-zero-check)
    function setTokens(address token0_, address token1_) external {
        _token0 = token0_;
        _token1 = token1_;
    }

    function factory() external view returns (address) {
        return _factory;
    }

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }
}

contract BondingCurveV1Test is Test {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint256 private constant FLOOR_INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_666;
    uint256 private constant FINAL_VIRTUAL_TOKEN = 266_666_666_666_666_666_666_666_667;
    uint256 private constant FINAL_VIRTUAL_ETH = 5.6 ether;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;

    address private constant TOKEN = address(0x1000);
    address private constant CREATOR = address(0x2000);
    address private constant TREASURY = address(0x3000);
    address private constant WETH = address(0x4000);
    address private constant ATTACKER = address(0xBAD);

    BondingCurveV1Harness private implementation;
    CurveMathHarness private math;
    MockV2Factory private uniswapFactory;
    MockV2Pair private pair;

    function setUp() external {
        implementation = new BondingCurveV1Harness();
        math = new CurveMathHarness();
        uniswapFactory = new MockV2Factory();
        pair = new MockV2Pair(address(uniswapFactory), TOKEN, WETH);
        uniswapFactory.setPair(address(pair));
    }

    function testImplementationInitializationIsDisabled() external {
        vm.expectRevert(ILaunchErrors.ImplementationInitializationDisabled.selector);
        implementation.initialize(_defaultInitialization());

        vm.expectRevert(IBondingCurveV1.NotInitialized.selector);
        // forge-lint: disable-next-line(unused-return)
        implementation.quoteBuy(1);
    }

    function testUninitializedCloneCannotUseCurvePhaseFunctions() external {
        BondingCurveV1Harness curve = _newClone();

        vm.expectRevert(IBondingCurveV1.NotInitialized.selector);
        // forge-lint: disable-next-line(unused-return)
        curve.quoteBuy(1);

        vm.expectRevert(IBondingCurveV1.NotInitialized.selector);
        // forge-lint: disable-next-line(unused-return)
        curve.quoteSell(1);
    }

    function testCloneInitializesExactlyOnceWithDefaultState() external {
        BondingCurveV1Harness curve = _initializeClone(_defaultParameters());

        assertEq(uint8(curve.phase()), uint8(LaunchTypes.Phase.Curve));
        assertEq(curve.token(), TOKEN);
        assertEq(curve.creator(), CREATOR);
        assertEq(curve.protocolTreasury(), TREASURY);
        assertEq(curve.lpPair(), address(pair));
        assertEq(curve.virtualEthReserve(), INITIAL_VIRTUAL_ETH);
        assertEq(curve.virtualTokenReserve(), INITIAL_VIRTUAL_TOKEN);
        assertEq(curve.realCurveEth(), 0);
        assertEq(curve.tokensSold(), 0);

        assertTrue(curve.initialized());
        assertEq(curve.factorySnapshot(), address(this));
        assertEq(curve.implementationSnapshot(), address(implementation));
        assertEq(curve.wethSnapshot(), WETH);
        assertEq(curve.uniswapFactorySnapshot(), address(uniswapFactory));
        assertEq(curve.totalSupplySnapshot(), TOTAL_SUPPLY);
        assertEq(curve.curveTokensSnapshot(), CURVE_TOKENS);
        assertEq(curve.lpTokensSnapshot(), LP_TOKENS);
        assertEq(curve.graduationEthSnapshot(), GRADUATION_ETH);
        assertEq(curve.initialVirtualEthSnapshot(), INITIAL_VIRTUAL_ETH);
        assertEq(curve.initialVirtualTokenSnapshot(), INITIAL_VIRTUAL_TOKEN);
        assertEq(curve.curveInvariantSnapshot(), INITIAL_VIRTUAL_ETH * INITIAL_VIRTUAL_TOKEN);
        assertEq(curve.tradeFeeBpsSnapshot(), TRADE_FEE_BPS);
        assertEq(curve.protocolShareBpsSnapshot(), PROTOCOL_SHARE_BPS);

        vm.expectRevert(ILaunchErrors.AlreadyInitialized.selector);
        curve.initialize(_defaultInitialization());
    }

    function testOnlyDeclaredFactoryCanInitializeClone() external {
        BondingCurveV1Harness curve = _newClone();
        LaunchTypes.CurveInitialization memory initialization = _defaultInitialization();
        initialization.factory = ATTACKER;

        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.UnauthorizedFactory.selector, address(this))
        );
        curve.initialize(initialization);

        curve.initialize(_defaultInitialization());
        assertEq(curve.token(), TOKEN);
    }

    function testFuzzEveryRequiredAddressRejectsZero(uint256 fieldSeed) external {
        uint256 field = bound(fieldSeed, 0, 7);
        LaunchTypes.CurveInitialization memory initialization = _defaultInitialization();
        bytes32 expectedField;

        if (field == 0) {
            initialization.factory = address(0);
            expectedField = "factory";
        } else if (field == 1) {
            initialization.implementation = address(0);
            expectedField = "implementation";
        } else if (field == 2) {
            initialization.token = address(0);
            expectedField = "token";
        } else if (field == 3) {
            initialization.creator = address(0);
            expectedField = "creator";
        } else if (field == 4) {
            initialization.protocolTreasury = address(0);
            expectedField = "protocolTreasury";
        } else if (field == 5) {
            initialization.weth = address(0);
            expectedField = "weth";
        } else if (field == 6) {
            initialization.uniswapFactory = address(0);
            expectedField = "uniswapFactory";
        } else {
            initialization.lpPair = address(0);
            expectedField = "lpPair";
        }

        BondingCurveV1Harness curve = _newClone();
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, expectedField));
        curve.initialize(initialization);
    }

    function testRejectsInvalidSupplyAndCurveAllocations() external {
        LaunchTypes.CurveParameters memory parameters = _defaultParameters();
        parameters.totalSupply -= 1;
        _expectParametersRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidSupplyAllocation.selector,
                parameters.totalSupply,
                parameters.curveTokens,
                parameters.lpTokens
            ),
            parameters
        );

        parameters = _defaultParameters();
        parameters.curveTokens = parameters.lpTokens;
        parameters.totalSupply = parameters.curveTokens + parameters.lpTokens;
        _expectParametersRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidCurveAllocation.selector,
                parameters.curveTokens,
                parameters.lpTokens
            ),
            parameters
        );

        parameters = _defaultParameters();
        parameters.lpTokens = 0;
        parameters.totalSupply = parameters.curveTokens;
        _expectParametersRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidCurveAllocation.selector,
                parameters.curveTokens,
                parameters.lpTokens
            ),
            parameters
        );
    }

    function testRejectsInvalidGraduationReserveAndFees() external {
        LaunchTypes.CurveParameters memory parameters = _defaultParameters();
        parameters.graduationEth = 0;
        _expectParametersRevert(
            abi.encodeWithSelector(ILaunchErrors.InvalidGraduationEth.selector), parameters
        );

        parameters = _defaultParameters();
        parameters.initialVirtualEth = 0;
        _expectParametersRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidVirtualReserves.selector,
                0,
                parameters.initialVirtualToken,
                parameters.curveTokens
            ),
            parameters
        );

        parameters = _defaultParameters();
        parameters.initialVirtualToken = parameters.curveTokens;
        _expectParametersRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidVirtualReserves.selector,
                parameters.initialVirtualEth,
                parameters.initialVirtualToken,
                parameters.curveTokens
            ),
            parameters
        );

        parameters = _defaultParameters();
        parameters.tradeFeeBps = 10_000;
        _expectParametersRevert(
            abi.encodeWithSelector(ILaunchErrors.InvalidTradeFeeBps.selector, uint16(10_000)),
            parameters
        );

        parameters = _defaultParameters();
        parameters.protocolShareBps = 10_001;
        _expectParametersRevert(
            abi.encodeWithSelector(ILaunchErrors.InvalidProtocolShareBps.selector, uint16(10_001)),
            parameters
        );
    }

    function testExactDefaultBoundaryIsReversibleAndFloorY0IsRejected() external {
        uint256 invariant = INITIAL_VIRTUAL_ETH * INITIAL_VIRTUAL_TOKEN;
        assertEq(math.ceilDiv(invariant, FINAL_VIRTUAL_TOKEN), FINAL_VIRTUAL_ETH);
        assertEq(math.ceilDiv(invariant, FINAL_VIRTUAL_ETH), FINAL_VIRTUAL_TOKEN);
        _initializeClone(_defaultParameters());

        LaunchTypes.CurveParameters memory parameters = _defaultParameters();
        parameters.initialVirtualToken = FLOOR_INITIAL_VIRTUAL_TOKEN;
        uint256 floorInvariant = parameters.initialVirtualEth * parameters.initialVirtualToken;
        uint256 floorFinalVirtualToken = parameters.initialVirtualToken - parameters.curveTokens;
        uint256 expectedFinalVirtualEth = parameters.initialVirtualEth + parameters.graduationEth;
        _expectParametersRevert(
            abi.encodeWithSelector(
                ILaunchErrors.InvalidCurveBoundary.selector,
                floorInvariant,
                floorFinalVirtualToken,
                expectedFinalVirtualEth
            ),
            parameters
        );
    }

    function testRejectsArithmeticOverflowDuringInitialization() external {
        LaunchTypes.CurveParameters memory parameters = _defaultParameters();
        parameters.curveTokens = type(uint256).max;
        parameters.lpTokens = 1;
        parameters.totalSupply = type(uint256).max;

        _expectParametersRevert(
            abi.encodeWithSelector(ILaunchErrors.ArithmeticOverflow.selector), parameters
        );

        parameters = LaunchTypes.CurveParameters({
            totalSupply: 3,
            curveTokens: 2,
            lpTokens: 1,
            graduationEth: 1,
            initialVirtualEth: type(uint256).max,
            initialVirtualToken: 3,
            tradeFeeBps: 0,
            protocolShareBps: 0
        });
        _expectParametersRevert(
            abi.encodeWithSelector(ILaunchErrors.ArithmeticOverflow.selector), parameters
        );
    }

    function testAcceptsMaximumSupportedFeeBounds() external {
        LaunchTypes.CurveParameters memory parameters = _defaultParameters();
        parameters.tradeFeeBps = 9999;
        parameters.protocolShareBps = 10_000;

        BondingCurveV1Harness curve = _initializeClone(parameters);
        assertEq(curve.tradeFeeBpsSnapshot(), 9999);
        assertEq(curve.protocolShareBpsSnapshot(), 10_000);
    }

    function testRejectsNonCanonicalPairFactoryAndTokens() external {
        BondingCurveV1Harness curve = _newClone();
        address otherPair = address(0xCAFE);
        uniswapFactory.setPair(otherPair);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.PairNotCanonical.selector, otherPair, address(pair)
            )
        );
        curve.initialize(_defaultInitialization());

        uniswapFactory.setPair(address(pair));
        pair.setFactory(ATTACKER);
        curve = _newClone();
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.PairFactoryMismatch.selector, address(uniswapFactory), ATTACKER
            )
        );
        curve.initialize(_defaultInitialization());

        pair.setFactory(address(uniswapFactory));
        pair.setTokens(TOKEN, ATTACKER);
        curve = _newClone();
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.PairTokensMismatch.selector, TOKEN, ATTACKER)
        );
        curve.initialize(_defaultInitialization());
    }

    function testAcceptsCanonicalPairInReverseTokenOrder() external {
        pair.setTokens(WETH, TOKEN);

        BondingCurveV1Harness curve = _initializeClone(_defaultParameters());
        assertEq(curve.lpPair(), address(pair));
    }

    function testMathBoundaryCases() external view {
        assertEq(math.ceilDiv(0, 3), 0);
        assertEq(math.ceilDiv(9, 3), 3);
        assertEq(math.ceilDiv(10, 3), 4);
        assertEq(math.checkedAdd(20, 22), 42);
        assertEq(math.checkedMul(6, 7), 42);

        (uint256 totalFee, uint256 protocolFee, uint256 creatorFee) =
            math.splitFees(10_100, 100, 5000);
        assertEq(totalFee, 101);
        assertEq(protocolFee, 50);
        assertEq(creatorFee, 51);
        assertEq(math.exactGrossForNet(100, 100), 101);
        assertEq(math.spotPriceWad(2 ether, 4 ether), 0.5 ether);
        assertEq(math.tokensSold(100, 91), 9);
        assertEq(math.realCurveEth(20, 10), 10);
    }

    function testMathRejectsDivisionAndCheckedOverflow() external {
        vm.expectRevert(ILaunchErrors.DivisionByZero.selector);
        assertEq(math.ceilDiv(1, 0), 0);

        vm.expectRevert(ILaunchErrors.DivisionByZero.selector);
        assertEq(math.spotPriceWad(1, 0), 0);

        vm.expectRevert(ILaunchErrors.ArithmeticOverflow.selector);
        assertEq(math.checkedAdd(type(uint256).max, 1), 0);

        vm.expectRevert(ILaunchErrors.ArithmeticOverflow.selector);
        assertEq(math.checkedMul(type(uint256).max, 2), 0);
    }

    function testHandProvenBuySellAndFinalFillQuotes() external view {
        CurveMath.BuyQuote memory buy = math.quoteBuy(1000, 10, 100, 20, 1, 0, 0);
        assertEq(buy.ethGrossUsed, 1);
        assertEq(buy.tokensOut, 9);
        assertEq(buy.newVirtualEth, 11);
        assertEq(buy.newVirtualToken, 91);
        assertEq(buy.refund, 0);
        assertFalse(buy.graduates);

        CurveMath.SellQuote memory sell = math.quoteSell(1000, 20, 50, 50, 10, 0, 0);
        assertEq(sell.ethOut, 3);
        assertEq(sell.ethGross, 3);
        assertEq(sell.newVirtualEth, 17);
        assertEq(sell.newVirtualToken, 60);

        CurveMath.BuyQuote memory finalBuy = math.quoteBuy(1000, 10, 100, 20, 50, 0, 0);
        assertEq(finalBuy.ethGrossUsed, 40);
        assertEq(finalBuy.tokensOut, 80);
        assertEq(finalBuy.refund, 10);
        assertEq(finalBuy.newVirtualEth, 50);
        assertEq(finalBuy.newVirtualToken, 20);
        assertTrue(finalBuy.graduates);

        CurveMath.BuyQuote memory exactBoundary = math.quoteBuy(1000, 10, 100, 20, 40, 0, 0);
        assertEq(exactBoundary.ethGrossUsed, 40);
        assertEq(exactBoundary.refund, 0);
        assertEq(exactBoundary.newVirtualEth, 50);
        assertEq(exactBoundary.newVirtualToken, 20);
        assertTrue(exactBoundary.graduates);

        CurveMath.BuyQuote memory oneUnitOverfill = math.quoteBuy(1000, 10, 100, 20, 41, 0, 0);
        assertEq(oneUnitOverfill.ethGrossUsed, 40);
        assertEq(oneUnitOverfill.refund, 1);
        assertEq(oneUnitOverfill.newVirtualEth, 50);
        assertEq(oneUnitOverfill.newVirtualToken, 20);

        CurveMath.BuyQuote memory feePlateauBoundary =
            math.quoteBuy(1100, 10, 110, 10, 200, 5000, 5000);
        assertEq(feePlateauBoundary.ethGrossUsed, 200);
        assertEq(feePlateauBoundary.protocolFee, 50);
        assertEq(feePlateauBoundary.creatorFee, 50);
        assertEq(feePlateauBoundary.refund, 0);
        assertEq(feePlateauBoundary.newVirtualEth, 110);
        assertEq(feePlateauBoundary.newVirtualToken, 10);
        assertTrue(feePlateauBoundary.graduates);
    }

    function testInitializedContractQuotesRegularAndFinalBuys() external {
        BondingCurveV1Harness curve = _initializeClone(_defaultParameters());

        (
            uint256 grossUsed,
            uint256 tokensOut,
            uint256 protocolFee,
            uint256 creatorFee,
            uint256 refund,
            bool graduates
        ) = curve.quoteBuy(1 ether);
        assertEq(grossUsed, 1 ether);
        assertGt(tokensOut, 0);
        assertEq(protocolFee + creatorFee, 0.01 ether);
        assertEq(refund, 0);
        assertFalse(graduates);

        (grossUsed, tokensOut, protocolFee, creatorFee, refund, graduates) =
            curve.quoteBuy(10 ether);
        assertEq(grossUsed + refund, 10 ether);
        assertEq(tokensOut, CURVE_TOKENS);
        assertEq(protocolFee + creatorFee, (grossUsed * TRADE_FEE_BPS) / 10_000);
        assertGt(refund, 0);
        assertTrue(graduates);

        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.Oversell.selector, uint256(1), uint256(0))
        );
        // The call must revert before it can return a quote.
        // forge-lint: disable-next-line(unused-return)
        curve.quoteSell(1);
    }

    function testFuzzExactGrossProducesExactNetAndIsMinimal(uint16 feeSeed, uint128 netSeed)
        external
        view
    {
        // The bound proves the value fits uint16.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 feeBps = uint16(bound(feeSeed, 0, 9999));
        uint256 net = bound(uint256(netSeed), 1, type(uint128).max);
        uint256 gross = math.exactGrossForNet(net, feeBps);
        uint256 fee = (gross * feeBps) / 10_000;

        assertEq(gross - fee, net);
        if (gross > 1) {
            uint256 previousGross = gross - 1;
            uint256 previousFee = (previousGross * feeBps) / 10_000;
            assertLt(previousGross - previousFee, net);
        }
    }

    function testFuzzBuyAndFullSellPreserveCurveBounds(uint96 grossSeed) external view {
        uint256 suppliedGross = bound(uint256(grossSeed), 1, 20 ether);
        uint256 invariant = INITIAL_VIRTUAL_ETH * INITIAL_VIRTUAL_TOKEN;
        CurveMath.BuyQuote memory buy = math.quoteBuy(
            invariant,
            INITIAL_VIRTUAL_ETH,
            INITIAL_VIRTUAL_TOKEN,
            FINAL_VIRTUAL_TOKEN,
            suppliedGross,
            TRADE_FEE_BPS,
            PROTOCOL_SHARE_BPS
        );

        assertGe(buy.newVirtualEth, INITIAL_VIRTUAL_ETH);
        assertGe(buy.newVirtualToken, FINAL_VIRTUAL_TOKEN);
        assertGe(buy.newVirtualEth * buy.newVirtualToken, invariant);
        assertEq(buy.ethGrossUsed + buy.refund, suppliedGross);

        CurveMath.SellQuote memory sell = math.quoteSell(
            invariant,
            buy.newVirtualEth,
            buy.newVirtualToken,
            INITIAL_VIRTUAL_TOKEN - buy.newVirtualToken,
            buy.tokensOut,
            TRADE_FEE_BPS,
            PROTOCOL_SHARE_BPS
        );
        assertGe(sell.newVirtualEth, INITIAL_VIRTUAL_ETH);
        assertGe(sell.newVirtualToken, FINAL_VIRTUAL_TOKEN);
        assertGe(sell.newVirtualEth * sell.newVirtualToken, invariant);
        assertEq(sell.newVirtualEth, INITIAL_VIRTUAL_ETH);
        assertEq(sell.newVirtualToken, INITIAL_VIRTUAL_TOKEN);
    }

    function _newClone() private returns (BondingCurveV1Harness) {
        return BondingCurveV1Harness(Clones.clone(address(implementation)));
    }

    function _initializeClone(LaunchTypes.CurveParameters memory parameters)
        private
        returns (BondingCurveV1Harness curve)
    {
        curve = _newClone();
        LaunchTypes.CurveInitialization memory initialization = _defaultInitialization();
        initialization.parameters = parameters;
        curve.initialize(initialization);
    }

    function _expectParametersRevert(
        bytes memory reason,
        LaunchTypes.CurveParameters memory parameters
    ) private {
        BondingCurveV1Harness curve = _newClone();
        LaunchTypes.CurveInitialization memory initialization = _defaultInitialization();
        initialization.parameters = parameters;
        vm.expectRevert(reason);
        curve.initialize(initialization);
    }

    function _defaultInitialization()
        private
        view
        returns (LaunchTypes.CurveInitialization memory)
    {
        return LaunchTypes.CurveInitialization({
            factory: address(this),
            implementation: address(implementation),
            token: TOKEN,
            creator: CREATOR,
            protocolTreasury: TREASURY,
            weth: WETH,
            uniswapFactory: address(uniswapFactory),
            lpPair: address(pair),
            parameters: _defaultParameters()
        });
    }

    function _defaultParameters() private pure returns (LaunchTypes.CurveParameters memory) {
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
}
