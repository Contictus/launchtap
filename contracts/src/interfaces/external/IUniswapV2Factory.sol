// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @dev Minimal Uniswap v2 factory interface. Task 11 verifies deployed compatibility.
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
