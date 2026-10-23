// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SoothToken} from "../src/SoothToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev All recipients and approval owners stay in this closed actor set. Ghost state is
/// derived from requested operations, never copied back from the token after a call.
contract SoothTokenHandler is TestBase {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SoothToken public immutable token;
    address[4] public actors;
    uint256[4] public expectedBalances;
    mapping(uint256 => mapping(uint256 => uint256)) public expectedAllowances;
    uint256 public successfulTransfers;
    uint256 public successfulDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor() {
        token = new SoothToken();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA11)];
        expectedBalances[0] = SUPPLY;
        for (uint256 i = 1; i < actors.length; ++i) {
            require(token.transfer(actors[i], SUPPLY / 4), "seed transfer");
            _move(0, i, SUPPLY / 4);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 amount = _amount(amountSeed, expectedBalances[from]);
        vm.prank(actors[from]);
        require(token.transfer(actors[to], amount), "transfer returned false");
        _move(from, to, amount);
        ++successfulTransfers;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        // Includes revoke, one wei, finite approvals above the supply, and unlimited.
        uint256 amount;
        if (amountSeed % 4 == 0) amount = 0;
        else if (amountSeed % 4 == 1) amount = 1;
        else if (amountSeed % 4 == 2) amount = type(uint256).max;
        else amount = amountSeed;
        vm.prank(actors[owner]);
        require(token.approve(actors[spender], amount), "approve returned false");
        expectedAllowances[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 allowance = expectedAllowances[owner][spender];
        uint256 limit = expectedBalances[owner] < allowance ? expectedBalances[owner] : allowance;
        uint256 amount = _amount(amountSeed, limit);
        vm.prank(actors[spender]);
        require(token.transferFrom(actors[owner], actors[to], amount), "transferFrom returned false");
        if (allowance != type(uint256).max) expectedAllowances[owner][spender] -= amount;
        _move(owner, to, amount);
        ++successfulDelegatedTransfers;
    }

    function rejectOverdraft(uint256 fromSeed, uint256 toSeed, bool maximum) external {
        uint256 from = fromSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 balance = expectedBalances[from];
        uint256 amount = maximum ? type(uint256).max : balance + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[from], balance, amount)
        );
        vm.prank(actors[from]);
        token.transfer(actors[to], amount);
        ++rejectedCalls;
    }

    function rejectAllowanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 to = toSeed % actors.length;
        // Revoking is a real transaction, then the spender tries to reuse the approval.
        vm.prank(actors[owner]);
        require(token.approve(actors[spender], 0), "revoke returned false");
        expectedAllowances[owner][spender] = 0;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], 0, 1));
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[to], 1);
        ++rejectedCalls;
    }

    function rejectDelegatedOverdraft(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool unlimited) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 to = toSeed % actors.length;
        uint256 balance = expectedBalances[owner];
        uint256 amount = balance + 1;
        uint256 allowance = unlimited ? type(uint256).max : amount;
        vm.prank(actors[owner]);
        require(token.approve(actors[spender], allowance), "approve returned false");
        expectedAllowances[owner][spender] = allowance;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], balance, amount)
        );
        vm.prank(actors[spender]);
        token.transferFrom(actors[owner], actors[to], amount);
        // The ledger deliberately retains the full approval: failed spending must roll back.
        ++rejectedCalls;
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        uint256 owner = ownerSeed % actors.length;
        uint256 spender = spenderSeed % actors.length;
        uint256 amount = _amount(amountSeed, expectedBalances[owner]);
        if (delegated) {
            vm.prank(actors[owner]);
            require(token.approve(actors[spender], amount), "approve returned false");
            expectedAllowances[owner][spender] = amount;
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? actors[spender] : actors[owner]);
        if (delegated) token.transferFrom(actors[owner], address(0), amount);
        else token.transfer(address(0), amount);
        ++rejectedCalls;
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        uint256 owner = ownerSeed % actors.length;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(actors[owner]);
        token.approve(address(0), amount);
        ++rejectedCalls;
    }

    /// @dev Boundary cases have explicit probability, while the remaining inputs cover
    /// the full feasible interval without discarded runs or assumptions.
    function _amount(uint256 seed, uint256 limit) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return seed % (limit + 1);
    }

    function _move(uint256 from, uint256 to, uint256 amount) private {
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
    }
}

/// @dev Uses Foundry's target discovery ABI directly, so no new dependency is needed.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SoothTokenInvariantTest is TestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SoothTokenHandler private handler;
    SoothToken private token;

    function setUp() public {
        handler = new SoothTokenHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = SoothTokenHandler.transfer.selector;
        selectors[1] = SoothTokenHandler.approve.selector;
        selectors[2] = SoothTokenHandler.transferFrom.selector;
        selectors[3] = SoothTokenHandler.rejectOverdraft.selector;
        selectors[4] = SoothTokenHandler.rejectAllowanceOverspend.selector;
        selectors[5] = SoothTokenHandler.rejectDelegatedOverdraft.selector;
        selectors[6] = SoothTokenHandler.rejectZeroRecipient.selector;
        selectors[7] = SoothTokenHandler.rejectZeroSpender.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_supplyIsFixedAndEveryTokenIsAccountedFor() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply changed after construction");
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY, "tokens created, lost, or credited outside the actor set");
        assertEq(token.balanceOf(address(0)), 0, "zero address credited");
        assertEq(token.balanceOf(address(token)), 0, "unexpected token reserve");
    }

    function invariant_balancesMatchRequestedMovements() public view {
        for (uint256 i; i < 4; ++i) {
            assertEq(token.balanceOf(handler.actors(i)), handler.expectedBalances(i), "holder balance mismatch");
        }
    }

    function invariant_onlyApprovedSpendingChangesAllowances() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0, "zero spender authorized");
            for (uint256 j; j < 4; ++j) {
                assertEq(
                    token.allowance(owner, handler.actors(j)),
                    handler.expectedAllowances(i, j),
                    "approval isolation, consumption, or rollback mismatch"
                );
            }
        }
    }

    function invariant_metadataDoesNotChange() public view {
        assertEq(token.name(), "Sooth Protocol", "name changed");
        assertEq(token.symbol(), "SOOTH", "symbol changed");
        assertEq(token.decimals(), 18, "decimals changed");
    }

    /// @notice A deterministic sequence makes the handler's nonzero spend and failure
    /// branches reviewable independently of the random campaign's call distribution.
    function test_handlerExercisesSpendingRevocationAndRollback() public {
        handler.transfer(0, 1, 1);
        handler.approve(1, 2, 2); // unlimited
        handler.transferFrom(1, 2, 3, 1);
        handler.transferFrom(1, 2, 1, 2); // self transfer with unlimited approval
        handler.approve(1, 2, 7); // finite
        handler.transferFrom(1, 2, 3, 2); // exhaust allowance
        handler.rejectAllowanceOverspend(1, 2, 3);
        handler.rejectOverdraft(0, 0, true);
        handler.rejectDelegatedOverdraft(0, 2, 3, false);
        handler.rejectDelegatedOverdraft(0, 2, 3, true);
        handler.rejectZeroRecipient(0, 2, 2, true);
        handler.rejectZeroRecipient(0, 2, 0, false);
        handler.rejectZeroSpender(0, type(uint256).max);
        assertEq(handler.successfulTransfers(), 1, "direct path not reached");
        assertEq(handler.successfulDelegatedTransfers(), 3, "delegated path not reached");
        assertEq(handler.rejectedCalls(), 7, "failure paths not reached");
        invariant_supplyIsFixedAndEveryTokenIsAccountedFor();
        invariant_balancesMatchRequestedMovements();
        invariant_onlyApprovedSpendingChangesAllowances();
        invariant_metadataDoesNotChange();
    }
}
