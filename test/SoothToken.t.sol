// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SoothToken} from "../src/SoothToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, TestVm} from "./support/TestBase.sol";

contract SoothTokenTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    SoothToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SoothToken();
    }

    function test_metadataAndEntireSupply() public view {
        assertEq(token.name(), "Sooth Protocol", "name");
        assertEq(token.symbol(), "SOOTH", "symbol");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "supply constant");
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.balanceOf(address(this)), SUPPLY, "deployer allocation");
        assertEq(token.balanceOf(address(token)), 0, "no token reserve");
        assertEq(token.balanceOf(address(0)), 0, "no zero-address allocation");
        assertEq(token.balanceOf(ALICE), 0, "unfunded account");
        assertEq(token.allowance(address(this), SPENDER), 0, "no initial allowance");
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        SoothToken deployed = new SoothToken();
        TestVm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one mint event");
        assertEq(logs[0].emitter, address(deployed), "mint emitter");
        assertEq(logs[0].topics.length, 3, "transfer topics");
        require(logs[0].topics[0] == keccak256("Transfer(address,address,uint256)"), "mint signature");
        require(logs[0].topics[1] == bytes32(0), "mint from zero");
        require(logs[0].topics[2] == bytes32(uint256(uint160(address(this)))), "mint recipient");
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "mint amount");
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 17 ether);
        require(token.transfer(ALICE, 17 ether), "transfer return");
        assertEq(token.balanceOf(ALICE), 17 ether, "exact receipt");
        assertEq(token.balanceOf(address(this)), SUPPLY - 17 ether, "exact debit");
        assertEq(token.totalSupply(), SUPPLY, "unchanged supply");
    }

    function test_transferEntireBalanceAndOneBaseUnitBack() public {
        require(token.transfer(ALICE, SUPPLY), "full transfer");
        assertEq(token.balanceOf(address(this)), 0, "empty sender");
        vm.prank(ALICE);
        require(token.transfer(address(this), 1), "base unit transfer");
        assertEq(token.balanceOf(address(this)), 1, "one base unit");
        assertEq(token.balanceOf(ALICE), SUPPLY - 1, "remaining balance");
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        require(token.transfer(BOB, 0), "zero transfer");
        assertEq(token.balanceOf(ALICE), 0, "empty sender unchanged");
        assertEq(token.balanceOf(BOB), 0, "receiver unchanged");
        assertEq(token.totalSupply(), SUPPLY, "unchanged supply");
    }

    function test_selfTransferPreservesBalance() public {
        require(token.transfer(address(this), SUPPLY), "self transfer");
        assertEq(token.balanceOf(address(this)), SUPPLY, "no duplication or loss");
        assertEq(token.totalSupply(), SUPPLY, "unchanged supply");
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY, "rejected transfer preserves balance");
        assertEq(token.totalSupply(), SUPPLY, "no implicit burn");
    }

    function test_transferInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0, "sender unchanged");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
    }

    function test_approveEmitsAndOnlyChangesCallersAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 20 ether);
        require(token.approve(SPENDER, 20 ether), "approval return");
        vm.prank(ALICE);
        require(token.approve(SPENDER, 7 ether), "empty holder may approve");
        assertEq(token.allowance(address(this), SPENDER), 20 ether, "deployer allowance");
        assertEq(token.allowance(ALICE, SPENDER), 7 ether, "alice allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY, "approve moves no tokens");
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        require(token.approve(SPENDER, 20 ether), "initial approve");
        require(token.approve(SPENDER, 3 ether), "replace approve");
        assertEq(token.allowance(address(this), SPENDER), 3 ether, "replace not add");
        require(token.approve(SPENDER, 0), "revoke");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 0, "revoked allowance");
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0, "no zero spender approval");
    }

    function test_transferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        require(token.approve(SPENDER, 20 ether), "approve");
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), BOB, 7 ether);
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, 7 ether), "delegated transfer");
        assertEq(token.allowance(address(this), SPENDER), 13 ether, "remaining allowance");
        assertEq(token.balanceOf(BOB), 7 ether, "exact receipt");
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether, "exact debit");
        assertEq(token.balanceOf(SPENDER), 0, "spender gets no fee");
    }

    function test_exhaustedAllowanceCannotBeReused() public {
        require(token.approve(SPENDER, 10), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, 10), "spend exact allowance");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.balanceOf(BOB), 10, "no repeat spend");
    }

    function test_unlimitedAllowanceRemainsUnlimited() public {
        require(token.approve(SPENDER, type(uint256).max), "approve");
        vm.startPrank(SPENDER);
        require(token.transferFrom(address(this), BOB, 10 ether), "first spend");
        require(token.transferFrom(address(this), ALICE, 5 ether), "second spend");
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max, "unlimited allowance preserved");
        assertEq(token.balanceOf(address(this)), SUPPLY - 15 ether, "exact debit");
    }

    function test_unauthorizedSpenderCannotUseSomeoneElsesApproval() public {
        require(token.approve(SPENDER, 10 ether), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 10 ether, "other approval preserved");
        assertEq(token.balanceOf(address(this)), SUPPLY, "balance preserved");
    }

    function test_transferFromInsufficientAllowanceIsAtomic() public {
        require(token.approve(SPENDER, 5), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 5, 6));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, 6);
        assertEq(token.allowance(address(this), SPENDER), 5, "allowance preserved");
        assertEq(token.balanceOf(address(this)), SUPPLY, "balance preserved");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        require(token.approve(SPENDER, 100), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100, "allowance rolled back");
        assertEq(token.balanceOf(BOB), 0, "recipient unchanged");
    }

    function test_transferFromToZeroRestoresAllowance() public {
        require(token.approve(SPENDER, 100), "approve");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100, "allowance rolled back");
        assertEq(token.balanceOf(address(this)), SUPPLY, "sender unchanged");
    }

    function test_transferFromZeroSenderReverts() public {
        // OpenZeppelin validates the allowance owner before reaching the transfer's sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), BOB, 0);
        assertEq(token.balanceOf(BOB), 0, "no accidental mint");
        assertEq(token.totalSupply(), SUPPLY, "no supply growth");
    }

    function test_zeroTransferFromWithoutAllowanceEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        require(token.transferFrom(ALICE, BOB, 0), "zero transferFrom");
        assertEq(token.allowance(ALICE, SPENDER), 0, "allowance unchanged");
    }

    function test_delegatedSelfTransferSpendsAllowanceWithoutChangingBalance() public {
        require(token.approve(SPENDER, 100), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(this), 100), "delegated self transfer");
        assertEq(token.allowance(address(this), SPENDER), 0, "spent allowance");
        assertEq(token.balanceOf(address(this)), SUPPLY, "balance conserved");
    }

    function test_holderUsesTransferOrApprovesItselfForTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        require(token.approve(address(this), 1), "self approve");
        require(token.transferFrom(address(this), ALICE, 1), "self delegated transfer");
        assertEq(token.balanceOf(ALICE), 1, "exact receipt");
    }

    function test_noMintBurnAdministrativeOrUpgradeEntryPoints() public {
        require(token.transfer(ALICE, 100 ether), "fund holder");
        bytes[14] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether),
            abi.encodeWithSignature("mint(uint256)", 1 ether),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("burn(uint256)", 1 ether),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("freeze(address)", ALICE),
            abi.encodeWithSignature("seize(address)", ALICE),
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("setMinter(address)", BOB)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            require(!deployerSucceeded, "unexpected deployer capability");
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            require(!strangerSucceeded, "unexpected public capability");
            assertEq(token.totalSupply(), SUPPLY, "fixed supply");
            assertEq(token.balanceOf(ALICE), 100 ether, "holder balance untouched");
        }
        vm.prank(ALICE);
        require(token.transfer(BOB, 100 ether), "holder remains free to transfer");
        assertEq(token.balanceOf(BOB), 100 ether, "holder received no restrictions");
    }

    function test_nativeCurrencyAndUnknownCallsAreRejected() public {
        vm.deal(address(this), 1 ether);
        (bool funded,) = address(token).call{value: 1 ether}("");
        require(!funded, "native deposit rejected");
        (bool unknown,) = address(token).call(hex"ffffffff");
        require(!unknown, "no fallback entry point");
        assertEq(address(token).balance, 0, "no native currency accepted");
    }

    function testFuzz_transferConservesSupply(uint256 rawAmount, address recipient) public {
        // Zero and self recipients have separate boundary tests above.
        if (recipient == address(0) || recipient == address(this)) return;
        uint256 amount = rawAmount % (SUPPLY + 1);
        require(token.transfer(recipient, amount), "transfer");
        assertEq(token.balanceOf(recipient), amount, "exact credit");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "exact debit");
        assertEq(token.totalSupply(), SUPPLY, "supply conserved");
    }

    function testFuzz_overspendAlwaysReverts(uint256 rawAmount) public {
        uint256 amount = SUPPLY + 1 + rawAmount % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY, "balance preserved");
        assertEq(token.balanceOf(ALICE), 0, "no overdraft credit");
    }

    function testFuzz_delegatedTransferConservesBalanceAndAllowance(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = rawAllowance % (SUPPLY + 1);
        uint256 amount = rawAmount % (approved + 1);
        require(token.approve(SPENDER, approved), "approve");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), BOB, amount), "transferFrom");
        assertEq(token.allowance(address(this), SPENDER), approved - amount, "allowance consumed exactly");
        assertEq(token.balanceOf(BOB), amount, "recipient credited exactly");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "holder debited exactly");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply");
    }
}
