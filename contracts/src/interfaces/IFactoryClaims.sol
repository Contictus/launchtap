// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

interface IFactoryClaims {
    function claimLaunchFees() external returns (uint256 amount);
    function launchFeesByTreasury(address treasury) external view returns (uint256);
}
