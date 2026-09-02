// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IUniswapV2Factory } from "../../src/interfaces/external/IUniswapV2Factory.sol";

library DeploymentValidation {
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;

    address internal constant ROBINHOOD_MAINNET_UNISWAP_FACTORY =
        0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    address internal constant ROBINHOOD_MAINNET_WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    bytes32 internal constant CANONICAL_UNISWAP_V2_PAIR_INIT_CODE_HASH =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    address private constant PROBE_TOKEN_A = 0x0000000000000000000000000000000000001001;
    address private constant PROBE_TOKEN_B = 0x0000000000000000000000000000000000001002;

    enum Target {
        Anvil,
        RobinhoodTestnet,
        RobinhoodMainnet
    }

    struct Dependencies {
        address weth;
        address uniswapFactory;
        bytes32 pairInitCodeHash;
        bytes32 expectedWethRuntimeCodeHash;
        bytes32 expectedUniswapFactoryRuntimeCodeHash;
    }

    struct DependencyEvidence {
        bytes32 wethRuntimeCodeHash;
        bytes32 uniswapFactoryRuntimeCodeHash;
        bool pairInitCodeHashVerified;
    }

    error AuthorityIsDeployer(bytes32 field, address deployer);
    error ChainIdMismatch(uint256 expected, uint256 actual);
    error DependencyHasNoCode(bytes32 field, address dependency);
    error DependencyRuntimeCodeHashMismatch(bytes32 field, bytes32 expected, bytes32 actual);
    error DependencyReviewRequired();
    error InvalidAuthority(bytes32 field, address authority);
    error InvalidPairInitCodeHash(bytes32 expected, bytes32 actual);
    error MainnetDependencyMismatch(bytes32 field, address expected, address actual);
    error PairAddressMismatch(address expected, address actual);
    error TestnetUsesMainnetDependency(bytes32 field, address dependency);

    function validateChain(Target target, uint256 chainId) internal pure {
        uint256 expected;
        if (target == Target.Anvil) expected = ANVIL_CHAIN_ID;
        else if (target == Target.RobinhoodTestnet) expected = ROBINHOOD_TESTNET_CHAIN_ID;
        else expected = ROBINHOOD_MAINNET_CHAIN_ID;

        if (chainId != expected) revert ChainIdMismatch(expected, chainId);
    }

    function validateAuthorities(
        Target target,
        address deployer,
        address pauseAuthority,
        address timelock,
        address protocolTreasury
    ) internal pure {
        _nonzero("pauseAuthority", pauseAuthority);
        _nonzero("timelock", timelock);
        _nonzero("protocolTreasury", protocolTreasury);
        if (pauseAuthority == deployer) revert AuthorityIsDeployer("pauseAuthority", deployer);
        if (timelock == deployer) revert AuthorityIsDeployer("timelock", deployer);
        if (pauseAuthority == timelock) revert InvalidAuthority("timelock", timelock);
        if (target == Target.RobinhoodMainnet && protocolTreasury == deployer) {
            revert AuthorityIsDeployer("protocolTreasury", deployer);
        }
    }

    function validateDependencies(
        Target target,
        Dependencies memory dependencies,
        bool dependenciesReviewed
    ) internal returns (DependencyEvidence memory evidence) {
        if (target != Target.Anvil && !dependenciesReviewed) {
            revert DependencyReviewRequired();
        }
        if (target == Target.RobinhoodTestnet) _rejectMainnetDependencies(dependencies);
        if (target == Target.RobinhoodMainnet) _requireMainnetDependencies(dependencies);

        if (dependencies.weth.code.length == 0) {
            revert DependencyHasNoCode("weth", dependencies.weth);
        }
        if (dependencies.uniswapFactory.code.length == 0) {
            revert DependencyHasNoCode("uniswapFactory", dependencies.uniswapFactory);
        }
        if (dependencies.pairInitCodeHash == bytes32(0)) {
            revert InvalidPairInitCodeHash(bytes32(uint256(1)), bytes32(0));
        }

        evidence.wethRuntimeCodeHash = dependencies.weth.codehash;
        evidence.uniswapFactoryRuntimeCodeHash = dependencies.uniswapFactory.codehash;
        _requireExpectedCodeHash(
            "weth", dependencies.expectedWethRuntimeCodeHash, evidence.wethRuntimeCodeHash
        );
        _requireExpectedCodeHash(
            "uniswapFactory",
            dependencies.expectedUniswapFactoryRuntimeCodeHash,
            evidence.uniswapFactoryRuntimeCodeHash
        );
        evidence.pairInitCodeHashVerified = _verifyPairInitCodeHash(dependencies);
    }

    function expectedPairAddress(
        address factory,
        address tokenA,
        address tokenB,
        bytes32 pairInitCodeHash
    ) internal pure returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 digest = keccak256(
            abi.encodePacked(
                hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), pairInitCodeHash
            )
        );
        return address(uint160(uint256(digest)));
    }

    function _verifyPairInitCodeHash(Dependencies memory dependencies) private returns (bool) {
        (bool success, bytes memory data) =
            dependencies.uniswapFactory.staticcall(abi.encodeWithSignature("pairCodeHash()"));
        if (success && data.length == 32) {
            bytes32 actualPairInitCodeHash = abi.decode(data, (bytes32));
            if (actualPairInitCodeHash != dependencies.pairInitCodeHash) {
                revert InvalidPairInitCodeHash(
                    dependencies.pairInitCodeHash, actualPairInitCodeHash
                );
            }
            return true;
        }

        address expected = expectedPairAddress(
            dependencies.uniswapFactory, PROBE_TOKEN_A, PROBE_TOKEN_B, dependencies.pairInitCodeHash
        );
        IUniswapV2Factory factory = IUniswapV2Factory(dependencies.uniswapFactory);
        address actualPair = factory.getPair(PROBE_TOKEN_A, PROBE_TOKEN_B);
        if (actualPair == address(0)) {
            actualPair = factory.createPair(PROBE_TOKEN_A, PROBE_TOKEN_B);
        }
        if (actualPair != expected) revert PairAddressMismatch(expected, actualPair);
        return true;
    }

    function _rejectMainnetDependencies(Dependencies memory dependencies) private pure {
        if (dependencies.weth == ROBINHOOD_MAINNET_WETH) {
            revert TestnetUsesMainnetDependency("weth", dependencies.weth);
        }
        if (dependencies.uniswapFactory == ROBINHOOD_MAINNET_UNISWAP_FACTORY) {
            revert TestnetUsesMainnetDependency("uniswapFactory", dependencies.uniswapFactory);
        }
    }

    function _requireMainnetDependencies(Dependencies memory dependencies) private pure {
        if (dependencies.weth != ROBINHOOD_MAINNET_WETH) {
            revert MainnetDependencyMismatch("weth", ROBINHOOD_MAINNET_WETH, dependencies.weth);
        }
        if (dependencies.uniswapFactory != ROBINHOOD_MAINNET_UNISWAP_FACTORY) {
            revert MainnetDependencyMismatch(
                "uniswapFactory", ROBINHOOD_MAINNET_UNISWAP_FACTORY, dependencies.uniswapFactory
            );
        }
        if (dependencies.pairInitCodeHash != CANONICAL_UNISWAP_V2_PAIR_INIT_CODE_HASH) {
            revert InvalidPairInitCodeHash(
                CANONICAL_UNISWAP_V2_PAIR_INIT_CODE_HASH, dependencies.pairInitCodeHash
            );
        }
    }

    function _nonzero(bytes32 field, address value) private pure {
        if (value == address(0)) revert InvalidAuthority(field, value);
    }

    function _requireExpectedCodeHash(bytes32 field, bytes32 expected, bytes32 actual)
        private
        pure
    {
        if (expected != bytes32(0) && expected != actual) {
            revert DependencyRuntimeCodeHashMismatch(field, expected, actual);
        }
    }
}
