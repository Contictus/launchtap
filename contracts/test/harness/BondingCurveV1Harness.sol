// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { BondingCurveV1 } from "../../src/BondingCurveV1.sol";
import { LaunchTypes } from "../../src/types/LaunchTypes.sol";

contract BondingCurveV1Harness is BondingCurveV1 {
    function initialized() external view returns (bool) {
        return _initialized;
    }

    function factorySnapshot() external view returns (address) {
        return _factory;
    }

    function implementationSnapshot() external view returns (address) {
        return _implementation;
    }

    function wethSnapshot() external view returns (address) {
        return _weth;
    }

    function uniswapFactorySnapshot() external view returns (address) {
        return _uniswapFactory;
    }

    function totalSupplySnapshot() external view returns (uint256) {
        return _totalSupply;
    }

    function curveTokensSnapshot() external view returns (uint256) {
        return _curveTokens;
    }

    function lpTokensSnapshot() external view returns (uint256) {
        return _lpTokens;
    }

    function graduationEthSnapshot() external view returns (uint256) {
        return _graduationEth;
    }

    function initialVirtualEthSnapshot() external view returns (uint256) {
        return _initialVirtualEth;
    }

    function initialVirtualTokenSnapshot() external view returns (uint256) {
        return _initialVirtualToken;
    }

    function curveInvariantSnapshot() external view returns (uint256) {
        return _invariant;
    }

    function tradeFeeBpsSnapshot() external view returns (uint16) {
        return _tradeFeeBps;
    }

    function protocolShareBpsSnapshot() external view returns (uint16) {
        return _protocolShareBps;
    }

    function totalPendingRefunds() external view returns (uint256) {
        return _totalPendingRefunds;
    }

    function setPhase(LaunchTypes.Phase phase_) external {
        _phase = phase_;
    }
}
