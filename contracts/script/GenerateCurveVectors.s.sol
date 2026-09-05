// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Script } from "forge-std/Script.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BondingCurveV1 } from "../src/BondingCurveV1.sol";
import { LaunchToken } from "../src/LaunchToken.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { ILaunchErrors } from "../src/interfaces/ILaunchErrors.sol";
import { ILaunchToken } from "../src/interfaces/ILaunchToken.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";

// The fixture deliberately retains deposited ETH as WETH backing.
// forge-lint: disable-next-line(locked-ether)
contract VectorWETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") { }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract VectorPair {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint256 public totalSupply;

    uint112 private _reserve0;
    uint112 private _reserve1;

    // The generator only deploys this fixture with freshly created nonzero contracts.
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

    function mint(address) external returns (uint256 liquidity) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;
        liquidity = amount0 < amount1 ? amount0 : amount1;
        if (liquidity == 0) return 0;

        totalSupply += liquidity;
        _reserve0 = SafeCast.toUint112(balance0);
        _reserve1 = SafeCast.toUint112(balance1);
    }
}

contract VectorV2Factory {
    mapping(bytes32 key => address pair) private _pairs;

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _pairs[_key(tokenA, tokenB)];
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        bytes32 key = _key(tokenA, tokenB);
        require(_pairs[key] == address(0), "PAIR_EXISTS");

        pair = address(new VectorPair(address(this), tokenA, tokenB));
        _pairs[key] = pair;
    }

    function _key(address tokenA, address tokenB) private pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }
}

contract VectorActor {
    function createCurve(
        address implementation,
        address weth,
        address uniswapFactory,
        address creator,
        address treasury,
        LaunchTypes.CurveParameters calldata parameters
    ) external returns (IERC20 token, IBondingCurveV1 curve) {
        curve = IBondingCurveV1(Clones.clone(implementation));
        token = IERC20(
            address(new LaunchToken("Vector Token", "VEC", address(curve), parameters.totalSupply))
        );
        address pair = VectorV2Factory(uniswapFactory).createPair(address(token), weth);
        ILaunchToken(address(token)).initializePair(pair);
        curve.initialize(
            LaunchTypes.CurveInitialization({
                factory: address(this),
                implementation: implementation,
                token: address(token),
                creator: creator,
                protocolTreasury: treasury,
                weth: weth,
                uniswapFactory: uniswapFactory,
                lpPair: pair,
                parameters: parameters
            })
        );
    }

    function executeBuy(IBondingCurveV1 curve, uint256 gross)
        external
        returns (uint256 tokensOut, uint256 grossUsed)
    {
        // Value only reaches a freshly initialized production curve clone.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        return curve.buy{ value: gross }(address(this), address(this), 0, type(uint256).max);
    }

    function executeSell(IERC20 token, IBondingCurveV1 curve, uint256 tokensIn)
        external
        returns (uint256 ethOut)
    {
        require(token.approve(address(curve), tokensIn), "APPROVE_FAILED");
        return curve.sell(tokensIn, address(this), 0, type(uint256).max);
    }

    function tradingPaused() external pure returns (bool) {
        return false;
    }

    receive() external payable { }
}

/// @notice Produces the byte-for-byte V1 fixture consumed by the Go curve mirror.
/// @dev Inputs select coverage cases; every expected amount, state, and revert payload comes
/// from the deployed V1 implementation and its public view/transaction paths.
contract GenerateCurveVectors is Script {
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint16 private constant ENGINE_VERSION = 1;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;
    uint256 private constant CASE_COUNT = 13;

    address private constant CREATOR = address(0xC0FFEE);
    address private constant TREASURY = address(0x7000);

    struct CurveState {
        LaunchTypes.Phase phase;
        uint256 virtualEth;
        uint256 virtualToken;
        uint256 tokensSold;
        uint256 realCurveEth;
        uint256 protocolFees;
        uint256 creatorFees;
    }

    struct CaseOutput {
        uint256 ethGross;
        uint256 ethRefund;
        uint256 ethOut;
        uint256 tokenAmount;
        uint256 protocolFee;
        uint256 creatorFee;
        bool graduates;
    }

    struct VectorCase {
        string id;
        string operation;
        CurveState initialState;
        uint256 inputEthGross;
        uint256 inputTokensIn;
        CaseOutput output;
        CurveState nextState;
        bool reverted;
        string errorName;
        bytes revertData;
    }

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

    BondingCurveV1 private _implementation;
    VectorWETH private _weth;
    VectorV2Factory private _uniswapFactory;
    VectorActor private _actor;

    function run() external {
        _implementation = new BondingCurveV1();
        require(_implementation.ENGINE_VERSION() == ENGINE_VERSION, "ENGINE_VERSION_MISMATCH");
        _weth = new VectorWETH();
        _uniswapFactory = new VectorV2Factory();
        _actor = new VectorActor();
        vm.deal(address(_actor), 100 ether);

        VectorCase[] memory cases = new VectorCase[](CASE_COUNT);
        cases[0] = _buyCase("buy_normal", 1 ether);
        cases[1] = _buyCase("buy_one_wei", 1);
        cases[2] = _buyCase("buy_fee_split_dust", 100);
        cases[3] = _buyCaseAfterBuy("buy_mid_curve", 1 ether, 0.5 ether);
        cases[4] = _buyJustBelowGraduationCase();

        (, IBondingCurveV1 boundaryCurve) = _newCurve();
        BuyQuote memory boundary = _quoteBuy(boundaryCurve, 10 ether);
        cases[5] = _buyCase("buy_final_exact", boundary.ethGross);
        cases[6] = _buyCase("buy_final_refund_and_graduation", 10 ether);
        cases[7] = _sellCase("sell_normal", false);
        cases[8] = _sellCase("sell_full", true);
        cases[9] = _invalidCase(
            "invalid_buy_zero_input", "buy", false, 0, ILaunchErrors.ZeroInput.selector, "ZeroInput"
        );
        cases[10] = _invalidCase(
            "invalid_sell_zero_input",
            "sell",
            false,
            0,
            ILaunchErrors.ZeroInput.selector,
            "ZeroInput"
        );
        cases[11] = _invalidCase(
            "invalid_sell_oversell", "sell", false, 1, ILaunchErrors.Oversell.selector, "Oversell"
        );
        cases[12] = _invalidCase(
            "invalid_sell_one_wei_zero_output",
            "sell",
            true,
            1,
            ILaunchErrors.ZeroOutput.selector,
            "ZeroOutput"
        );

        string memory outputPath =
            vm.envOr("CURVE_VECTORS_OUTPUT", string("./vectors/v1/curve-v1.json"));
        vm.writeFile(outputPath, string.concat(_artifactJson(cases), "\n"));
    }

    function _buyCase(string memory id, uint256 suppliedGross)
        private
        returns (VectorCase memory vector)
    {
        (, IBondingCurveV1 curve) = _newCurve();
        return _buyCaseOnCurve(id, curve, suppliedGross);
    }

    function _buyCaseAfterBuy(string memory id, uint256 initialGross, uint256 suppliedGross)
        private
        returns (VectorCase memory vector)
    {
        (, IBondingCurveV1 curve) = _newCurve();
        _executeBuy(curve, initialGross);
        return _buyCaseOnCurve(id, curve, suppliedGross);
    }

    function _buyJustBelowGraduationCase() private returns (VectorCase memory vector) {
        (, IBondingCurveV1 curve) = _newCurve();
        BuyQuote memory boundary = _quoteBuy(curve, 10 ether);
        require(boundary.graduates && boundary.refund > 0, "FINAL_BOUNDARY_QUOTE_MISSING");
        return _buyCaseOnCurve("buy_just_below_graduation", curve, boundary.ethGross - 1);
    }

    function _buyCaseOnCurve(string memory id, IBondingCurveV1 curve, uint256 suppliedGross)
        private
        returns (VectorCase memory vector)
    {
        vector.id = id;
        vector.operation = "buy";
        vector.initialState = _state(curve);
        vector.inputEthGross = suppliedGross;

        BuyQuote memory quote = _quoteBuy(curve, suppliedGross);
        (uint256 actualTokensOut, uint256 actualGrossUsed) = _executeBuy(curve, suppliedGross);
        require(actualTokensOut == quote.tokensOut, "BUY_TOKEN_RESULT_MISMATCH");
        require(actualGrossUsed == quote.ethGross, "BUY_GROSS_RESULT_MISMATCH");

        vector.output = CaseOutput({
            ethGross: quote.ethGross,
            ethRefund: quote.refund,
            ethOut: 0,
            tokenAmount: quote.tokensOut,
            protocolFee: quote.protocolFee,
            creatorFee: quote.creatorFee,
            graduates: quote.graduates
        });
        vector.nextState = _state(curve);
        require(
            (vector.nextState.phase == LaunchTypes.Phase.Graduated) == quote.graduates,
            "BUY_PHASE_MISMATCH"
        );
    }

    function _sellCase(string memory id, bool fullSell) private returns (VectorCase memory vector) {
        (IERC20 token, IBondingCurveV1 curve) = _newCurve();
        (uint256 purchased,) = _executeBuy(curve, 1 ether);
        uint256 tokensIn = fullSell ? purchased : purchased / 2;

        vector.id = id;
        vector.operation = "sell";
        vector.initialState = _state(curve);
        vector.inputTokensIn = tokensIn;

        SellQuote memory quote = _quoteSell(curve, tokensIn);
        uint256 actualEthOut = _actor.executeSell(token, curve, tokensIn);
        require(actualEthOut == quote.ethOut, "SELL_RESULT_MISMATCH");

        vector.output = CaseOutput({
            ethGross: quote.ethGross,
            ethRefund: 0,
            ethOut: quote.ethOut,
            tokenAmount: tokensIn,
            protocolFee: quote.protocolFee,
            creatorFee: quote.creatorFee,
            graduates: false
        });
        vector.nextState = _state(curve);
    }

    function _invalidCase(
        string memory id,
        string memory operation,
        bool prepareBuy,
        uint256 amount,
        bytes4 expectedSelector,
        string memory errorName
    ) private returns (VectorCase memory vector) {
        (, IBondingCurveV1 curve) = _newCurve();
        if (prepareBuy) _executeBuy(curve, 1 ether);

        vector.id = id;
        vector.operation = operation;
        vector.initialState = _state(curve);
        if (keccak256(bytes(operation)) == keccak256("buy")) {
            vector.inputEthGross = amount;
        } else {
            vector.inputTokensIn = amount;
        }

        bytes memory callData = keccak256(bytes(operation)) == keccak256("buy")
            ? abi.encodeCall(IBondingCurveV1.quoteBuy, (amount))
            : abi.encodeCall(IBondingCurveV1.quoteSell, (amount));
        (bool success, bytes memory revertData) = address(curve).staticcall(callData);
        require(!success, "EXPECTED_REVERT_MISSING");
        require(revertData.length >= 4, "REVERT_DATA_TOO_SHORT");
        bytes4 actualSelector;
        assembly ("memory-safe") {
            actualSelector := mload(add(revertData, 0x20))
        }
        require(actualSelector == expectedSelector, "REVERT_SELECTOR_MISMATCH");

        vector.nextState = _state(curve);
        vector.reverted = true;
        vector.errorName = errorName;
        vector.revertData = revertData;
    }

    function _newCurve() private returns (IERC20 token, IBondingCurveV1 curve) {
        return _actor.createCurve(
            address(_implementation),
            address(_weth),
            address(_uniswapFactory),
            CREATOR,
            TREASURY,
            _parameters()
        );
    }

    function _executeBuy(IBondingCurveV1 curve, uint256 gross)
        private
        returns (uint256 tokensOut, uint256 grossUsed)
    {
        return _actor.executeBuy(curve, gross);
    }

    function _quoteBuy(IBondingCurveV1 curve, uint256 gross)
        private
        view
        returns (BuyQuote memory quote)
    {
        (
            quote.ethGross,
            quote.tokensOut,
            quote.protocolFee,
            quote.creatorFee,
            quote.refund,
            quote.graduates
        ) = curve.quoteBuy(gross);
    }

    function _quoteSell(IBondingCurveV1 curve, uint256 tokensIn)
        private
        view
        returns (SellQuote memory quote)
    {
        (quote.ethOut, quote.ethGross, quote.protocolFee, quote.creatorFee) =
            curve.quoteSell(tokensIn);
    }

    function _state(IBondingCurveV1 curve) private view returns (CurveState memory) {
        return CurveState({
            phase: curve.phase(),
            virtualEth: curve.virtualEthReserve(),
            virtualToken: curve.virtualTokenReserve(),
            tokensSold: curve.tokensSold(),
            realCurveEth: curve.realCurveEth(),
            protocolFees: curve.unclaimedProtocolFees(),
            creatorFees: curve.unclaimedCreatorFees()
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

    function _artifactJson(VectorCase[] memory cases) private pure returns (string memory json) {
        json = string.concat(
            '{"$schema":"./curve.schema.json","schemaVersion":1,"engineVersion":',
            vm.toString(uint256(ENGINE_VERSION)),
            ',"amountEncoding":"uint256-decimal-string","parameters":',
            _parametersJson(),
            ',"cases":['
        );
        json = string.concat(
            json,
            _caseJson(cases[0]),
            ",",
            _caseJson(cases[1]),
            ",",
            _caseJson(cases[2]),
            ",",
            _caseJson(cases[3])
        );
        json = string.concat(
            json,
            ",",
            _caseJson(cases[4]),
            ",",
            _caseJson(cases[5]),
            ",",
            _caseJson(cases[6]),
            ",",
            _caseJson(cases[7])
        );
        json = string.concat(
            json,
            ",",
            _caseJson(cases[8]),
            ",",
            _caseJson(cases[9]),
            ",",
            _caseJson(cases[10]),
            ",",
            _caseJson(cases[11])
        );
        return string.concat(json, ",", _caseJson(cases[12]), "]}");
    }

    function _parametersJson() private pure returns (string memory json) {
        LaunchTypes.CurveParameters memory parameters = _parameters();
        json = string.concat(
            '{"totalSupply":"',
            vm.toString(parameters.totalSupply),
            '","curveTokens":"',
            vm.toString(parameters.curveTokens),
            '","lpTokens":"',
            vm.toString(parameters.lpTokens),
            '","graduationEth":"',
            vm.toString(parameters.graduationEth),
            '","initialVirtualEth":"',
            vm.toString(parameters.initialVirtualEth),
            '"'
        );
        return string.concat(
            json,
            ',"initialVirtualToken":"',
            vm.toString(parameters.initialVirtualToken),
            '","tradeFeeBps":',
            vm.toString(uint256(parameters.tradeFeeBps)),
            ',"protocolShareBps":',
            vm.toString(uint256(parameters.protocolShareBps)),
            "}"
        );
    }

    function _caseJson(VectorCase memory vector) private pure returns (string memory json) {
        json = string.concat(
            '{"id":"',
            vector.id,
            '","operation":"',
            vector.operation,
            '","initialState":',
            _stateJson(vector.initialState),
            ',"input":{"ethGross":"',
            vm.toString(vector.inputEthGross),
            '","tokensIn":"',
            vm.toString(vector.inputTokensIn),
            '"},"output":'
        );
        json = string.concat(
            json,
            vector.reverted ? "null" : _outputJson(vector.output),
            ',"nextState":',
            _stateJson(vector.nextState),
            ',"expectedRevert":',
            _revertJson(vector),
            "}"
        );
    }

    function _stateJson(CurveState memory state_) private pure returns (string memory json) {
        json = string.concat(
            '{"phase":"',
            state_.phase == LaunchTypes.Phase.Curve ? "curve" : "graduated",
            '","virtualEth":"',
            vm.toString(state_.virtualEth),
            '","virtualToken":"',
            vm.toString(state_.virtualToken),
            '","tokensSold":"',
            vm.toString(state_.tokensSold),
            '"'
        );
        return string.concat(
            json,
            ',"realCurveEth":"',
            vm.toString(state_.realCurveEth),
            '","protocolFees":"',
            vm.toString(state_.protocolFees),
            '","creatorFees":"',
            vm.toString(state_.creatorFees),
            '"}'
        );
    }

    function _outputJson(CaseOutput memory output) private pure returns (string memory json) {
        json = string.concat(
            '{"ethGross":"',
            vm.toString(output.ethGross),
            '","ethRefund":"',
            vm.toString(output.ethRefund),
            '","ethOut":"',
            vm.toString(output.ethOut),
            '","tokenAmount":"',
            vm.toString(output.tokenAmount),
            '"'
        );
        return string.concat(
            json,
            ',"protocolFee":"',
            vm.toString(output.protocolFee),
            '","creatorFee":"',
            vm.toString(output.creatorFee),
            '","graduates":',
            output.graduates ? "true" : "false",
            "}"
        );
    }

    function _revertJson(VectorCase memory vector) private pure returns (string memory) {
        if (!vector.reverted) return "null";
        return string.concat(
            '{"name":"', vector.errorName, '","data":"', vm.toString(vector.revertData), '"}'
        );
    }
}
