// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { BondingCurveV1Storage } from "./storage/BondingCurveV1Storage.sol";
import { CurveMath } from "./libraries/CurveMath.sol";
import { ILaunchErrors } from "./interfaces/ILaunchErrors.sol";
import { IUniswapV2Factory } from "./interfaces/external/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "./interfaces/external/IUniswapV2Pair.sol";
import { LaunchTypes } from "./types/LaunchTypes.sol";

contract BondingCurveV1 is BondingCurveV1Storage, ILaunchErrors {
    bytes32 private constant FIELD_FACTORY = "factory";
    bytes32 private constant FIELD_IMPLEMENTATION = "implementation";
    bytes32 private constant FIELD_TOKEN = "token";
    bytes32 private constant FIELD_CREATOR = "creator";
    bytes32 private constant FIELD_PROTOCOL_TREASURY = "protocolTreasury";
    bytes32 private constant FIELD_WETH = "weth";
    bytes32 private constant FIELD_UNISWAP_FACTORY = "uniswapFactory";
    bytes32 private constant FIELD_LP_PAIR = "lpPair";

    constructor() {
        _implementation = address(this);
        _initialized = true;
    }

    function initialize(LaunchTypes.CurveInitialization calldata initialization)
        external
        nonReentrant
    {
        if (_implementation == address(this)) {
            revert ImplementationInitializationDisabled();
        }
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        _validateAddress(initialization.factory, FIELD_FACTORY);
        if (msg.sender != initialization.factory) revert UnauthorizedFactory(msg.sender);
        _validateAddress(initialization.implementation, FIELD_IMPLEMENTATION);
        if (initialization.implementation == address(this)) {
            revert ImplementationInitializationDisabled();
        }
        _validateAddress(initialization.token, FIELD_TOKEN);
        _validateAddress(initialization.creator, FIELD_CREATOR);
        _validateAddress(initialization.protocolTreasury, FIELD_PROTOCOL_TREASURY);
        _validateAddress(initialization.weth, FIELD_WETH);
        _validateAddress(initialization.uniswapFactory, FIELD_UNISWAP_FACTORY);
        _validateAddress(initialization.lpPair, FIELD_LP_PAIR);

        LaunchTypes.CurveParameters calldata parameters = initialization.parameters;
        _validateParameters(parameters);
        _validatePair(initialization);

        uint256 invariant =
            CurveMath.checkedMul(parameters.initialVirtualEth, parameters.initialVirtualToken);

        _phase = LaunchTypes.Phase.Curve;
        _tradeFeeBps = parameters.tradeFeeBps;
        _protocolShareBps = parameters.protocolShareBps;
        _factory = initialization.factory;
        _implementation = initialization.implementation;
        _token = initialization.token;
        _creator = initialization.creator;
        _protocolTreasury = initialization.protocolTreasury;
        _weth = initialization.weth;
        _uniswapFactory = initialization.uniswapFactory;
        _lpPair = initialization.lpPair;
        _totalSupply = parameters.totalSupply;
        _curveTokens = parameters.curveTokens;
        _lpTokens = parameters.lpTokens;
        _graduationEth = parameters.graduationEth;
        _initialVirtualEth = parameters.initialVirtualEth;
        _initialVirtualToken = parameters.initialVirtualToken;
        _invariant = invariant;
        _virtualEthReserve = parameters.initialVirtualEth;
        _virtualTokenReserve = parameters.initialVirtualToken;
    }

    function quoteBuy(uint256 ethGross)
        external
        view
        returns (
            uint256 ethGrossUsed,
            uint256 tokensOut,
            uint256 protocolFee,
            uint256 creatorFee,
            uint256 refund,
            bool graduates
        )
    {
        _requireCurvePhase();
        CurveMath.BuyQuote memory quote = CurveMath.quoteBuy(
            _invariant,
            _virtualEthReserve,
            _virtualTokenReserve,
            _initialVirtualToken - _curveTokens,
            ethGross,
            _tradeFeeBps,
            _protocolShareBps
        );
        return (
            quote.ethGrossUsed,
            quote.tokensOut,
            quote.protocolFee,
            quote.creatorFee,
            quote.refund,
            quote.graduates
        );
    }

    function quoteSell(uint256 tokensIn)
        external
        view
        returns (uint256 ethOut, uint256 ethGross, uint256 protocolFee, uint256 creatorFee)
    {
        _requireCurvePhase();
        CurveMath.SellQuote memory quote = CurveMath.quoteSell(
            _invariant,
            _virtualEthReserve,
            _virtualTokenReserve,
            CurveMath.tokensSold(_initialVirtualToken, _virtualTokenReserve),
            tokensIn,
            _tradeFeeBps,
            _protocolShareBps
        );
        return (quote.ethOut, quote.ethGross, quote.protocolFee, quote.creatorFee);
    }

    function phase() external view returns (LaunchTypes.Phase) {
        return _phase;
    }

    function token() external view returns (address) {
        return _token;
    }

    function creator() external view returns (address) {
        return _creator;
    }

    function protocolTreasury() external view returns (address) {
        return _protocolTreasury;
    }

    function lpPair() external view returns (address) {
        return _lpPair;
    }

    function virtualEthReserve() external view returns (uint256) {
        return _virtualEthReserve;
    }

    function virtualTokenReserve() external view returns (uint256) {
        return _virtualTokenReserve;
    }

    function realCurveEth() external view returns (uint256) {
        return CurveMath.realCurveEth(_virtualEthReserve, _initialVirtualEth);
    }

    function tokensSold() external view returns (uint256) {
        return CurveMath.tokensSold(_initialVirtualToken, _virtualTokenReserve);
    }

    function _validateParameters(LaunchTypes.CurveParameters calldata parameters) private pure {
        uint256 allocatedSupply = CurveMath.checkedAdd(parameters.curveTokens, parameters.lpTokens);
        if (parameters.totalSupply != allocatedSupply) {
            revert InvalidSupplyAllocation(
                parameters.totalSupply, parameters.curveTokens, parameters.lpTokens
            );
        }
        if (parameters.lpTokens == 0 || parameters.curveTokens <= parameters.lpTokens) {
            revert InvalidCurveAllocation(parameters.curveTokens, parameters.lpTokens);
        }
        if (parameters.graduationEth == 0) revert InvalidGraduationEth();
        if (
            parameters.initialVirtualEth == 0
                || parameters.initialVirtualToken <= parameters.curveTokens
        ) {
            revert InvalidVirtualReserves(
                parameters.initialVirtualEth, parameters.initialVirtualToken, parameters.curveTokens
            );
        }
        if (parameters.tradeFeeBps >= CurveMath.BPS_DENOMINATOR) {
            revert InvalidTradeFeeBps(parameters.tradeFeeBps);
        }
        if (parameters.protocolShareBps > CurveMath.BPS_DENOMINATOR) {
            revert InvalidProtocolShareBps(parameters.protocolShareBps);
        }

        uint256 invariant =
            CurveMath.checkedMul(parameters.initialVirtualEth, parameters.initialVirtualToken);
        uint256 finalVirtualToken = parameters.initialVirtualToken - parameters.curveTokens;
        uint256 finalVirtualEth =
            CurveMath.checkedAdd(parameters.initialVirtualEth, parameters.graduationEth);
        if (
            CurveMath.ceilDiv(invariant, finalVirtualToken) != finalVirtualEth
                || CurveMath.ceilDiv(invariant, finalVirtualEth) != finalVirtualToken
        ) {
            revert InvalidCurveBoundary(invariant, finalVirtualToken, finalVirtualEth);
        }
    }

    function _validatePair(LaunchTypes.CurveInitialization calldata initialization) private view {
        address expectedPair = IUniswapV2Factory(initialization.uniswapFactory)
            .getPair(initialization.token, initialization.weth);
        if (expectedPair != initialization.lpPair) {
            revert PairNotCanonical(expectedPair, initialization.lpPair);
        }

        address actualFactory = IUniswapV2Pair(initialization.lpPair).factory();
        if (actualFactory != initialization.uniswapFactory) {
            revert PairFactoryMismatch(initialization.uniswapFactory, actualFactory);
        }

        address token0 = IUniswapV2Pair(initialization.lpPair).token0();
        address token1 = IUniswapV2Pair(initialization.lpPair).token1();
        bool correctOrder = token0 == initialization.token && token1 == initialization.weth;
        bool reverseOrder = token0 == initialization.weth && token1 == initialization.token;
        if (!correctOrder && !reverseOrder) revert PairTokensMismatch(token0, token1);
    }

    function _validateAddress(address account, bytes32 field) private pure {
        if (account == address(0)) revert ZeroAddress(field);
    }

    function _requireCurvePhase() private view {
        if (_phase != LaunchTypes.Phase.Curve) {
            revert WrongPhase(uint8(LaunchTypes.Phase.Curve), uint8(_phase));
        }
    }
}
