// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { LocalUniswapV2Pair } from "./LocalUniswapV2Pair.sol";

/// @dev Anvil/testnet-only factory with canonical Uniswap v2 CREATE2 pair derivation.
contract LocalUniswapV2Factory {
    mapping(address token0 => mapping(address token1 => address pair)) public getPair;
    address[] public allPairs;

    event PairCreated(
        address indexed token0, address indexed token1, address pair, uint256 pairCount
    );

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(LocalUniswapV2Pair).creationCode);
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "LocalV2: identical addresses");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "LocalV2: zero address");
        require(getPair[token0][token1] == address(0), "LocalV2: pair exists");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new LocalUniswapV2Pair{ salt: salt }());
        // The pair is freshly deployed and cannot call back before this initialization.
        // forge-lint: disable-next-line(reentrancy-no-eth)
        LocalUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        // forge-lint: disable-next-line(reentrancy-events)
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
