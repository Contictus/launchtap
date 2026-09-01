// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Task 1 compile probe. Production contracts begin in Task 2.
contract CompileProbe {
    function ceilDiv(uint256 value, uint256 divisor) external pure returns (uint256) {
        return Math.ceilDiv(value, divisor);
    }
}
