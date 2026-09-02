// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { CurveMath } from "../../src/libraries/CurveMath.sol";

contract CurveMathHarness {
    function checkedAdd(uint256 a, uint256 b) external pure returns (uint256) {
        return CurveMath.checkedAdd(a, b);
    }

    function checkedMul(uint256 a, uint256 b) external pure returns (uint256) {
        return CurveMath.checkedMul(a, b);
    }

    function ceilDiv(uint256 numerator, uint256 denominator) external pure returns (uint256) {
        return CurveMath.ceilDiv(numerator, denominator);
    }

    function splitFees(uint256 gross, uint16 feeBps, uint16 protocolShareBps)
        external
        pure
        returns (uint256 totalFee, uint256 protocolFee, uint256 creatorFee)
    {
        return CurveMath.splitFees(gross, feeBps, protocolShareBps);
    }

    function exactGrossForNet(uint256 net, uint16 feeBps) external pure returns (uint256) {
        return CurveMath.exactGrossForNet(net, feeBps);
    }

    function quoteBuy(
        uint256 invariant,
        uint256 virtualEth,
        uint256 virtualToken,
        uint256 finalVirtualToken,
        uint256 suppliedGross,
        uint16 feeBps,
        uint16 protocolShareBps
    ) external pure returns (CurveMath.BuyQuote memory) {
        return CurveMath.quoteBuy(
            invariant,
            virtualEth,
            virtualToken,
            finalVirtualToken,
            suppliedGross,
            feeBps,
            protocolShareBps
        );
    }

    function quoteSell(
        uint256 invariant,
        uint256 virtualEth,
        uint256 virtualToken,
        uint256 soldTokens,
        uint256 tokensIn,
        uint16 feeBps,
        uint16 protocolShareBps
    ) external pure returns (CurveMath.SellQuote memory) {
        return CurveMath.quoteSell(
            invariant, virtualEth, virtualToken, soldTokens, tokensIn, feeBps, protocolShareBps
        );
    }

    function spotPriceWad(uint256 virtualEth, uint256 virtualToken)
        external
        pure
        returns (uint256)
    {
        return CurveMath.spotPriceWad(virtualEth, virtualToken);
    }

    function tokensSold(uint256 initialVirtualToken, uint256 virtualToken)
        external
        pure
        returns (uint256)
    {
        return CurveMath.tokensSold(initialVirtualToken, virtualToken);
    }

    function realCurveEth(uint256 virtualEth, uint256 initialVirtualEth)
        external
        pure
        returns (uint256)
    {
        return CurveMath.realCurveEth(virtualEth, initialVirtualEth);
    }
}
