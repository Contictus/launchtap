// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LocalUniswapV2Factory } from "./LocalUniswapV2Factory.sol";
import { LocalUniswapV2Pair } from "./LocalUniswapV2Pair.sol";
import { LocalWETH } from "./LocalWETH.sol";

/// @dev Anvil-only Uniswap v2 router used by the real browser transaction gate.
contract LocalUniswapV2Router {
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    address public immutable factory;
    address public immutable WETH;

    constructor(address factory_, address weth_) {
        factory = factory_;
        WETH = weth_;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length == 2, "LocalRouter: path");
        address pair = LocalUniswapV2Factory(factory).getPair(path[0], path[1]);
        require(pair != address(0), "LocalRouter: pair");
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        (uint112 reserve0, uint112 reserve1,) = LocalUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) = path[0] == LocalUniswapV2Pair(pair).token0()
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "LocalRouter: liquidity");
        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        amounts[1] =
            (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
        require(amounts[1] > 0, "LocalRouter: output");
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "LocalRouter: expired");
        require(path.length == 2 && path[0] == WETH, "LocalRouter: path");
        amounts = this.getAmountsOut(msg.value, path);
        require(amounts[1] >= amountOutMin, "LocalRouter: slippage");
        LocalWETH(payable(WETH)).deposit{ value: msg.value }();
        address pair = LocalUniswapV2Factory(factory).getPair(path[0], path[1]);
        require(IERC20(WETH).transfer(pair, msg.value), "LocalRouter: transfer");
        _swap(pair, path[0], amounts[1], to);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "LocalRouter: expired");
        require(path.length == 2 && path[1] == WETH, "LocalRouter: path");
        amounts = this.getAmountsOut(amountIn, path);
        require(amounts[1] >= amountOutMin, "LocalRouter: slippage");
        address pair = LocalUniswapV2Factory(factory).getPair(path[0], path[1]);
        require(IERC20(path[0]).transferFrom(msg.sender, pair, amountIn), "LocalRouter: transfer");
        _swap(pair, path[0], amounts[1], address(this));
        LocalWETH(payable(WETH)).withdraw(amounts[1]);
        (bool sent,) = payable(to).call{ value: amounts[1] }("");
        require(sent, "LocalRouter: ETH transfer");
    }

    function _swap(address pair, address input, uint256 output, address to) private {
        address token0 = LocalUniswapV2Pair(pair).token0();
        uint256 amount0Out = input == token0 ? 0 : output;
        uint256 amount1Out = input == token0 ? output : 0;
        LocalUniswapV2Pair(pair).swap(amount0Out, amount1Out, to);
    }

    receive() external payable { }
}
