// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Stable V1 event contract consumed by the launchpad indexer.
interface ILaunchEvents {
    event TokenLaunched(
        address indexed token,
        address indexed curve,
        address indexed creator,
        address lpPair,
        address weth,
        address protocolTreasury,
        uint16 engineVersion,
        string name,
        string symbol,
        uint256 totalSupply,
        uint256 virtualEth,
        uint256 virtualToken,
        uint256 curveTokens,
        uint256 lpTokens,
        uint256 graduationEth,
        uint256 launchFeePaid,
        uint16 tradeFeeBps,
        uint16 protocolShareBps
    );

    /// @param ethGross Gross ETH consumed by the trade, excluding any final-fill excess.
    /// @param ethRefund Excess ETH not consumed by a buy; zero for sells and buys without excess.
    /// @param tokenAmount Tokens received on a buy or supplied on a sell.
    /// @param newEthReserve Post-trade virtual ETH reserve `x`.
    /// @param newTokenReserve Post-trade virtual token reserve `y`.
    /// @dev Consumers can read real curve ETH from `IBondingCurveV1.realCurveEth()`. Spot
    /// price derives from `newEthReserve / newTokenReserve`. For every buy, ETH supplied to
    /// the curve equals `ethGross + ethRefund`. A failed immediate refund still records
    /// `ethRefund`; RefundCredited additionally records the pull-payment balance. Sells set
    /// `ethRefund` to zero, including when failed proceeds create a refund credit.
    event Trade(
        address indexed token,
        address indexed trader,
        bool isBuy,
        uint256 ethGross,
        uint256 ethRefund,
        uint256 tokenAmount,
        uint256 protocolFee,
        uint256 creatorFee,
        uint256 newEthReserve,
        uint256 newTokenReserve
    );

    event Graduated(
        address indexed token,
        address indexed lpPair,
        uint256 ethToPool,
        uint256 tokensToPool,
        uint256 lpLiquidityBurned
    );

    event CreatorFeesClaimed(address indexed token, address indexed creator, uint256 amount);
    event ProtocolFeesClaimed(address indexed token, address indexed treasury, uint256 amount);
    event LaunchFeesClaimed(address indexed treasury, uint256 amount);
    event RefundCredited(address indexed token, address indexed account, uint256 amount);
    event RefundClaimed(address indexed token, address indexed account, uint256 amount);
    event LaunchPauseSet(bool paused);
    event TradingPauseSet(bool paused);
    event EngineConfigured(
        uint16 indexed engineVersion, address indexed implementation, bool enabled
    );
    event FutureDefaultsConfigured(bytes32 indexed configHash);
    event FutureTreasuryConfigured(address indexed previousTreasury, address indexed newTreasury);
}
