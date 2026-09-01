// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

abstract contract LaunchTokenStorage {
    address internal _factory;
    address internal _curve;
    address internal _lpPair;
    bool internal _graduated;
}
