// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

interface ILaunchPause {
    function launchesPaused() external view returns (bool);
    function tradingPaused() external view returns (bool);
    function setLaunchesPaused(bool paused) external;
    function setTradingPaused(bool paused) external;
}
