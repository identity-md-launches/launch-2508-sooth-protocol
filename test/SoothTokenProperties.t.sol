// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SoothToken} from "../src/SoothToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, TestVm} from "./support/TestBase.sol";

/// forge-config: default.fuzz.runs = 1024
contract SoothTokenPropertiesTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant HOLDER = address(0xA11CE);
    address private constant RECIPIENT = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    SoothToken private token;

    function setUp() public {
        token = new SoothToken();
    }

    function testFuzz_roundTripRestoresBalancesButDoesNotRestoreApproval(uint256 seed) public {
        uint256 amount = seed % (SUPPLY + 1);
        require(token.approve(SPENDER, amount), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), RECIPIENT, amount), "outbound");
        vm.prank(RECIPIENT);
        require(token.transfer(address(this), amount), "return");
        assertEq(token.balanceOf(address(this)), SUPPLY, "round trip lost or created value");
        assertEq(token.balanceOf(RECIPIENT), 0, "recipient retained value");
        assertEq(token.allowance(address(this), SPENDER), 0, "return replenished spent approval");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, 1);
        assertEq(token.totalSupply(), SUPPLY, "round trip changed supply");
    }

    function testFuzz_largeFiniteApprovalIsConsumed(uint256 seed) public {
        // Generate every finite approval strictly above supply, including max - 1.
        uint256 approved = SUPPLY + 1 + seed % (type(uint256).max - SUPPLY - 1);
        _spendSupplyWithApproval(approved);
    }

    function test_maxMinusOneApprovalIsFinite() public {
        _spendSupplyWithApproval(type(uint256).max - 1);
    }

    function testFuzz_failedSpendAfterPartialUseCanBeRetriedAfterFunding(uint256 fundingSeed, uint256 spendSeed)
        public
    {
        uint256 funding = 1 + fundingSeed % (SUPPLY - 1);
        uint256 firstSpend = 1 + spendSeed % funding;
        require(token.transfer(HOLDER, funding), "fund holder");
        vm.prank(HOLDER);
        require(token.approve(SPENDER, SUPPLY + 1), "approve more than balance");
        vm.prank(SPENDER);
        require(token.transferFrom(HOLDER, RECIPIENT, firstSpend), "partial spend");

        uint256 remainingBalance = funding - firstSpend;
        uint256 remainingApproval = SUPPLY + 1 - firstSpend;
        uint256 attempted = remainingBalance + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, remainingBalance, attempted)
        );
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, attempted);
        assertEq(token.allowance(HOLDER, SPENDER), remainingApproval, "failed spend consumed approval");
        assertEq(token.balanceOf(HOLDER), remainingBalance, "failed spend debited holder");
        assertEq(token.balanceOf(RECIPIENT), firstSpend, "failed spend credited recipient");

        // Balance, rather than permission, was the limiting factor. The exact same
        // delegated call must work after one base unit arrives, without reapproval.
        require(token.transfer(HOLDER, 1), "refill one unit");
        vm.prank(SPENDER);
        require(token.transferFrom(HOLDER, RECIPIENT, attempted), "retry after funding");
        assertEq(token.balanceOf(HOLDER), 0, "retry did not empty holder");
        assertEq(token.balanceOf(RECIPIENT), funding + 1, "retry receipt");
        assertEq(token.allowance(HOLDER, SPENDER), SUPPLY - funding, "retry allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY - funding - 1, "funding debit");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }

    function test_rejectedDelegatedTransferLeavesNoEventsOrStateChanges() public {
        require(token.approve(SPENDER, SUPPLY), "approve");
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), SUPPLY);
        TestVm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0, "rejected transaction emitted logs");
        assertEq(token.allowance(address(this), SPENDER), SUPPLY, "failed transfer consumed allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY, "failed transfer changed balance");
        assertEq(token.totalSupply(), SUPPLY, "failed transfer burned supply");
    }

    function test_maximumDelegatedSpendCannotBypassBalanceWithUnlimitedApproval() public {
        require(token.approve(SPENDER, type(uint256).max), "approve unlimited");
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), RECIPIENT, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max, "unlimited approval changed");
        assertEq(token.balanceOf(address(this)), SUPPLY, "overspend changed balance");
        assertEq(token.balanceOf(RECIPIENT), 0, "overspend credited recipient");
        assertEq(token.totalSupply(), SUPPLY, "overspend changed supply");
    }

    function _spendSupplyWithApproval(uint256 approved) private {
        require(token.approve(SPENDER, approved), "approve large finite amount");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), RECIPIENT, SUPPLY), "spend supply");
        assertEq(token.allowance(address(this), SPENDER), approved - SUPPLY, "finite approval not consumed");
        assertEq(token.balanceOf(address(this)), 0, "sender not emptied");
        assertEq(token.balanceOf(RECIPIENT), SUPPLY, "recipient did not receive supply");
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
    }
}
