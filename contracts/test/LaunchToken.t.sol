// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILaunchErrors } from "../src/interfaces/ILaunchErrors.sol";
import { LaunchToken } from "../src/LaunchToken.sol";

contract LaunchTokenTest is Test {
    string private constant NAME = "Launch Token";
    string private constant SYMBOL = "LCH";
    bytes32 private constant FIELD_CURVE = "curve";
    bytes32 private constant FIELD_PAIR = "lpPair";
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant CURVE = address(0xC0DE);
    address private constant PAIR = address(0xBEEF);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant ATTACKER = address(0xBAD);

    LaunchToken private token;

    function setUp() external {
        token = new LaunchToken(NAME, SYMBOL, CURVE, SUPPLY);
        token.initializePair(PAIR);
    }

    function testConstructorMintsEntireSupplyToCurve() external {
        vm.expectEmit(true, true, false, true);
        // forge-lint: disable-next-line(reentrancy-events)
        emit IERC20.Transfer(address(0), CURVE, SUPPLY);

        LaunchToken deployed = new LaunchToken(NAME, SYMBOL, CURVE, SUPPLY);

        assertEq(deployed.name(), NAME);
        assertEq(deployed.symbol(), SYMBOL);
        assertEq(deployed.decimals(), 18);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(CURVE), SUPPLY);
        assertEq(deployed.curve(), CURVE);
        assertEq(deployed.lpPair(), address(0));
        assertFalse(deployed.graduated());
    }

    function testConstructorRejectsZeroCurve() external {
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, FIELD_CURVE));
        new LaunchToken(NAME, SYMBOL, address(0), SUPPLY);
    }

    function testPairCanOnlyBeInitializedOnceByFactory() external {
        LaunchToken uninitialized = new LaunchToken(NAME, SYMBOL, CURVE, SUPPLY);

        vm.prank(ATTACKER);
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.UnauthorizedFactory.selector, ATTACKER)
        );
        uninitialized.initializePair(PAIR);

        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, FIELD_PAIR));
        uninitialized.initializePair(address(0));

        uninitialized.initializePair(PAIR);
        assertEq(uninitialized.lpPair(), PAIR);

        vm.expectRevert(ILaunchErrors.AlreadyInitialized.selector);
        uninitialized.initializePair(address(0xCAFE));
    }

    function testUserToUserTransferWorksBeforeGraduation() external {
        _curveTransfer(ALICE, 100 ether);

        _transferAs(ALICE, BOB, 40 ether);

        assertEq(token.balanceOf(ALICE), 60 ether);
        assertEq(token.balanceOf(BOB), 40 ether);
    }

    function testUserToUserTransferFromWorksBeforeGraduation() external {
        _curveTransfer(ALICE, 100 ether);

        _approveAs(ALICE, BOB, 40 ether);
        _transferFromAs(BOB, ALICE, BOB, 40 ether);

        assertEq(token.balanceOf(ALICE), 60 ether);
        assertEq(token.balanceOf(BOB), 40 ether);
        assertEq(token.allowance(ALICE, BOB), 0);
    }

    function testCurveInitiatedBuySellAndLpTransfersWork() external {
        _curveTransfer(ALICE, 100 ether);

        _approveAs(ALICE, CURVE, 60 ether);
        _transferFromAs(CURVE, ALICE, CURVE, 60 ether);
        _transferAs(CURVE, PAIR, 25 ether);

        assertEq(token.balanceOf(ALICE), 40 ether);
        assertEq(token.balanceOf(PAIR), 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testDirectTransfersTouchingCurveOrPairRevert() external {
        _curveTransfer(ALICE, 100 ether);

        _expectRestrictedTransfer(ALICE, ALICE, CURVE);
        _expectRestrictedTransfer(ALICE, ALICE, PAIR);

        _approveAs(CURVE, ALICE, 1 ether);
        _expectRestrictedTransferFrom(ALICE, CURVE, BOB);

        _transferAs(CURVE, PAIR, 1 ether);
        _approveAs(PAIR, ALICE, 1 ether);
        _expectRestrictedTransferFrom(ALICE, PAIR, BOB);

        vm.prank(PAIR);
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.TransferRestricted.selector, PAIR, PAIR, BOB)
        );
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(BOB, 1 ether);
    }

    function testOnlyCurveCanMarkGraduatedOnce() external {
        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.UnauthorizedCurve.selector, ATTACKER));
        token.markGraduated();

        vm.prank(CURVE);
        token.markGraduated();
        assertTrue(token.graduated());

        vm.prank(CURVE);
        vm.expectRevert(ILaunchErrors.AlreadyGraduated.selector);
        token.markGraduated();
    }

    function testCannotGraduateBeforePairInitialization() external {
        LaunchToken uninitialized = new LaunchToken(NAME, SYMBOL, CURVE, SUPPLY);

        vm.prank(CURVE);
        vm.expectRevert(abi.encodeWithSelector(ILaunchErrors.ZeroAddress.selector, FIELD_PAIR));
        uninitialized.markGraduated();

        assertFalse(uninitialized.graduated());
    }

    function testTransfersIncludingPairWorkAfterGraduation() external {
        _curveTransfer(ALICE, 100 ether);

        vm.prank(CURVE);
        token.markGraduated();

        _transferAs(ALICE, PAIR, 40 ether);
        _transferAs(PAIR, BOB, 15 ether);
        _approveAs(BOB, ALICE, 5 ether);
        _transferFromAs(ALICE, BOB, CURVE, 5 ether);

        assertEq(token.balanceOf(PAIR), 25 ether);
        assertEq(token.balanceOf(BOB), 10 ether);
        assertEq(token.balanceOf(CURVE), SUPPLY - 95 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTotalSupplyNeverChangesAcrossTransfers(
        uint256 buyAmount,
        uint256 userTransfer,
        uint256 sellAmount,
        uint256 lpAmount
    ) external {
        buyAmount = bound(buyAmount, 1, SUPPLY);
        userTransfer = bound(userTransfer, 0, buyAmount);
        sellAmount = bound(sellAmount, 0, buyAmount - userTransfer);
        lpAmount = bound(lpAmount, 0, SUPPLY - buyAmount);

        _curveTransfer(ALICE, buyAmount);
        _transferAs(ALICE, BOB, userTransfer);
        _approveAs(ALICE, CURVE, sellAmount);
        _transferFromAs(CURVE, ALICE, CURVE, sellAmount);
        _transferAs(CURVE, PAIR, lpAmount);

        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.balanceOf(CURVE) + token.balanceOf(ALICE) + token.balanceOf(BOB)
                + token.balanceOf(PAIR),
            SUPPLY
        );
    }

    function testFuzzTransferFromCannotBypassRestrictedEndpoints(
        address operator,
        bool useCurve,
        uint256 amount
    ) external {
        vm.assume(operator != CURVE && operator != address(0));
        address restrictedEndpoint = useCurve ? CURVE : PAIR;
        amount = bound(amount, 0, 100 ether);
        _curveTransfer(ALICE, 100 ether);
        uint256 endpointBalanceBefore = token.balanceOf(restrictedEndpoint);

        _approveAs(ALICE, operator, amount);
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILaunchErrors.TransferRestricted.selector, operator, ALICE, restrictedEndpoint
            )
        );
        // forge-lint: disable-next-line(arbitrary-send-erc20, erc20-unchecked-transfer)
        token.transferFrom(ALICE, restrictedEndpoint, amount);

        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(restrictedEndpoint), endpointBalanceBefore);
    }

    function _curveTransfer(address recipient, uint256 amount) private {
        _transferAs(CURVE, recipient, amount);
    }

    function _transferAs(address operator, address to, uint256 amount) private {
        vm.prank(operator);
        assertTrue(token.transfer(to, amount));
    }

    function _approveAs(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function _transferFromAs(address operator, address from, address to, uint256 amount) private {
        vm.prank(operator);
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        assertTrue(token.transferFrom(from, to, amount));
    }

    function _expectRestrictedTransfer(address operator, address from, address to) private {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.TransferRestricted.selector, operator, from, to)
        );
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(to, 1 ether);
    }

    function _expectRestrictedTransferFrom(address operator, address from, address to) private {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(ILaunchErrors.TransferRestricted.selector, operator, from, to)
        );
        // forge-lint: disable-next-line(arbitrary-send-erc20, erc20-unchecked-transfer)
        token.transferFrom(from, to, 1 ether);
    }
}
