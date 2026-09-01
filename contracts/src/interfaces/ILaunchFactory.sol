// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IFactoryClaims } from "./IFactoryClaims.sol";
import { ILaunchErrors } from "./ILaunchErrors.sol";
import { ILaunchEvents } from "./ILaunchEvents.sol";
import { ILaunchPause } from "./ILaunchPause.sol";
import { LaunchTypes } from "../types/LaunchTypes.sol";

interface ILaunchFactory is IFactoryClaims, ILaunchErrors, ILaunchEvents, ILaunchPause {
    function launch(LaunchTypes.LaunchRequest calldata request)
        external
        payable
        returns (address token, address curve, address lpPair);

    function curveImplementation(uint16 engineVersion) external view returns (address);
    function engineEnabled(uint16 engineVersion) external view returns (bool);
    function protocolTreasury() external view returns (address);
    function launchFee() external view returns (uint256);
}
