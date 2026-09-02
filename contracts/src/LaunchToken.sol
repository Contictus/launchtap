// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ILaunchToken } from "./interfaces/ILaunchToken.sol";
import { LaunchTokenStorage } from "./storage/LaunchTokenStorage.sol";

/// @notice Fixed-supply launch token with curve-phase reserve protections.
contract LaunchToken is ERC20, LaunchTokenStorage, ILaunchToken {
    bytes32 private constant FIELD_CURVE = "curve";
    bytes32 private constant FIELD_PAIR = "lpPair";

    /// @param curve_ Bonding curve that receives and distributes the fixed supply.
    constructor(string memory name_, string memory symbol_, address curve_, uint256 totalSupply_)
        ERC20(name_, symbol_)
    {
        if (curve_ == address(0)) revert ZeroAddress(FIELD_CURVE);

        _factory = msg.sender;
        _curve = curve_;
        _mint(curve_, totalSupply_);
    }

    /// @inheritdoc ILaunchToken
    function curve() external view returns (address) {
        return _curve;
    }

    /// @inheritdoc ILaunchToken
    function lpPair() external view returns (address) {
        return _lpPair;
    }

    /// @inheritdoc ILaunchToken
    function graduated() external view returns (bool) {
        return _graduated;
    }

    /// @inheritdoc ILaunchToken
    function initializePair(address pair) external {
        if (msg.sender != _factory) revert UnauthorizedFactory(msg.sender);
        if (_lpPair != address(0)) revert AlreadyInitialized();
        if (pair == address(0)) revert ZeroAddress(FIELD_PAIR);

        // TokenLaunched records the immutable pair after atomic factory initialization.
        // forge-lint: disable-next-line(missing-events-access-control)
        _lpPair = pair;
    }

    /// @inheritdoc ILaunchToken
    function markGraduated() external {
        if (msg.sender != _curve) revert UnauthorizedCurve(msg.sender);
        if (_graduated) revert AlreadyGraduated();
        if (_lpPair == address(0)) revert ZeroAddress(FIELD_PAIR);

        _graduated = true;
    }

    /// @dev During the curve phase, only the curve may operate transfers that touch its
    /// inventory or the canonical pair. The constructor mint is explicitly exempt.
    function _update(address from, address to, uint256 value) internal override {
        address operator = _msgSender();
        if (
            !_graduated && from != address(0) && operator != _curve
                && (from == _curve || to == _curve || from == _lpPair || to == _lpPair)
        ) {
            revert TransferRestricted(operator, from, to);
        }

        super._update(from, to, value);
    }
}
