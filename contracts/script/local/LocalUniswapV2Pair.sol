// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @dev Anvil/testnet-only Uniswap v2-compatible pair surface used by deployment simulations.
contract LocalUniswapV2Pair {
    using SafeCast for uint256;

    uint256 private constant MINIMUM_LIQUIDITY = 1000;

    address public immutable factory;
    address public token0;
    address public token1;
    uint256 public totalSupply;
    mapping(address account => uint256 balance) public balanceOf;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint112 reserve0, uint112 reserve1);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Transfer(address indexed from, address indexed to, uint256 amount);

    constructor() {
        factory = msg.sender;
    }

    function initialize(address token0_, address token1_) external {
        require(msg.sender == factory, "LocalV2: forbidden");
        require(token0 == address(0) && token1 == address(0), "LocalV2: initialized");
        require(token0_ != address(0) && token1_ != address(0), "LocalV2: zero token");
        token0 = token0_;
        token1 = token1_;
    }

    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    function mint(address to) external returns (uint256 liquidity) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        if (totalSupply == 0) {
            uint256 root = Math.sqrt(amount0 * amount1);
            require(root > MINIMUM_LIQUIDITY, "LocalV2: insufficient liquidity");
            liquidity = root - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity =
                _min((amount0 * totalSupply) / _reserve0, (amount1 * totalSupply) / _reserve1);
        }
        require(liquidity != 0, "LocalV2: insufficient liquidity minted");
        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external {
        require(amount0Out > 0 || amount1Out > 0, "LocalV2: insufficient output");
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "LocalV2: liquidity");
        if (amount0Out > 0) require(IERC20(token0).transfer(to, amount0Out), "LocalV2: transfer");
        if (amount1Out > 0) require(IERC20(token1).transfer(to, amount1Out), "LocalV2: transfer");
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0In = balance0 > uint256(_reserve0) - amount0Out
            ? balance0 - (uint256(_reserve0) - amount0Out)
            : 0;
        uint256 amount1In = balance1 > uint256(_reserve1) - amount1Out
            ? balance1 - (uint256(_reserve1) - amount1Out)
            : 0;
        require(amount0In > 0 || amount1In > 0, "LocalV2: insufficient input");
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        require(
            balance0Adjusted * balance1Adjusted
                >= uint256(_reserve0) * uint256(_reserve1) * 1_000_000,
            "LocalV2: invariant"
        );
        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function _mint(address to, uint256 amount) private {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        _reserve0 = balance0.toUint112();
        _reserve1 = balance1.toUint112();
        _blockTimestampLast = block.timestamp.toUint32();
        emit Sync(_reserve0, _reserve1);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
