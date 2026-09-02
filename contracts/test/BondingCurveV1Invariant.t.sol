// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BondingCurveV1Harness } from "./harness/BondingCurveV1Harness.sol";
import { LaunchToken } from "../src/LaunchToken.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";

// The fixture deliberately retains deposited ETH as WETH backing.
// forge-lint: disable-next-line(locked-ether)
contract InvariantWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function donate(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract InvariantPair {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint256 public totalSupply;
    uint256 public mintCount;
    address public lastMintRecipient;
    mapping(address account => uint256 amount) public balanceOf;

    uint112 private _reserve0;
    uint112 private _reserve1;

    // This fixture is deployed only with fresh nonzero contracts.
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

    // The production curve deliberately supplies the permanent burn address.
    // forge-lint: disable-next-line(missing-zero-check)
    function mint(address recipient) external returns (uint256 liquidity) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        liquidity = amount0 < amount1 ? amount0 : amount1;
        if (liquidity == 0) return 0;

        totalSupply += liquidity;
        balanceOf[recipient] += liquidity;
        ++mintCount;
        lastMintRecipient = recipient;
        _reserve0 = SafeCast.toUint112(balance0);
        _reserve1 = SafeCast.toUint112(balance1);
    }

    function sync() external {
        _reserve0 = SafeCast.toUint112(IERC20(token0).balanceOf(address(this)));
        _reserve1 = SafeCast.toUint112(IERC20(token1).balanceOf(address(this)));
    }
}

contract InvariantV2Factory {
    address private _pair;

    // Setup controls the canonical pair and separately tests zero/invalid pair rejection.
    // forge-lint: disable-next-line(missing-zero-check)
    function setPair(address pair_) external {
        _pair = pair_;
    }

    function getPair(address, address) external view returns (address) {
        return _pair;
    }
}

contract InvariantPauseFactory {
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

// This recipient switches between accepting, rejecting, and reentering ETH deliveries.
// forge-lint: disable-next-line(locked-ether)
contract InvariantEthRecipient {
    BondingCurveV1Harness private immutable _curve;
    bool public rejectEth;
    bool public reenter;
    uint256 public reentryAttempts;
    uint256 public reentrySuccesses;

    constructor(BondingCurveV1Harness curve_) {
        _curve = curve_;
    }

    function configure(bool rejectEth_, bool reenter_) external {
        rejectEth = rejectEth_;
        reenter = reenter_;
    }

    function claimRefund() external returns (uint256) {
        return _curve.claimRefund();
    }

    receive() external payable {
        if (rejectEth) revert("REJECT_ETH");
        if (!reenter) return;

        ++reentryAttempts;
        (bool success,) = address(_curve).call(abi.encodeCall(_curve.claimRefund, ()));
        if (success) ++reentrySuccesses;
    }
}

contract BondingCurveV1Handler is Test {
    struct BuyQuote {
        uint256 ethGross;
        uint256 tokensOut;
        uint256 protocolFee;
        uint256 creatorFee;
        uint256 refund;
        bool graduates;
    }

    struct SellQuote {
        uint256 ethOut;
        uint256 ethGross;
        uint256 protocolFee;
        uint256 creatorFee;
    }

    BondingCurveV1Harness public immutable curve;
    LaunchToken public immutable token;
    InvariantPauseFactory public immutable pauseFactory;
    InvariantV2Factory public immutable uniswapFactory;
    InvariantPair public immutable pair;
    InvariantWETH public immutable weth;
    InvariantEthRecipient public immutable ethRecipient;

    address[4] public actors;

    uint256 public ghostBuyInput;
    uint256 public ghostBuyGrossUsed;
    uint256 public ghostBuyRefunds;
    uint256 public ghostSellGross;
    uint256 public ghostSellEthOut;
    uint256 public ghostSellProtocolFees;
    uint256 public ghostSellCreatorFees;
    uint256 public ghostProtocolFeesAccrued;
    uint256 public ghostCreatorFeesAccrued;
    uint256 public ghostProtocolFeesClaimed;
    uint256 public ghostCreatorFeesClaimed;
    uint256 public ghostRefundsCredited;
    uint256 public ghostRefundsClaimed;
    uint256 public ghostForcedEth;
    uint256 public ghostGraduations;
    uint256 public ghostPhaseRegressions;
    uint256 public ghostRevertChecks;
    uint256 public ghostRevertViolations;
    uint256 public ghostExecutionMismatches;

    LaunchTypes.Phase private _lastPhase;

    constructor(
        BondingCurveV1Harness curve_,
        LaunchToken token_,
        InvariantPauseFactory pauseFactory_,
        InvariantV2Factory uniswapFactory_,
        InvariantPair pair_,
        InvariantWETH weth_,
        address creator,
        address treasury
    ) {
        curve = curve_;
        token = token_;
        pauseFactory = pauseFactory_;
        uniswapFactory = uniswapFactory_;
        pair = pair_;
        weth = weth_;
        ethRecipient = new InvariantEthRecipient(curve_);
        actors = [address(0xA11CE), address(0xB0B), creator, treasury];
        _lastPhase = LaunchTypes.Phase.Curve;
    }

    function buy(uint256 actorSeed, uint256 grossSeed, uint256 recipientSeed) external {
        if (curve.phase() != LaunchTypes.Phase.Curve) return;

        address actor = _actor(actorSeed);
        uint256 suppliedGross = grossSeed % 8 == 0
            ? bound(grossSeed, 1 ether, 10 ether)
            : bound(grossSeed, 1, 0.5 ether);
        if (actor.balance < suppliedGross) vm.deal(actor, actor.balance + 100 ether);

        (bool quoteSuccess, bytes memory quoteData) =
            address(curve).staticcall(abi.encodeCall(IBondingCurveV1.quoteBuy, (suppliedGross)));
        if (!quoteSuccess) return;
        BuyQuote memory quote = abi.decode(quoteData, (BuyQuote));

        uint256 pendingBefore = curve.totalPendingRefunds();
        address refundRecipient = _deliveryRecipient(recipientSeed, actor);
        vm.prank(actor);
        // Value reaches only the initialized curve under test.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        (bool success, bytes memory result) = address(curve).call{ value: suppliedGross }(
            abi.encodeCall(IBondingCurveV1.buy, (actor, refundRecipient, 0, type(uint256).max))
        );
        if (success) {
            (uint256 tokensOut, uint256 grossUsed) = abi.decode(result, (uint256, uint256));
            _check(tokensOut == quote.tokensOut);
            _check(grossUsed == quote.ethGross);
            _check(suppliedGross == grossUsed + quote.refund);

            ghostBuyInput += suppliedGross;
            ghostBuyGrossUsed += grossUsed;
            ghostBuyRefunds += quote.refund;
            ghostProtocolFeesAccrued += quote.protocolFee;
            ghostCreatorFeesAccrued += quote.creatorFee;
            _recordCredits(pendingBefore);
        }
        _observePhase();
    }

    function sell(uint256 actorSeed, uint256 amountSeed, uint256 recipientSeed) external {
        if (curve.phase() != LaunchTypes.Phase.Curve) return;

        address actor = _actor(actorSeed);
        uint256 actorBalance = token.balanceOf(actor);
        if (actorBalance == 0) return;
        uint256 tokensIn = bound(amountSeed, 1, actorBalance);

        (bool quoteSuccess, bytes memory quoteData) =
            address(curve).staticcall(abi.encodeCall(IBondingCurveV1.quoteSell, (tokensIn)));
        if (!quoteSuccess) return;
        SellQuote memory quote = abi.decode(quoteData, (SellQuote));

        vm.prank(actor);
        _check(token.approve(address(curve), tokensIn));
        uint256 pendingBefore = curve.totalPendingRefunds();
        address recipient = _deliveryRecipient(recipientSeed, actor);
        // The handler deliberately probes arbitrary recipients while the curve blocks reentry.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        vm.prank(actor);
        bool success = false;
        uint256 actualEthOut = 0;
        // The expected pause/recipient failures remain valid fuzz inputs.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        try curve.sell(tokensIn, recipient, 0, type(uint256).max) returns (uint256 returnedEthOut) {
            success = true;
            actualEthOut = returnedEthOut;
        } catch { }
        if (success) {
            _check(actualEthOut == quote.ethOut);
            _check(quote.ethGross == quote.ethOut + quote.protocolFee + quote.creatorFee);

            ghostSellGross += quote.ethGross;
            ghostSellEthOut += quote.ethOut;
            ghostSellProtocolFees += quote.protocolFee;
            ghostSellCreatorFees += quote.creatorFee;
            ghostProtocolFeesAccrued += quote.protocolFee;
            ghostCreatorFeesAccrued += quote.creatorFee;
            _recordCredits(pendingBefore);
        }
        _observePhase();
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _differentActor(toSeed, from);
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        vm.prank(from);
        _check(token.transfer(to, amount));
        _observePhase();
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _differentActor(spenderSeed, owner);
        vm.prank(owner);
        _check(token.approve(spender, amount));
        _observePhase();
    }

    function transferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amountSeed
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _differentActor(spenderSeed, owner);
        address recipient = _differentActor(recipientSeed, owner);
        uint256 available = token.balanceOf(owner);
        uint256 allowed = token.allowance(owner, spender);
        if (allowed < available) available = allowed;
        uint256 amount = bound(amountSeed, 0, available);

        vm.prank(spender);
        // The handler intentionally exercises approved third-party ERC-20 transfers.
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        _check(token.transferFrom(owner, recipient, amount));
        _observePhase();
    }

    function claimFees(uint256 claimSeed) external {
        if (claimSeed % 2 == 0) {
            uint256 claimable = curve.unclaimedCreatorFees();
            if (claimable == 0) return;
            address creator = curve.creator();
            vm.prank(creator);
            (bool success, bytes memory result) =
                address(curve).call(abi.encodeCall(curve.claimCreatorFees, ()));
            if (success) {
                uint256 claimed = abi.decode(result, (uint256));
                _check(claimed == claimable);
                ghostCreatorFeesClaimed += claimed;
            }
        } else {
            uint256 claimable = curve.unclaimedProtocolFees();
            if (claimable == 0) return;
            address treasury = curve.protocolTreasury();
            vm.prank(treasury);
            (bool success, bytes memory result) =
                address(curve).call(abi.encodeCall(curve.claimProtocolFees, ()));
            if (success) {
                uint256 claimed = abi.decode(result, (uint256));
                _check(claimed == claimable);
                ghostProtocolFeesClaimed += claimed;
            }
        }
        _observePhase();
    }

    function claimRefund() external {
        uint256 pending = curve.pendingRefund(address(ethRecipient));
        if (pending == 0) return;
        (bool success, bytes memory result) =
            address(ethRecipient).call(abi.encodeCall(ethRecipient.claimRefund, ()));
        if (success) {
            uint256 claimed = abi.decode(result, (uint256));
            _check(claimed == pending);
            ghostRefundsClaimed += claimed;
        }
        _observePhase();
    }

    function setPause(bool paused) external {
        pauseFactory.setTradingPaused(paused);
        _observePhase();
    }

    function configureRecipient(uint256 modeSeed) external {
        uint256 mode = modeSeed % 3;
        ethRecipient.configure(mode == 1, mode == 2);
        _observePhase();
    }

    function forceEth(uint256 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1 ether);
        vm.deal(address(curve), address(curve).balance + amount);
        ghostForcedEth += amount;
        _observePhase();
    }

    function donateWeth(uint256 amountSeed, bool syncDonation) external {
        uint256 amount = bound(amountSeed, 1, 1 ether);
        weth.donate(address(pair), amount);
        if (syncDonation) pair.sync();
        _observePhase();
    }

    function revertOversell(uint256 actorSeed) external {
        if (curve.phase() != LaunchTypes.Phase.Curve) return;

        address actor = _actor(actorSeed);
        uint256 tokensIn = curve.tokensSold() + 1;
        vm.prank(actor);
        _check(token.approve(address(curve), tokensIn));
        bytes32 beforeHash = _stateHash(actor);

        vm.prank(actor);
        (bool success,) = address(curve)
            .call(abi.encodeCall(IBondingCurveV1.sell, (tokensIn, actor, 0, type(uint256).max)));
        ++ghostRevertChecks;
        if (success || _stateHash(actor) != beforeHash) ++ghostRevertViolations;
        _observePhase();
    }

    function revertBuySlippage(uint256 actorSeed, uint256 grossSeed) external {
        if (curve.phase() != LaunchTypes.Phase.Curve) return;

        address actor = _actor(actorSeed);
        uint256 suppliedGross = bound(grossSeed, 1, 1 ether);
        if (actor.balance < suppliedGross) vm.deal(actor, actor.balance + 100 ether);
        bytes32 beforeHash = _stateHash(actor);

        vm.prank(actor);
        // Value reaches only the initialized curve under test and must revert.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        (bool success,) = address(curve).call{ value: suppliedGross }(
            abi.encodeCall(
                IBondingCurveV1.buy, (actor, actor, type(uint256).max, type(uint256).max)
            )
        );
        ++ghostRevertChecks;
        if (success || _stateHash(actor) != beforeHash) ++ghostRevertViolations;
        _observePhase();
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _differentActor(uint256 seed, address excluded) private view returns (address actor) {
        uint256 index = seed % actors.length;
        actor = actors[index];
        if (actor == excluded) actor = actors[(index + 1) % actors.length];
    }

    function _deliveryRecipient(uint256 seed, address actor) private view returns (address) {
        return seed % 2 == 0 ? actor : address(ethRecipient);
    }

    function _recordCredits(uint256 pendingBefore) private {
        uint256 pendingAfter = curve.totalPendingRefunds();
        if (pendingAfter >= pendingBefore) ghostRefundsCredited += pendingAfter - pendingBefore;
        else _check(false);
    }

    function _observePhase() private {
        LaunchTypes.Phase current = curve.phase();
        if (_lastPhase == LaunchTypes.Phase.Graduated && current == LaunchTypes.Phase.Curve) {
            ++ghostPhaseRegressions;
        }
        if (_lastPhase == LaunchTypes.Phase.Curve && current == LaunchTypes.Phase.Graduated) {
            ++ghostGraduations;
        }
        _lastPhase = current;
    }

    function _stateHash(address actor) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                curve.phase(),
                curve.virtualEthReserve(),
                curve.virtualTokenReserve(),
                curve.unclaimedCreatorFees(),
                curve.unclaimedProtocolFees(),
                curve.totalPendingRefunds(),
                address(curve).balance,
                actor.balance,
                token.balanceOf(actor),
                token.balanceOf(address(curve)),
                token.balanceOf(address(pair)),
                curve.pendingRefund(address(ethRecipient)),
                pair.totalSupply()
            )
        );
    }

    function _check(bool condition) private {
        if (!condition) ++ghostExecutionMismatches;
    }
}

contract BondingCurveV1InvariantTest is Test {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;
    address private constant CREATOR = address(0xC0FFEE);
    address private constant TREASURY = address(0x7000);
    address private constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    BondingCurveV1Harness private curve;
    LaunchToken private token;
    InvariantPair private pair;
    BondingCurveV1Handler private handler;

    function setUp() external {
        BondingCurveV1Harness implementation = new BondingCurveV1Harness();
        InvariantPauseFactory pauseFactory = new InvariantPauseFactory();
        InvariantV2Factory uniswapFactory = new InvariantV2Factory();
        InvariantWETH weth = new InvariantWETH();
        curve = BondingCurveV1Harness(Clones.clone(address(implementation)));
        token = new LaunchToken("Invariant Token", "INV", address(curve), TOTAL_SUPPLY);
        pair = new InvariantPair(address(uniswapFactory), address(token), address(weth));
        uniswapFactory.setPair(address(pair));
        token.initializePair(address(pair));

        LaunchTypes.CurveInitialization memory initialization = LaunchTypes.CurveInitialization({
            factory: address(pauseFactory),
            implementation: address(implementation),
            token: address(token),
            creator: CREATOR,
            protocolTreasury: TREASURY,
            weth: address(weth),
            uniswapFactory: address(uniswapFactory),
            lpPair: address(pair),
            parameters: _parameters()
        });
        pauseFactory.initializeCurve(curve, initialization);

        handler = new BondingCurveV1Handler(
            curve, token, pauseFactory, uniswapFactory, pair, weth, CREATOR, TREASURY
        );
        for (uint256 i = 0; i < 4; ++i) {
            // A fixed four-actor fixture is intentionally funded through the test VM.
            // forge-lint: disable-next-line(calls-loop)
            vm.deal(handler.actors(i), 1000 ether);
        }

        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = handler.buy.selector;
        selectors[1] = handler.sell.selector;
        selectors[2] = handler.transfer.selector;
        selectors[3] = handler.approve.selector;
        selectors[4] = handler.transferFrom.selector;
        selectors[5] = handler.claimFees.selector;
        selectors[6] = handler.claimRefund.selector;
        selectors[7] = handler.setPause.selector;
        selectors[8] = handler.configureRecipient.selector;
        selectors[9] = handler.forceEth.selector;
        selectors[10] = handler.donateWeth.selector;
        selectors[11] = handler.revertOversell.selector;
        selectors[12] = handler.revertBuySlippage.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    }

    function testHandlerAdversarialPathsAreLive() external {
        address actor = handler.actors(0);
        handler.revertOversell(0);
        handler.revertBuySlippage(0, 1);
        assertEq(handler.ghostRevertChecks(), 2);
        assertEq(handler.ghostRevertViolations(), 0);

        handler.buy(0, 1, 0);
        handler.configureRecipient(1);
        handler.sell(0, token.balanceOf(actor), 1);
        assertGt(curve.pendingRefund(address(handler.ethRecipient())), 0);

        handler.configureRecipient(0);
        handler.claimRefund();
        assertEq(curve.pendingRefund(address(handler.ethRecipient())), 0);

        handler.buy(0, 1, 0);
        handler.configureRecipient(2);
        handler.sell(0, token.balanceOf(actor), 1);
        assertGt(handler.ethRecipient().reentryAttempts(), 0);
        assertEq(handler.ethRecipient().reentrySuccesses(), 0);
    }

    function invariant_fixedSupplyAndAllTokenBalancesRemainAccounted() external view {
        uint256 accounted = token.balanceOf(address(curve)) + token.balanceOf(address(pair))
            + token.balanceOf(address(handler.ethRecipient()));
        for (uint256 i = 0; i < 4; ++i) {
            // The fixed actor set is the complete user balance universe for this handler.
            // forge-lint: disable-next-line(calls-loop)
            accounted += token.balanceOf(handler.actors(i));
        }

        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(accounted, TOTAL_SUPPLY);
    }

    function invariant_accountingAndFeeRefundConservation() external view {
        uint256 required = curve.phase() == LaunchTypes.Phase.Curve ? curve.realCurveEth() : 0;
        required += curve.unclaimedCreatorFees();
        required += curve.unclaimedProtocolFees();
        required += curve.totalPendingRefunds();

        assertEq(address(curve).balance, required + handler.ghostForcedEth());
        assertEq(
            curve.unclaimedProtocolFees() + handler.ghostProtocolFeesClaimed(),
            handler.ghostProtocolFeesAccrued()
        );
        assertEq(
            curve.unclaimedCreatorFees() + handler.ghostCreatorFeesClaimed(),
            handler.ghostCreatorFeesAccrued()
        );
        assertEq(
            curve.totalPendingRefunds() + handler.ghostRefundsClaimed(),
            handler.ghostRefundsCredited()
        );
        assertEq(handler.ghostBuyInput(), handler.ghostBuyGrossUsed() + handler.ghostBuyRefunds());
        assertEq(
            handler.ghostSellGross(),
            handler.ghostSellEthOut() + handler.ghostSellProtocolFees()
                + handler.ghostSellCreatorFees()
        );
    }

    function invariant_inventoryAndCurveProductStayBounded() external view {
        uint256 sold = curve.tokensSold();
        uint256 virtualEth = curve.virtualEthReserve();
        uint256 virtualToken = curve.virtualTokenReserve();
        uint256 invariantProduct = INITIAL_VIRTUAL_ETH * INITIAL_VIRTUAL_TOKEN;
        uint256 finalVirtualToken = INITIAL_VIRTUAL_TOKEN - CURVE_TOKENS;

        assertLe(sold, CURVE_TOKENS);
        assertGe(virtualEth, INITIAL_VIRTUAL_ETH);
        assertLe(virtualEth, INITIAL_VIRTUAL_ETH + GRADUATION_ETH);
        assertGe(virtualToken, finalVirtualToken);
        assertLe(virtualToken, INITIAL_VIRTUAL_TOKEN);
        assertGe(virtualEth * virtualToken, invariantProduct);
        assertLt((virtualEth * virtualToken) - invariantProduct, virtualToken);

        if (curve.phase() == LaunchTypes.Phase.Curve) {
            assertEq(token.balanceOf(address(curve)), TOTAL_SUPPLY - sold);
        } else {
            assertEq(sold, CURVE_TOKENS);
            assertEq(token.balanceOf(address(curve)), 0);
        }
    }

    function invariant_phaseAndGraduationAreOneWayAndConsistent() external view {
        assertEq(handler.ghostPhaseRegressions(), 0);
        assertLe(handler.ghostGraduations(), 1);
        assertLe(pair.mintCount(), 1);
        assertEq(token.graduated(), curve.phase() == LaunchTypes.Phase.Graduated);
        assertEq(handler.ethRecipient().reentrySuccesses(), 0);
    }

    function invariant_initialLpIsNeverRecoverable() external view {
        if (curve.phase() == LaunchTypes.Phase.Curve) {
            assertEq(pair.totalSupply(), 0);
            assertEq(pair.mintCount(), 0);
        } else {
            assertEq(pair.mintCount(), 1);
            assertEq(pair.lastMintRecipient(), LP_BURN_ADDRESS);
            assertGt(pair.totalSupply(), 0);
            assertEq(pair.balanceOf(LP_BURN_ADDRESS), pair.totalSupply());
            assertEq(pair.balanceOf(address(curve)), 0);
            assertEq(pair.balanceOf(address(handler)), 0);
            for (uint256 i = 0; i < 4; ++i) {
                // No actor in the fixed user universe may receive launch LP.
                // forge-lint: disable-next-line(calls-loop)
                assertEq(pair.balanceOf(handler.actors(i)), 0);
            }
        }
    }

    function invariant_revertsNeverLeavePartialState() external view {
        assertEq(handler.ghostRevertViolations(), 0);
        assertEq(handler.ghostExecutionMismatches(), 0);
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
}
