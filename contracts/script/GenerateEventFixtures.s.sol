// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import { BondingCurveV1 } from "../src/BondingCurveV1.sol";
import { LaunchFactory } from "../src/LaunchFactory.sol";
import { ILaunchEvents } from "../src/interfaces/ILaunchEvents.sol";
import { LaunchTypes } from "../src/types/LaunchTypes.sol";
import { LocalWETH } from "./local/LocalWETH.sol";
import { LocalUniswapV2Factory } from "./local/LocalUniswapV2Factory.sol";

contract CurveEventFixture is ILaunchEvents {
    function emitEvents(address token, address pair) external {
        emit Trade(token, address(0xB0B), true, 101, 2, 303, 4, 5, 606, 707);
        emit Graduated(token, pair, 808, 909, 1010);
        emit CreatorFeesClaimed(token, address(0xC0FFEE), 11);
        emit ProtocolFeesClaimed(token, address(0x7000), 12);
        emit RefundCredited(token, address(0xB0B), 13);
        emit RefundClaimed(token, address(0xB0B), 14);
    }
}

contract PairEventFixture {
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function emitEvents() external {
        emit Mint(address(0xA11CE), 15, 16);
        emit Burn(address(0xA11CE), 17, 18, address(0xB0B));
        emit Swap(address(0xA11CE), 19, 20, 21, 22, address(0xB0B));
        emit Sync(23, 24);
    }
}

/// @notice Generates ABI-decoder logs from a real Foundry execution.
/// @dev TokenLaunched is emitted by LaunchFactory's production inline-assembly encoder.
contract GenerateEventFixtures is Script {
    struct FixtureEmitters {
        address factory;
        address curveFixture;
        address actualCurve;
        address token;
        address pairFixture;
    }

    uint16 private constant ENGINE_VERSION = 1;
    uint256 private constant LAUNCH_FEE = 0.0005 ether;
    uint256 private constant DEVELOPER_BUY = 0.001 ether;
    address private constant PAUSE_AUTHORITY = address(0xA11CE);
    address private constant TIMELOCK = address(0x710E10C);
    address private constant TREASURY = address(0x7000);
    address private constant CREATOR = address(0xC0FFEE);

    bytes32 private constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");

    function run() external {
        BondingCurveV1 implementation = new BondingCurveV1();
        LocalWETH weth = new LocalWETH();
        LocalUniswapV2Factory uniswapFactory = new LocalUniswapV2Factory();
        CurveEventFixture curveEvents = new CurveEventFixture();
        PairEventFixture pairEvents = new PairEventFixture();

        vm.recordLogs();
        LaunchFactory factory = new LaunchFactory(
            LaunchTypes.FactoryInitialization({
                pauseAuthority: PAUSE_AUTHORITY,
                timelock: TIMELOCK,
                protocolTreasury: TREASURY,
                engineVersion: ENGINE_VERSION,
                implementation: address(implementation),
                defaults: _defaults(address(weth), address(uniswapFactory))
            })
        );
        vm.deal(CREATOR, 1 ether);
        vm.prank(CREATOR);
        // Value reaches the freshly deployed production LaunchFactory fixture only.
        // forge-lint: disable-start(arbitrary-send-eth)
        (address token, address actualCurve, address pair) = factory.launch{
            value: LAUNCH_FEE + DEVELOPER_BUY
        }(
            LaunchTypes.LaunchRequest({
                name: unicode"Pons 🐸 launch",
                symbol: unicode"PØNS",
                engineVersion: ENGINE_VERSION,
                developerBuyGross: DEVELOPER_BUY,
                minDeveloperTokensOut: 0,
                deadline: type(uint256).max
            })
        );
        // forge-lint: disable-end(arbitrary-send-eth)
        vm.prank(PAUSE_AUTHORITY);
        factory.setLaunchesPaused(true);
        vm.prank(PAUSE_AUTHORITY);
        factory.setTradingPaused(true);
        vm.prank(TIMELOCK);
        factory.configureEngine(ENGINE_VERSION, address(implementation), true);
        vm.prank(TIMELOCK);
        factory.setFutureDefaults(_defaults(address(weth), address(uniswapFactory)));
        vm.prank(TIMELOCK);
        factory.setFutureTreasury(address(0x7001));
        vm.prank(TREASURY);
        require(factory.claimLaunchFees() == LAUNCH_FEE, "LAUNCH_FEE_FIXTURE_MISMATCH");
        curveEvents.emitEvents(token, pair);
        pairEvents.emitEvents();

        _writeFixtures(
            vm.getRecordedLogs(),
            FixtureEmitters({
                factory: address(factory),
                curveFixture: address(curveEvents),
                actualCurve: actualCurve,
                token: token,
                pairFixture: address(pairEvents)
            })
        );
    }

    function _writeFixtures(Vm.Log[] memory logs, FixtureEmitters memory emitters) private {
        string memory json = '{"schemaVersion":1,"engineVersion":1,"logs":[';
        bool first = true;
        for (uint256 index = 0; index < logs.length; ++index) {
            string memory kind = _kind(logs[index], emitters);
            if (bytes(kind).length == 0 || !_supported(logs[index].topics[0])) continue;
            if (!first) json = string.concat(json, ",");
            first = false;
            json = string.concat(json, _logJson(logs[index], kind));
        }
        require(!first, "NO_EVENT_FIXTURES");
        string memory output =
            vm.envOr("EVENT_FIXTURES_OUTPUT", string("./fixtures/v1/event-logs-v1.json"));
        vm.writeFile(output, string.concat(json, "]}\n"));
    }

    function _defaults(address weth, address uniswapFactory)
        private
        pure
        returns (LaunchTypes.FactoryDefaults memory)
    {
        return LaunchTypes.FactoryDefaults({
            parameters: LaunchTypes.CurveParameters({
                totalSupply: 1_000_000_000 ether,
                curveTokens: 800_000_000 ether,
                lpTokens: 200_000_000 ether,
                graduationEth: 4.2 ether,
                initialVirtualEth: 1.4 ether,
                initialVirtualToken: 1_066_666_666_666_666_666_666_666_667,
                tradeFeeBps: 100,
                protocolShareBps: 5000
            }),
            weth: weth,
            uniswapFactory: uniswapFactory,
            launchFee: LAUNCH_FEE
        });
    }

    function _kind(Vm.Log memory entry, FixtureEmitters memory emitters)
        private
        pure
        returns (string memory)
    {
        if (entry.emitter == emitters.factory) return "factory";
        if (entry.emitter == emitters.curveFixture || entry.emitter == emitters.actualCurve) {
            return "curve";
        }
        if (entry.emitter == emitters.token) return "token";
        if (entry.emitter == emitters.pairFixture) return "pair";
        return "";
    }

    function _supported(bytes32 topic) private pure returns (bool) {
        return topic == TRANSFER_TOPIC
            || topic
                == keccak256(
                "TokenLaunched(address,address,address,address,address,address,uint16,string,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint16,uint16)"
            )
            || topic
                == keccak256(
                "Trade(address,address,bool,uint256,uint256,uint256,uint256,uint256,uint256,uint256)"
            ) || topic == keccak256("Graduated(address,address,uint256,uint256,uint256)")
            || topic == keccak256("CreatorFeesClaimed(address,address,uint256)")
            || topic == keccak256("ProtocolFeesClaimed(address,address,uint256)")
            || topic == keccak256("LaunchFeesClaimed(address,uint256)")
            || topic == keccak256("RefundCredited(address,address,uint256)")
            || topic == keccak256("RefundClaimed(address,address,uint256)")
            || topic == keccak256("LaunchPauseSet(bool)")
            || topic == keccak256("TradingPauseSet(bool)")
            || topic == keccak256("EngineConfigured(uint16,address,bool)")
            || topic == keccak256("FutureDefaultsConfigured(bytes32)")
            || topic == keccak256("FutureTreasuryConfigured(address,address)")
            || topic == keccak256("Mint(address,uint256,uint256)")
            || topic == keccak256("Burn(address,uint256,uint256,address)")
            || topic == keccak256("Swap(address,uint256,uint256,uint256,uint256,address)")
            || topic == keccak256("Sync(uint112,uint112)");
    }

    function _logJson(Vm.Log memory entry, string memory kind)
        private
        pure
        returns (string memory json)
    {
        // Cheatcode string conversion is intentionally used while serializing recorded logs.
        // forge-lint: disable-start(calls-loop)
        json = string.concat(
            '{"emitterKind":"', kind, '","address":"', vm.toString(entry.emitter), '","topics":['
        );
        for (uint256 index = 0; index < entry.topics.length; ++index) {
            if (index != 0) json = string.concat(json, ",");
            json = string.concat(json, '"', vm.toString(entry.topics[index]), '"');
        }
        json = string.concat(json, '],"data":"', vm.toString(entry.data), '"}');
        // forge-lint: disable-end(calls-loop)
        return json;
    }
}
