// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { LaunchTypes } from "../types/LaunchTypes.sol";

/// @dev Storage-based reentrancy protection is intentional until Robinhood Chain support for
/// EIP-1153 is proven. This layout is frozen by the Task 2 golden artifact.
abstract contract BondingCurveV1Storage is ReentrancyGuard {
    uint16 public constant ENGINE_VERSION = 1;

    bool internal _initialized;
    LaunchTypes.Phase internal _phase;
    uint16 internal _tradeFeeBps;
    uint16 internal _protocolShareBps;

    address internal _factory;
    address internal _implementation;
    address internal _token;
    address internal _creator;
    address internal _protocolTreasury;
    address internal _weth;
    address internal _uniswapFactory;
    address internal _lpPair;

    uint256 internal _totalSupply;
    uint256 internal _curveTokens;
    uint256 internal _lpTokens;
    uint256 internal _graduationEth;
    uint256 internal _initialVirtualEth;
    uint256 internal _initialVirtualToken;
    uint256 internal _invariant;
    uint256 internal _virtualEthReserve;
    uint256 internal _virtualTokenReserve;

    uint256 internal _unclaimedCreatorFees;
    uint256 internal _unclaimedProtocolFees;
    uint256 internal _totalPendingRefunds;
    mapping(address account => uint256 amount) internal _pendingRefunds;
}
