// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Script } from "forge-std/Script.sol";
import { DeploymentValidation } from "./deployment/DeploymentValidation.sol";
import { LocalUniswapV2Factory } from "./local/LocalUniswapV2Factory.sol";
import { LocalWETH } from "./local/LocalWETH.sol";

contract DeployTestnetDependencies is Script {
    function run() external returns (address weth, address uniswapFactory, bytes32 pairCodeHash) {
        DeploymentValidation.validateChain(
            DeploymentValidation.Target.RobinhoodTestnet, block.chainid
        );
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);
        LocalWETH localWeth = new LocalWETH();
        LocalUniswapV2Factory localFactory = new LocalUniswapV2Factory();
        vm.stopBroadcast();

        weth = address(localWeth);
        uniswapFactory = address(localFactory);
        pairCodeHash = localFactory.pairCodeHash();
        DeploymentValidation.DependencyEvidence memory evidence =
            DeploymentValidation.validateDependencies(
                DeploymentValidation.Target.RobinhoodTestnet,
                DeploymentValidation.Dependencies({
                    weth: weth,
                    uniswapFactory: uniswapFactory,
                    pairInitCodeHash: pairCodeHash,
                    expectedWethRuntimeCodeHash: weth.codehash,
                    expectedUniswapFactoryRuntimeCodeHash: uniswapFactory.codehash
                }),
                true
            );
        require(evidence.pairInitCodeHashVerified, "pair init-code hash not verified");
    }
}
