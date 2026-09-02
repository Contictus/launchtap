// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

library LaunchTypes {
    enum Phase {
        Curve,
        Graduated
    }

    struct CurveParameters {
        uint256 totalSupply;
        uint256 curveTokens;
        uint256 lpTokens;
        uint256 graduationEth;
        uint256 initialVirtualEth;
        uint256 initialVirtualToken;
        uint16 tradeFeeBps;
        uint16 protocolShareBps;
    }

    struct CurveInitialization {
        address factory;
        address implementation;
        address token;
        address creator;
        address protocolTreasury;
        address weth;
        address uniswapFactory;
        address lpPair;
        CurveParameters parameters;
    }

    struct LaunchRequest {
        string name;
        string symbol;
        uint16 engineVersion;
        uint256 developerBuyGross;
        uint256 minDeveloperTokensOut;
        uint256 deadline;
    }

    struct FactoryDefaults {
        CurveParameters parameters;
        address weth;
        address uniswapFactory;
        uint256 launchFee;
    }

    struct FactoryInitialization {
        address pauseAuthority;
        address timelock;
        address protocolTreasury;
        uint16 engineVersion;
        address implementation;
        FactoryDefaults defaults;
    }
}
