// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { ICurveClaims } from "../src/interfaces/ICurveClaims.sol";
import { IFactoryClaims } from "../src/interfaces/IFactoryClaims.sol";
import { ILaunchErrors } from "../src/interfaces/ILaunchErrors.sol";
import { ILaunchFactory } from "../src/interfaces/ILaunchFactory.sol";
import { ILaunchPause } from "../src/interfaces/ILaunchPause.sol";
import { ILaunchToken } from "../src/interfaces/ILaunchToken.sol";
import { IUniswapV2Factory } from "../src/interfaces/external/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "../src/interfaces/external/IUniswapV2Pair.sol";
import { IWETH } from "../src/interfaces/external/IWETH.sol";
import { BondingCurveV1StorageHarness } from "./harness/BondingCurveV1StorageHarness.sol";
import { LaunchFactoryStorageHarness } from "./harness/LaunchFactoryStorageHarness.sol";
import { LaunchTokenStorageHarness } from "./harness/LaunchTokenStorageHarness.sol";

contract InterfaceDeclarationsTest is Test {
    function testEngineVersionIsV1() external {
        BondingCurveV1StorageHarness harness = new BondingCurveV1StorageHarness();

        assertEq(uint256(harness.ENGINE_VERSION()), 1);
    }

    function testInterfacesExposeSelectors() external pure {
        assertTrue(IBondingCurveV1.initialize.selector != bytes4(0));
        assertTrue(ICurveClaims.claimRefund.selector != bytes4(0));
        assertTrue(IFactoryClaims.claimLaunchFees.selector != bytes4(0));
        assertTrue(ILaunchErrors.ZeroOutput.selector != bytes4(0));
        assertTrue(ILaunchFactory.launch.selector != bytes4(0));
        assertTrue(ILaunchPause.setTradingPaused.selector != bytes4(0));
        assertTrue(ILaunchToken.markGraduated.selector != bytes4(0));
        assertTrue(IUniswapV2Factory.getPair.selector != bytes4(0));
        assertTrue(IUniswapV2Pair.mint.selector != bytes4(0));
        assertTrue(IWETH.deposit.selector != bytes4(0));
    }

    function testStorageHarnessesCompile() external pure {
        assertTrue(type(BondingCurveV1StorageHarness).creationCode.length > 0);
        assertTrue(type(LaunchFactoryStorageHarness).creationCode.length > 0);
        assertTrue(type(LaunchTokenStorageHarness).creationCode.length > 0);
    }
}
