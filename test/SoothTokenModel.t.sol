// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SoothToken} from "../src/SoothToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./support/TestBase.sol";

/// @notice Compare randomized operation sequences against an independent balance/allowance ledger.
contract SoothTokenModelTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 private constant STEPS = 32;

    SoothToken private token;
    address[4] private actors;
    uint256[4] private balances;
    uint256[4][4] private allowances;

    function setUp() public {
        token = new SoothToken();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA11)];
        balances[0] = SUPPLY;
    }

    function testFuzz_operationSequencePreservesLedger(bytes32 seed) public {
        for (uint256 step; step < STEPS; ++step) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, step)));
            uint256 from = entropy % actors.length;
            uint256 to = (entropy >> 8) % actors.length;
            uint256 spender = (entropy >> 16) % actors.length;
            uint256 operation = (entropy >> 24) % 3;
            uint256 amount;
            if (operation == 1) {
                amount = (entropy >> 32) % 4 == 0 ? type(uint256).max : (entropy >> 40) % (SUPPLY + 1);
                vm.prank(actors[from]);
                require(token.approve(actors[spender], amount), "model approve");
                allowances[from][spender] = amount;
            } else {
                // Deliberately include zero, exact balance, overspend, and arbitrary partial amounts.
                uint256 boundary = (entropy >> 32) % 4;
                if (boundary == 0) amount = 0;
                else if (boundary == 1) amount = balances[from];
                else if (boundary == 2) amount = balances[from] + 1;
                else amount = (entropy >> 40) % (balances[from] + 1);

                if (operation == 0) _transfer(from, to, amount);
                else _transferFrom(from, to, spender, amount);
            }
            _assertLedger();
        }
    }

    function _transfer(uint256 from, uint256 to, uint256 amount) private {
        bool succeeds = amount <= balances[from];
        if (!succeeds) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balances[from], amount
                )
            );
        }
        vm.prank(actors[from]);
        token.transfer(actors[to], amount);
        if (succeeds) {
            balances[from] -= amount;
            balances[to] += amount;
        }
    }

    function _transferFrom(uint256 from, uint256 to, uint256 spender, uint256 amount) private {
        uint256 approved = allowances[from][spender];
        bool succeeds = approved >= amount && balances[from] >= amount;
        if (approved < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], approved, amount
                )
            );
        } else if (balances[from] < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balances[from], amount
                )
            );
        }
        vm.prank(actors[spender]);
        token.transferFrom(actors[from], actors[to], amount);
        if (succeeds) {
            if (approved != type(uint256).max) allowances[from][spender] -= amount;
            balances[from] -= amount;
            balances[to] += amount;
        }
    }

    function _assertLedger() private view {
        uint256 total;
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), balances[i], "model balance mismatch");
            total += balances[i];
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), allowances[i][j], "model allowance mismatch");
            }
        }
        assertEq(total, SUPPLY, "modeled balance conservation");
        assertEq(token.totalSupply(), SUPPLY, "fixed token supply");
        assertEq(token.balanceOf(address(0)), 0, "zero address never funded");
    }
}
