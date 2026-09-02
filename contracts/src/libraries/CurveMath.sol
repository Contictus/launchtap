// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ILaunchErrors } from "../interfaces/ILaunchErrors.sol";

library CurveMath {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant WAD = 1e18;

    struct BuyQuote {
        uint256 ethGrossUsed;
        uint256 tokensOut;
        uint256 protocolFee;
        uint256 creatorFee;
        uint256 refund;
        uint256 newVirtualEth;
        uint256 newVirtualToken;
        bool graduates;
    }

    struct SellQuote {
        uint256 ethOut;
        uint256 ethGross;
        uint256 protocolFee;
        uint256 creatorFee;
        uint256 newVirtualEth;
        uint256 newVirtualToken;
    }

    function checkedAdd(uint256 a, uint256 b) internal pure returns (uint256 result) {
        bool success;
        (success, result) = Math.tryAdd(a, b);
        if (!success) revert ILaunchErrors.ArithmeticOverflow();
    }

    function checkedMul(uint256 a, uint256 b) internal pure returns (uint256 result) {
        bool success;
        (success, result) = Math.tryMul(a, b);
        if (!success) revert ILaunchErrors.ArithmeticOverflow();
    }

    function ceilDiv(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) revert ILaunchErrors.DivisionByZero();
        if (numerator == 0) return 0;

        unchecked {
            return ((numerator - 1) / denominator) + 1;
        }
    }

    function splitFees(uint256 gross, uint16 feeBps, uint16 protocolShareBps)
        internal
        pure
        returns (uint256 totalFee, uint256 protocolFee, uint256 creatorFee)
    {
        if (feeBps >= BPS_DENOMINATOR) {
            revert ILaunchErrors.InvalidTradeFeeBps(feeBps);
        }
        if (protocolShareBps > BPS_DENOMINATOR) {
            revert ILaunchErrors.InvalidProtocolShareBps(protocolShareBps);
        }

        totalFee = Math.mulDiv(gross, feeBps, BPS_DENOMINATOR);
        protocolFee = Math.mulDiv(totalFee, protocolShareBps, BPS_DENOMINATOR);
        creatorFee = totalFee - protocolFee;
    }

    function exactGrossForNet(uint256 net, uint16 feeBps) internal pure returns (uint256) {
        if (net == 0) revert ILaunchErrors.ZeroInput();
        if (feeBps >= BPS_DENOMINATOR) {
            revert ILaunchErrors.InvalidTradeFeeBps(feeBps);
        }

        uint256 grossMinusOne =
            Math.mulDiv(net - 1, BPS_DENOMINATOR, BPS_DENOMINATOR - uint256(feeBps));
        return checkedAdd(grossMinusOne, 1);
    }

    function quoteBuy(
        uint256 invariant,
        uint256 virtualEth,
        uint256 virtualToken,
        uint256 finalVirtualToken,
        uint256 suppliedGross,
        uint16 feeBps,
        uint16 protocolShareBps
    ) internal pure returns (BuyQuote memory quote) {
        if (suppliedGross == 0) revert ILaunchErrors.ZeroInput();

        (uint256 totalFee, uint256 protocolFee, uint256 creatorFee) =
            splitFees(suppliedGross, feeBps, protocolShareBps);
        uint256 effectiveEth = suppliedGross - totalFee;
        uint256 candidateVirtualEth = checkedAdd(virtualEth, effectiveEth);
        uint256 candidateVirtualToken = ceilDiv(invariant, candidateVirtualEth);
        uint256 finalVirtualEth = ceilDiv(invariant, finalVirtualToken);

        if (candidateVirtualToken >= virtualToken) revert ILaunchErrors.ZeroOutput();

        if (candidateVirtualEth > finalVirtualEth) {
            uint256 netNeeded = finalVirtualEth - virtualEth;
            quote.ethGrossUsed = exactGrossForNet(netNeeded, feeBps);

            (totalFee, protocolFee, creatorFee) =
                splitFees(quote.ethGrossUsed, feeBps, protocolShareBps);
            quote.newVirtualEth = finalVirtualEth;
            quote.newVirtualToken = finalVirtualToken;
            quote.refund = suppliedGross - quote.ethGrossUsed;
            quote.graduates = true;
        } else {
            quote.ethGrossUsed = suppliedGross;
            quote.newVirtualEth = candidateVirtualEth;
            quote.newVirtualToken = candidateVirtualToken;
            quote.graduates = candidateVirtualToken == finalVirtualToken;
        }

        quote.tokensOut = virtualToken - quote.newVirtualToken;
        if (quote.tokensOut == 0) revert ILaunchErrors.ZeroOutput();
        quote.protocolFee = protocolFee;
        quote.creatorFee = creatorFee;
    }

    function quoteSell(
        uint256 invariant,
        uint256 virtualEth,
        uint256 virtualToken,
        uint256 soldTokens,
        uint256 tokensIn,
        uint16 feeBps,
        uint16 protocolShareBps
    ) internal pure returns (SellQuote memory quote) {
        if (tokensIn == 0) revert ILaunchErrors.ZeroInput();
        if (tokensIn > soldTokens) revert ILaunchErrors.Oversell(tokensIn, soldTokens);

        quote.newVirtualToken = checkedAdd(virtualToken, tokensIn);
        quote.newVirtualEth = ceilDiv(invariant, quote.newVirtualToken);
        quote.ethGross = virtualEth - quote.newVirtualEth;
        if (quote.ethGross == 0) revert ILaunchErrors.ZeroOutput();

        (uint256 totalFee, uint256 protocolFee, uint256 creatorFee) =
            splitFees(quote.ethGross, feeBps, protocolShareBps);
        quote.ethOut = quote.ethGross - totalFee;
        if (quote.ethOut == 0) revert ILaunchErrors.ZeroOutput();
        quote.protocolFee = protocolFee;
        quote.creatorFee = creatorFee;
    }

    function spotPriceWad(uint256 virtualEth, uint256 virtualToken)
        internal
        pure
        returns (uint256)
    {
        if (virtualToken == 0) revert ILaunchErrors.DivisionByZero();
        return Math.mulDiv(virtualEth, WAD, virtualToken);
    }

    function tokensSold(uint256 initialVirtualToken, uint256 virtualToken)
        internal
        pure
        returns (uint256)
    {
        return initialVirtualToken - virtualToken;
    }

    function realCurveEth(uint256 virtualEth, uint256 initialVirtualEth)
        internal
        pure
        returns (uint256)
    {
        return virtualEth - initialVirtualEth;
    }
}
