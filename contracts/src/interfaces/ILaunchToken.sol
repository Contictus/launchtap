// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILaunchErrors } from "./ILaunchErrors.sol";

interface ILaunchToken is IERC20, ILaunchErrors {
    function curve() external view returns (address);
    function lpPair() external view returns (address);
    function graduated() external view returns (bool);
    function initializePair(address pair) external;
    function markGraduated() external;
}
