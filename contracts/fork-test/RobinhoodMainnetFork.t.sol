// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { BondingCurveV1 } from "../src/BondingCurveV1.sol";
import { LaunchFactory } from "../src/LaunchFactory.sol";
import { IBondingCurveV1 } from "../src/interfaces/IBondingCurveV1.sol";
import { ILaunchToken } from "../src/interfaces/ILaunchToken.sol";
import { IUniswapV2Factory } from "../src/interfaces/external/IUniswapV2Factory.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";

interface IMainnetWeth is IERC20Metadata {
    function deposit() external payable;
}

interface IMainnetPair is IERC20 {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract RobinhoodMainnetForkTest is Test {
    uint16 private constant ENGINE_VERSION = 1;
    uint256 private constant TOTAL_SUPPLY = 1_000_000_000 ether;
    uint256 private constant CURVE_TOKENS = 800_000_000 ether;
    uint256 private constant LP_TOKENS = 200_000_000 ether;
    uint256 private constant GRADUATION_ETH = 4.2 ether;
    uint256 private constant INITIAL_VIRTUAL_ETH = 1.4 ether;
    uint256 private constant INITIAL_VIRTUAL_TOKEN = 1_066_666_666_666_666_666_666_666_667;
    uint16 private constant TRADE_FEE_BPS = 100;
    uint16 private constant PROTOCOL_SHARE_BPS = 5000;
    uint256 private constant FINAL_BUY_GROSS = 10 ether;
    uint256 private constant SWAP_TOKEN_INPUT = 1_000_000 ether;
    uint256 private constant UNISWAP_MINIMUM_LIQUIDITY = 1000;

    address private constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant UNISWAP_FACTORY = 0x8bcEaA40B9AcdfAedF85AdF4FF01F5Ad6517937f;
    address private constant UNISWAP_ROUTER = 0x89e5DB8B5aA49aA85AC63f691524311AEB649eba;
    address private constant LP_BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bytes32 private constant PAIR_INIT_CODE_HASH =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    bytes32 private constant WETH_RUNTIME_CODE_HASH =
        0x5706be52f64875fee65a2cec0d80e47a23d8793cbe85d214b48445e2d05f5353;
    bytes32 private constant FACTORY_RUNTIME_CODE_HASH =
        0xbab145d02e7005f0d84c6c1639d39b799b0ea16df99ebbdaf5a14d9da820b4e0;
    bytes32 private constant PAIR_RUNTIME_CODE_HASH =
        0x5b83bdbcc56b2e630f2807bbadd2b0c21619108066b92a58de081261089e9ce5;

    bytes32 private constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    bytes32 private constant PAIR_CREATED_TOPIC =
        keccak256("PairCreated(address,address,address,uint256)");
    bytes32 private constant TOKEN_LAUNCHED_TOPIC = keccak256(
        "TokenLaunched(address,address,address,address,address,address,uint16,string,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint16,uint16)"
    );
    bytes32 private constant TRADE_TOPIC = keccak256(
        "Trade(address,address,bool,uint256,uint256,uint256,uint256,uint256,uint256,uint256)"
    );
    bytes32 private constant GRADUATED_TOPIC =
        keccak256("Graduated(address,address,uint256,uint256,uint256)");
    bytes32 private constant SYNC_TOPIC = keccak256("Sync(uint112,uint112)");
    bytes32 private constant SWAP_TOPIC =
        keccak256("Swap(address,uint256,uint256,uint256,uint256,address)");

    address private constant PAUSE_AUTHORITY = address(0xA11CE);
    address private constant TIMELOCK = address(0xB0B);
    address private constant TREASURY = address(0xCAFE);
    address private constant CREATOR = address(0xC0FFEE);
    address private constant TRADER = address(0xBEEF);

    struct LaunchResult {
        address token;
        IBondingCurveV1 curve;
        IMainnetPair pair;
    }

    LaunchFactory private launchFactory;

    function setUp() external {
        assertEq(block.chainid, 4663, "fork must target Robinhood mainnet");
        assertEq(WETH.codehash, WETH_RUNTIME_CODE_HASH, "WETH runtime bytecode drift");
        assertEq(
            UNISWAP_FACTORY.codehash,
            FACTORY_RUNTIME_CODE_HASH,
            "Uniswap factory runtime bytecode drift"
        );
        assertEq(IMainnetWeth(WETH).name(), "WETH");
        assertEq(IMainnetWeth(WETH).symbol(), "WETH");
        assertEq(IMainnetWeth(WETH).decimals(), 18);

        launchFactory = new LaunchFactory(
            LaunchTypes.FactoryInitialization({
                pauseAuthority: PAUSE_AUTHORITY,
                timelock: TIMELOCK,
                protocolTreasury: TREASURY,
                engineVersion: ENGINE_VERSION,
                implementation: address(new BondingCurveV1()),
                defaults: _defaults()
            })
        );
        vm.deal(CREATOR, 100 ether);
    }

    function testForkLaunchGraduationAndSwapAcrossBothTokenOrderings() external {
        _exerciseLaunch(true, "LOW", "LOW");
        _exerciseLaunch(false, "HIGH", "HIGH");
    }

    function testForkGraduationHasNoRouterDependency() external {
        _positionNextToken(false);
        vm.prank(CREATOR);
        (address token, address curve,) = launchFactory.launch(_request("NOROUTER", "NRT"));

        vm.etch(UNISWAP_ROUTER, hex"60006000fd");
        vm.prank(CREATOR);
        IBondingCurveV1(curve).buy{ value: FINAL_BUY_GROSS }(
            CREATOR, CREATOR, 0, block.timestamp
        );

        assertTrue(ILaunchToken(token).graduated());
        assertEq(uint8(IBondingCurveV1(curve).phase()), uint8(LaunchTypes.Phase.Graduated));
    }

    function _exerciseLaunch(bool tokenIs0Expected, string memory name, string memory symbol)
        private
    {
        _positionNextToken(tokenIs0Expected);
        vm.recordLogs();
        vm.prank(CREATOR);
        (address token, address curveAddress, address pairAddress) =
            launchFactory.launch(_request(name, symbol));
        Vm.Log[] memory launchLogs = vm.getRecordedLogs();

        LaunchResult memory result = LaunchResult({
            token: token,
            curve: IBondingCurveV1(curveAddress),
            pair: IMainnetPair(pairAddress)
        });
        assertEq(token < WETH, tokenIs0Expected, "requested token ordering not produced");
        _assertPairCreation(result);
        _assertLaunchEventOrder(launchLogs, result);
        _graduate(result);
        _assertPostGraduationTransferAndSwap(result, tokenIs0Expected);
    }

    function _graduate(LaunchResult memory result) private {
        (
            uint256 quotedGrossUsed,
            uint256 quotedTokensOut,
            ,
            ,
            ,
            bool graduates
        ) = result.curve.quoteBuy(FINAL_BUY_GROSS);
        assertTrue(graduates);

        vm.recordLogs();
        vm.prank(CREATOR);
        (uint256 tokensOut, uint256 grossUsed) = result.curve.buy{ value: FINAL_BUY_GROSS }(
            CREATOR, CREATOR, 0, block.timestamp
        );
        Vm.Log[] memory graduationLogs = vm.getRecordedLogs();

        assertEq(tokensOut, quotedTokensOut);
        assertEq(grossUsed, quotedGrossUsed);
        assertEq(uint8(result.curve.phase()), uint8(LaunchTypes.Phase.Graduated));
        assertTrue(ILaunchToken(result.token).graduated());
        assertEq(IMainnetWeth(WETH).balanceOf(address(result.pair)), GRADUATION_ETH);
        assertEq(IERC20(result.token).balanceOf(address(result.pair)), LP_TOKENS);
        assertEq(IERC20(result.token).balanceOf(CREATOR), CURVE_TOKENS);

        (uint112 reserve0, uint112 reserve1,) = result.pair.getReserves();
        if (result.token < WETH) {
            assertEq(uint256(reserve0), LP_TOKENS);
            assertEq(uint256(reserve1), GRADUATION_ETH);
        } else {
            assertEq(uint256(reserve0), GRADUATION_ETH);
            assertEq(uint256(reserve1), LP_TOKENS);
        }

        uint256 burnedLiquidity = result.pair.balanceOf(LP_BURN_ADDRESS);
        assertGt(burnedLiquidity, 0);
        assertEq(result.pair.balanceOf(address(0)), UNISWAP_MINIMUM_LIQUIDITY);
        assertEq(result.pair.totalSupply(), burnedLiquidity + UNISWAP_MINIMUM_LIQUIDITY);
        _assertGraduationEventOrder(graduationLogs, result, burnedLiquidity);
    }

    function _assertPairCreation(LaunchResult memory result) private view {
        assertEq(address(result.pair).codehash, PAIR_RUNTIME_CODE_HASH);
        assertEq(result.pair.factory(), UNISWAP_FACTORY);
        assertEq(
            IUniswapV2Factory(UNISWAP_FACTORY).getPair(result.token, WETH),
            address(result.pair)
        );
        assertEq(
            address(result.pair),
            _expectedPairAddress(UNISWAP_FACTORY, result.token, WETH, PAIR_INIT_CODE_HASH)
        );
        assertEq(result.pair.token0(), result.token < WETH ? result.token : WETH);
        assertEq(result.pair.token1(), result.token < WETH ? WETH : result.token);
        assertEq(result.pair.totalSupply(), 0);
        (uint112 reserve0, uint112 reserve1,) = result.pair.getReserves();
        assertEq(uint256(reserve0), 0);
        assertEq(uint256(reserve1), 0);
    }

    function _assertLaunchEventOrder(Vm.Log[] memory logs, LaunchResult memory result) private view {
        uint256 transferIndex = type(uint256).max;
        uint256 pairCreatedIndex = type(uint256).max;
        uint256 launchIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == result.token && logs[i].topics.length == 3
                    && logs[i].topics[0] == TRANSFER_TOPIC && logs[i].topics[1] == bytes32(0)
            ) transferIndex = i;
            if (
                logs[i].emitter == UNISWAP_FACTORY && logs[i].topics.length == 3
                    && logs[i].topics[0] == PAIR_CREATED_TOPIC
            ) pairCreatedIndex = i;
            if (
                logs[i].emitter == address(launchFactory) && logs[i].topics.length == 4
                    && logs[i].topics[0] == TOKEN_LAUNCHED_TOPIC
            ) launchIndex = i;
        }
        assertLt(transferIndex, pairCreatedIndex);
        assertLt(pairCreatedIndex, launchIndex);
    }

    function _assertGraduationEventOrder(
        Vm.Log[] memory logs,
        LaunchResult memory result,
        uint256 expectedLiquidity
    ) private pure {
        uint256 tradeIndex = type(uint256).max;
        uint256 tokenToPairIndex = type(uint256).max;
        uint256 syncIndex = type(uint256).max;
        uint256 graduatedIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == address(result.curve) && logs[i].topics[0] == TRADE_TOPIC) {
                tradeIndex = i;
            }
            if (
                logs[i].emitter == result.token && logs[i].topics.length == 3
                    && logs[i].topics[0] == TRANSFER_TOPIC
                    && _topicAddress(logs[i].topics[2]) == address(result.pair)
            ) tokenToPairIndex = i;
            if (logs[i].emitter == address(result.pair) && logs[i].topics[0] == SYNC_TOPIC) {
                syncIndex = i;
            }
            if (
                logs[i].emitter == address(result.curve) && logs[i].topics.length == 3
                    && logs[i].topics[0] == GRADUATED_TOPIC
            ) {
                graduatedIndex = i;
                (uint256 ethToPool, uint256 tokensToPool, uint256 liquidity) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256));
                assertEq(_topicAddress(logs[i].topics[1]), result.token);
                assertEq(_topicAddress(logs[i].topics[2]), address(result.pair));
                assertEq(ethToPool, GRADUATION_ETH);
                assertEq(tokensToPool, LP_TOKENS);
                assertEq(liquidity, expectedLiquidity);
            }
        }
        assertLt(tradeIndex, tokenToPairIndex);
        assertLt(tokenToPairIndex, syncIndex);
        assertLt(syncIndex, graduatedIndex);
    }

    function _assertPostGraduationTransferAndSwap(
        LaunchResult memory result,
        bool tokenIs0
    ) private {
        vm.prank(CREATOR);
        assertTrue(IERC20(result.token).transfer(TRADER, SWAP_TOKEN_INPUT));
        assertEq(IERC20(result.token).balanceOf(TRADER), SWAP_TOKEN_INPUT);

        (uint112 reserve0Before, uint112 reserve1Before,) = result.pair.getReserves();
        uint256 tokenReserve = tokenIs0 ? uint256(reserve0Before) : uint256(reserve1Before);
        uint256 wethReserve = tokenIs0 ? uint256(reserve1Before) : uint256(reserve0Before);
        uint256 wethOut = _getAmountOut(SWAP_TOKEN_INPUT, tokenReserve, wethReserve);
        uint256 traderWethBefore = IMainnetWeth(WETH).balanceOf(TRADER);

        vm.prank(TRADER);
        assertTrue(IERC20(result.token).transfer(address(result.pair), SWAP_TOKEN_INPUT));
        vm.recordLogs();
        vm.prank(TRADER);
        result.pair.swap(
            tokenIs0 ? 0 : wethOut, tokenIs0 ? wethOut : 0, TRADER, bytes("")
        );
        Vm.Log[] memory swapLogs = vm.getRecordedLogs();

        assertEq(IMainnetWeth(WETH).balanceOf(TRADER) - traderWethBefore, wethOut);
        (uint112 reserve0After, uint112 reserve1After,) = result.pair.getReserves();
        if (tokenIs0) {
            assertEq(uint256(reserve0After), uint256(reserve0Before) + SWAP_TOKEN_INPUT);
            assertEq(uint256(reserve1After), uint256(reserve1Before) - wethOut);
        } else {
            assertEq(uint256(reserve0After), uint256(reserve0Before) - wethOut);
            assertEq(uint256(reserve1After), uint256(reserve1Before) + SWAP_TOKEN_INPUT);
        }
        _assertSyncImmediatelyPrecedesSwap(swapLogs, address(result.pair));
    }

    function _assertSyncImmediatelyPrecedesSwap(Vm.Log[] memory logs, address pair) private pure {
        uint256 syncIndex = type(uint256).max;
        uint256 swapIndex = type(uint256).max;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == pair && logs[i].topics[0] == SYNC_TOPIC) syncIndex = i;
            if (logs[i].emitter == pair && logs[i].topics[0] == SWAP_TOPIC) swapIndex = i;
        }
        assertEq(syncIndex + 1, swapIndex, "Sync must immediately precede Swap");
    }

    function _positionNextToken(bool tokenIs0) private {
        uint64 candidateNonce = vm.getNonce(address(launchFactory));
        for (uint256 attempts = 0; attempts < 10_000; ++attempts) {
            address predictedToken =
                vm.computeCreateAddress(address(launchFactory), uint256(candidateNonce) + 1);
            if ((predictedToken < WETH) == tokenIs0) {
                vm.setNonce(address(launchFactory), candidateNonce);
                return;
            }
            ++candidateNonce;
        }
        revert("token ordering nonce not found");
    }

    function _expectedPairAddress(
        address factory,
        address tokenA,
        address tokenB,
        bytes32 initCodeHash
    ) private pure returns (address) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), initCodeHash
                        )
                    )
                )
            )
        );
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        private
        pure
        returns (uint256)
    {
        uint256 amountInWithFee = amountIn * 997;
        return amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee);
    }

    function _defaults() private pure returns (LaunchTypes.FactoryDefaults memory) {
        return LaunchTypes.FactoryDefaults({
            parameters: LaunchTypes.CurveParameters({
                totalSupply: TOTAL_SUPPLY,
                curveTokens: CURVE_TOKENS,
                lpTokens: LP_TOKENS,
                graduationEth: GRADUATION_ETH,
                initialVirtualEth: INITIAL_VIRTUAL_ETH,
                initialVirtualToken: INITIAL_VIRTUAL_TOKEN,
                tradeFeeBps: TRADE_FEE_BPS,
                protocolShareBps: PROTOCOL_SHARE_BPS
            }),
            weth: WETH,
            uniswapFactory: UNISWAP_FACTORY,
            launchFee: 0
        });
    }

    function _request(string memory name, string memory symbol)
        private
        view
        returns (LaunchTypes.LaunchRequest memory)
    {
        return LaunchTypes.LaunchRequest({
            name: name,
            symbol: symbol,
            engineVersion: ENGINE_VERSION,
            developerBuyGross: 0,
            minDeveloperTokensOut: 0,
            deadline: block.timestamp
        });
    }

    function _topicAddress(bytes32 topic) private pure returns (address) {
        return address(uint160(uint256(topic)));
    }
}
