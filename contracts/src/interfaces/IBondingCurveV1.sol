// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { ICurveClaims } from "./ICurveClaims.sol";
import { ILaunchErrors } from "./ILaunchErrors.sol";
import { ILaunchEvents } from "./ILaunchEvents.sol";
import { LaunchTypes } from "../types/LaunchTypes.sol";

interface IBondingCurveV1 is ICurveClaims, ILaunchErrors, ILaunchEvents {
    // forge-lint: disable-next-line(mixed-case-function)
    function ENGINE_VERSION() external view returns (uint16);
    function initialize(LaunchTypes.CurveInitialization calldata initialization) external;

    function buy(
        address tokenRecipient,
        address refundRecipient,
        uint256 minTokensOut,
        uint256 deadline
    ) external payable returns (uint256 tokensOut, uint256 ethGrossUsed);

    function buyFor(
        address trader,
        address tokenRecipient,
        address refundRecipient,
        uint256 minTokensOut,
        uint256 deadline
    ) external payable returns (uint256 tokensOut, uint256 ethGrossUsed);

    function sell(uint256 tokensIn, address ethRecipient, uint256 minEthOut, uint256 deadline)
        external
        returns (uint256 ethOut);

    function quoteBuy(uint256 ethGross)
        external
        view
        returns (
            uint256 ethGrossUsed,
            uint256 tokensOut,
            uint256 protocolFee,
            uint256 creatorFee,
            uint256 refund,
            bool graduates
        );

    function quoteSell(uint256 tokensIn)
        external
        view
        returns (uint256 ethOut, uint256 ethGross, uint256 protocolFee, uint256 creatorFee);

    function phase() external view returns (LaunchTypes.Phase);
    function token() external view returns (address);
    function creator() external view returns (address);
    function protocolTreasury() external view returns (address);
    function implementation() external view returns (address);
    function weth() external view returns (address);
    function uniswapFactory() external view returns (address);
    function lpPair() external view returns (address);
    function virtualEthReserve() external view returns (uint256);
    function virtualTokenReserve() external view returns (uint256);
    function realCurveEth() external view returns (uint256);
    function tokensSold() external view returns (uint256);
}
