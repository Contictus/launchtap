// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ILaunchFactory } from "./interfaces/ILaunchFactory.sol";
import { IBondingCurveV1 } from "./interfaces/IBondingCurveV1.sol";
import { ILaunchToken } from "./interfaces/ILaunchToken.sol";
import { IUniswapV2Factory } from "./interfaces/external/IUniswapV2Factory.sol";
import { CurveMath } from "./libraries/CurveMath.sol";
import { LaunchToken } from "./LaunchToken.sol";
import { LaunchFactoryStorage } from "./storage/LaunchFactoryStorage.sol";
import { LaunchTypes } from "./types/LaunchTypes.sol";

/// @notice Non-upgradeable launch coordinator and future-launch configuration registry.
contract LaunchFactory is LaunchFactoryStorage, ReentrancyGuard, ILaunchFactory {
    uint256 private constant DEVELOPER_BUY_CAP_DIVISOR = 100;
    bytes32 private constant FIELD_PAUSE_AUTHORITY = "pauseAuthority";
    bytes32 private constant FIELD_TIMELOCK = "timelock";
    bytes32 private constant FIELD_PROTOCOL_TREASURY = "protocolTreasury";
    bytes32 private constant FIELD_IMPLEMENTATION = "implementation";
    bytes32 private constant FIELD_WETH = "weth";
    bytes32 private constant FIELD_UNISWAP_FACTORY = "uniswapFactory";
    bytes32 private constant TOKEN_LAUNCHED_EVENT_SIGNATURE = keccak256(
        "TokenLaunched(address,address,address,address,address,address,uint16,string,string,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint16,uint16)"
    );

    struct LaunchSnapshot {
        LaunchTypes.CurveParameters parameters;
        address implementation;
        address protocolTreasury;
        address weth;
        address uniswapFactory;
        uint256 launchFee;
    }

    struct LaunchEventData {
        LaunchTypes.CurveParameters parameters;
        address token;
        address curve;
        address creator;
        address lpPair;
        address weth;
        address protocolTreasury;
        uint16 engineVersion;
        string name;
        string symbol;
        uint256 launchFee;
    }

    constructor(LaunchTypes.FactoryInitialization memory initialization) {
        _validateAddress(initialization.pauseAuthority, FIELD_PAUSE_AUTHORITY);
        _validateAddress(initialization.timelock, FIELD_TIMELOCK);
        _validateAddress(initialization.protocolTreasury, FIELD_PROTOCOL_TREASURY);
        if (initialization.pauseAuthority == msg.sender) {
            revert InvalidAuthority(FIELD_PAUSE_AUTHORITY, msg.sender);
        }
        if (
            initialization.timelock == msg.sender
                || initialization.timelock == initialization.pauseAuthority
        ) {
            revert InvalidAuthority(FIELD_TIMELOCK, initialization.timelock);
        }

        _pauseAuthority = initialization.pauseAuthority;
        _timelock = initialization.timelock;
        _futureProtocolTreasury = initialization.protocolTreasury;

        _setFutureDefaults(initialization.defaults);
        _configureEngine(initialization.engineVersion, initialization.implementation, true);

        emit FutureTreasuryConfigured(address(0), initialization.protocolTreasury);
        emit FutureDefaultsConfigured(_hashDefaults(initialization.defaults));
    }

    function launch(LaunchTypes.LaunchRequest calldata request)
        external
        payable
        nonReentrant
        returns (address token, address curve, address lpPair)
    {
        if (_launchesPaused) revert LaunchesPaused();

        LaunchSnapshot memory snapshot = _snapshot(request.engineVersion);
        uint256 expectedValue = CurveMath.checkedAdd(snapshot.launchFee, request.developerBuyGross);
        if (msg.value != expectedValue) revert LaunchValueMismatch(expectedValue, msg.value);
        if (request.developerBuyGross != 0 && _tradingPaused) revert TradingPaused();
        if (request.developerBuyGross == 0 && request.minDeveloperTokensOut != 0) {
            revert SlippageExceeded(request.minDeveloperTokensOut, 0);
        }

        curve = Clones.clone(snapshot.implementation);
        token = address(
            new LaunchToken(request.name, request.symbol, curve, snapshot.parameters.totalSupply)
        );
        lpPair = _resolvePair(snapshot.uniswapFactory, token, snapshot.weth);

        ILaunchToken(token).initializePair(lpPair);
        IBondingCurveV1(curve)
            .initialize(
                LaunchTypes.CurveInitialization({
                    factory: address(this),
                    implementation: snapshot.implementation,
                    token: token,
                    creator: msg.sender,
                    protocolTreasury: snapshot.protocolTreasury,
                    weth: snapshot.weth,
                    uniswapFactory: snapshot.uniswapFactory,
                    lpPair: lpPair,
                    parameters: snapshot.parameters
                })
            );

        _launchFeesByTreasury[snapshot.protocolTreasury] = CurveMath.checkedAdd(
            _launchFeesByTreasury[snapshot.protocolTreasury], snapshot.launchFee
        );

        uint256 developerTokensOut = _validateDeveloperBuy(curve, request, snapshot.parameters);
        LaunchEventData memory eventData;
        eventData.parameters = snapshot.parameters;
        eventData.token = token;
        eventData.curve = curve;
        eventData.creator = msg.sender;
        eventData.lpPair = lpPair;
        eventData.weth = snapshot.weth;
        eventData.protocolTreasury = snapshot.protocolTreasury;
        eventData.engineVersion = request.engineVersion;
        eventData.name = request.name;
        eventData.symbol = request.symbol;
        eventData.launchFee = snapshot.launchFee;
        _emitTokenLaunched(eventData);
        _executeDeveloperBuy(curve, request, snapshot.parameters.totalSupply, developerTokensOut);
    }

    function claimLaunchFees() external nonReentrant returns (uint256 amount) {
        amount = _launchFeesByTreasury[msg.sender];
        if (amount == 0) revert NothingToClaim();

        _launchFeesByTreasury[msg.sender] = 0;
        emit LaunchFeesClaimed(msg.sender, amount);

        // The treasury is the authenticated caller; claims intentionally forward all gas.
        // forge-lint: disable-next-line(arbitrary-send-eth, low-level-calls)
        (bool success,) = payable(msg.sender).call{ value: amount }("");
        if (!success) revert EthTransferFailed(msg.sender, amount);
    }

    function setLaunchesPaused(bool paused) external nonReentrant {
        _requirePauseAuthority();
        _launchesPaused = paused;
        emit LaunchPauseSet(paused);
    }

    function setTradingPaused(bool paused) external nonReentrant {
        _requirePauseAuthority();
        _tradingPaused = paused;
        emit TradingPauseSet(paused);
    }

    function configureEngine(uint16 engineVersion, address implementation_, bool enabled)
        external
        nonReentrant
    {
        _requireTimelock();
        _configureEngine(engineVersion, implementation_, enabled);
    }

    function setFutureDefaults(LaunchTypes.FactoryDefaults calldata defaults)
        external
        nonReentrant
    {
        _requireTimelock();
        _setFutureDefaults(defaults);
        emit FutureDefaultsConfigured(_hashDefaults(defaults));
    }

    // The shared validator below performs the zero-address check.
    // forge-lint: disable-next-line(missing-zero-check)
    function setFutureTreasury(address treasury) external nonReentrant {
        _requireTimelock();
        _validateAddress(treasury, FIELD_PROTOCOL_TREASURY);

        address previousTreasury = _futureProtocolTreasury;
        _futureProtocolTreasury = treasury;
        emit FutureTreasuryConfigured(previousTreasury, treasury);
    }

    function curveImplementation(uint16 engineVersion) external view returns (address) {
        return _engines[engineVersion].implementation;
    }

    function engineEnabled(uint16 engineVersion) external view returns (bool) {
        return _engines[engineVersion].enabled;
    }

    function futureDefaults() external view returns (LaunchTypes.FactoryDefaults memory defaults) {
        return _futureDefaults();
    }

    function futureDefaultsHash() external view returns (bytes32) {
        return _hashDefaults(_futureDefaults());
    }

    function protocolTreasury() external view returns (address) {
        return _futureProtocolTreasury;
    }

    function weth() external view returns (address) {
        return _weth;
    }

    function uniswapFactory() external view returns (address) {
        return _uniswapFactory;
    }

    function launchFee() external view returns (uint256) {
        return _launchFee;
    }

    function pauseAuthority() external view returns (address) {
        return _pauseAuthority;
    }

    function timelock() external view returns (address) {
        return _timelock;
    }

    function launchesPaused() external view returns (bool) {
        return _launchesPaused;
    }

    function tradingPaused() external view returns (bool) {
        return _tradingPaused;
    }

    function launchFeesByTreasury(address treasury) external view returns (uint256) {
        return _launchFeesByTreasury[treasury];
    }

    function _snapshot(uint16 engineVersion) private view returns (LaunchSnapshot memory snapshot) {
        EngineConfig storage engine = _engines[engineVersion];
        if (engine.implementation == address(0)) revert UnknownEngine(engineVersion);
        if (!engine.enabled) revert EngineDisabled(engineVersion);

        snapshot.parameters = _futureParameters;
        snapshot.implementation = engine.implementation;
        snapshot.protocolTreasury = _futureProtocolTreasury;
        snapshot.weth = _weth;
        snapshot.uniswapFactory = _uniswapFactory;
        snapshot.launchFee = _launchFee;
    }

    function _resolvePair(address factory, address token, address weth_)
        private
        returns (address pair)
    {
        pair = IUniswapV2Factory(factory).getPair(token, weth_);
        if (pair == address(0)) pair = IUniswapV2Factory(factory).createPair(token, weth_);

        address canonicalPair = IUniswapV2Factory(factory).getPair(token, weth_);
        if (pair != canonicalPair) revert PairNotCanonical(canonicalPair, pair);
    }

    function _validateDeveloperBuy(
        address curve,
        LaunchTypes.LaunchRequest calldata request,
        LaunchTypes.CurveParameters memory parameters
    ) private view returns (uint256 tokensOut) {
        if (request.developerBuyGross == 0) return 0;

        // Only the token output is required for the developer allocation cap.
        // forge-lint: disable-next-line(unused-return)
        (, tokensOut,,,,) = IBondingCurveV1(curve).quoteBuy(request.developerBuyGross);
        uint256 maximumTokensOut = parameters.totalSupply / DEVELOPER_BUY_CAP_DIVISOR;
        if (tokensOut > maximumTokensOut) {
            revert DeveloperBuyCapExceeded(tokensOut, maximumTokensOut);
        }
    }

    function _executeDeveloperBuy(
        address curve,
        LaunchTypes.LaunchRequest calldata request,
        uint256 totalSupply,
        uint256 expectedTokensOut
    ) private {
        if (request.developerBuyGross == 0) return;

        IBondingCurveV1 curveContract = IBondingCurveV1(curve);
        (uint256 actualTokensOut, uint256 actualGrossUsed) = _callDeveloperBuy(
            curveContract,
            msg.sender,
            request.developerBuyGross,
            request.minDeveloperTokensOut,
            request.deadline
        );
        uint256 maximumTokensOut = totalSupply / DEVELOPER_BUY_CAP_DIVISOR;
        if (actualTokensOut > maximumTokensOut || actualTokensOut != expectedTokensOut) {
            revert DeveloperBuyCapExceeded(actualTokensOut, maximumTokensOut);
        }
        if (actualGrossUsed != request.developerBuyGross) {
            revert LaunchValueMismatch(request.developerBuyGross, actualGrossUsed);
        }
    }

    function _callDeveloperBuy(
        IBondingCurveV1 curve,
        address creator,
        uint256 gross,
        uint256 minTokensOut,
        uint256 deadline
    ) private returns (uint256 tokensOut, uint256 grossUsed) {
        // The value only reaches the factory-created, already initialized curve clone.
        // forge-lint: disable-next-line(arbitrary-send-eth)
        return curve.buyFor{ value: gross }(creator, creator, creator, minTokensOut, deadline);
    }

    function _emitTokenLaunched(LaunchEventData memory data) private {
        bytes32 signature = TOKEN_LAUNCHED_EVENT_SIGNATURE;

        // The non-indexed payload has fifteen ABI words plus two dynamic string tails.
        // Manual encoding avoids a legacy-codegen stack limit while preserving the frozen ABI.
        assembly ("memory-safe") {
            let parameters := mload(data)
            let namePointer := mload(add(data, 0x100))
            let symbolPointer := mload(add(data, 0x120))
            let nameLength := mload(namePointer)
            let symbolLength := mload(symbolPointer)
            let namePaddedLength := and(add(nameLength, 0x1f), not(0x1f))
            let symbolPaddedLength := and(add(symbolLength, 0x1f), not(0x1f))
            let headLength := 0x1e0
            let nameTailLength := add(0x20, namePaddedLength)
            let payloadLength := add(add(headLength, nameTailLength), add(0x20, symbolPaddedLength))
            let payload := mload(0x40)

            mstore(payload, mload(add(data, 0x80)))
            mstore(add(payload, 0x20), mload(add(data, 0xa0)))
            mstore(add(payload, 0x40), mload(add(data, 0xc0)))
            mstore(add(payload, 0x60), mload(add(data, 0xe0)))
            mstore(add(payload, 0x80), headLength)
            mstore(add(payload, 0xa0), add(headLength, nameTailLength))
            mstore(add(payload, 0xc0), mload(parameters))
            mstore(add(payload, 0xe0), mload(add(parameters, 0x80)))
            mstore(add(payload, 0x100), mload(add(parameters, 0xa0)))
            mstore(add(payload, 0x120), mload(add(parameters, 0x20)))
            mstore(add(payload, 0x140), mload(add(parameters, 0x40)))
            mstore(add(payload, 0x160), mload(add(parameters, 0x60)))
            mstore(add(payload, 0x180), mload(add(data, 0x140)))
            mstore(add(payload, 0x1a0), mload(add(parameters, 0xc0)))
            mstore(add(payload, 0x1c0), mload(add(parameters, 0xe0)))

            let nameTail := add(payload, headLength)
            mstore(nameTail, nameLength)
            mcopy(add(nameTail, 0x20), add(namePointer, 0x20), nameLength)
            mstore(add(add(nameTail, 0x20), nameLength), 0)

            let symbolTail := add(nameTail, nameTailLength)
            mstore(symbolTail, symbolLength)
            mcopy(add(symbolTail, 0x20), add(symbolPointer, 0x20), symbolLength)
            mstore(add(add(symbolTail, 0x20), symbolLength), 0)

            mstore(0x40, add(add(payload, payloadLength), 0x20))
            log4(
                payload,
                payloadLength,
                signature,
                mload(add(data, 0x20)),
                mload(add(data, 0x40)),
                mload(add(data, 0x60))
            )
        }
    }

    function _configureEngine(uint16 engineVersion, address implementation_, bool enabled) private {
        _validateAddress(implementation_, FIELD_IMPLEMENTATION);
        if (implementation_.code.length == 0) {
            revert InvalidEngineImplementation(implementation_);
        }

        uint16 actualVersion = 0;
        try IBondingCurveV1(implementation_).ENGINE_VERSION() returns (uint16 version) {
            actualVersion = version;
        } catch {
            revert InvalidEngineImplementation(implementation_);
        }
        if (actualVersion != engineVersion) {
            revert EngineVersionMismatch(engineVersion, actualVersion);
        }

        _engines[engineVersion] =
            EngineConfig({ implementation: implementation_, enabled: enabled });
        emit EngineConfigured(engineVersion, implementation_, enabled);
    }

    function _setFutureDefaults(LaunchTypes.FactoryDefaults memory defaults) private {
        CurveMath.validateParameters(defaults.parameters);
        _validateAddress(defaults.weth, FIELD_WETH);
        _validateAddress(defaults.uniswapFactory, FIELD_UNISWAP_FACTORY);

        _futureParameters = defaults.parameters;
        _weth = defaults.weth;
        _uniswapFactory = defaults.uniswapFactory;
        _launchFee = defaults.launchFee;
    }

    function _futureDefaults() private view returns (LaunchTypes.FactoryDefaults memory defaults) {
        defaults.parameters = _futureParameters;
        defaults.weth = _weth;
        defaults.uniswapFactory = _uniswapFactory;
        defaults.launchFee = _launchFee;
    }

    function _hashDefaults(LaunchTypes.FactoryDefaults memory defaults)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(defaults));
    }

    function _requirePauseAuthority() private view {
        if (msg.sender != _pauseAuthority) {
            revert UnauthorizedPauseAuthority(msg.sender, _pauseAuthority);
        }
    }

    function _requireTimelock() private view {
        if (msg.sender != _timelock) revert UnauthorizedTimelock(msg.sender, _timelock);
    }

    function _validateAddress(address account, bytes32 field) private pure {
        if (account == address(0)) revert ZeroAddress(field);
    }
}
