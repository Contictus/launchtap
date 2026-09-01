// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { CompileProbe } from "../src/CompileProbe.sol";

contract CompileProbeTest is Test {
    function testPinnedLibrariesCompileAndExecute() external {
        CompileProbe probe = new CompileProbe();

        assertEq(probe.ceilDiv(10, 3), 4);
    }
}
