// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @dev Minimal WETH interface used by graduation. Task 11 verifies deployed compatibility.
interface IWETH {
    function deposit() external payable;
    function transfer(address recipient, uint256 amount) external returns (bool);
}
