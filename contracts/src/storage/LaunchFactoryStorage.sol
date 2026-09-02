// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { LaunchTypes } from "../types/LaunchTypes.sol";

abstract contract LaunchFactoryStorage {
    struct EngineConfig {
        address implementation;
        bool enabled;
    }

    mapping(uint16 engineVersion => EngineConfig config) internal _engines;
    mapping(address treasury => uint256 amount) internal _launchFeesByTreasury;

    LaunchTypes.CurveParameters internal _futureParameters;
    address internal _futureProtocolTreasury;
    address internal _weth;
    address internal _uniswapFactory;
    address internal _pauseAuthority;
    address internal _timelock;
    uint256 internal _launchFee;
    bool internal _launchesPaused;
    bool internal _tradingPaused;
}
