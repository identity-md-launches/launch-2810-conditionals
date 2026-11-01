// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev Supplements the existing examples with integer boundaries, recovery, and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract ConditionalsPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Conditionals private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new Conditionals();
        alice = makeAddr("property-alice");
        bob = makeAddr("property-bob");
        spender = makeAddr("property-spender");
    }

    function test_maximumTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDelegatedSpendDoesNotBypassBalanceCheck() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, type(uint256).max);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceIsStillConsumed() public {
        uint256 approved = type(uint256).max - 1;
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_fullSupplyDelegatedSpendCannotBeReplayed() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerRequiresSelfApprovalForDelegatedSpend() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_infiniteApprovalCanBeReducedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);

        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_approvalIsNotTransferredWithTokens() public {
        token.transfer(alice, 2);
        vm.prank(alice);
        token.approve(spender, 2);
        vm.prank(alice);
        token.transfer(bob, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(bob, spender, 1);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(bob), 2);

        // The approval still belongs to Alice and becomes spendable when she receives tokens again.
        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 1));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(spender), 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_zeroSpenderRejectsEvenZeroApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_zeroReceiverRejectsEvenZeroDelegatedSpend() public {
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Cheatcode-only caller: cover inherited zero-address guards without exposing internals.
    function test_zeroCallerCannotTransferOrApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_constructorCreditsImmediateDeployer(uint160 rawDeployer) public {
        address deployer = address(uint160(bound(uint256(rawDeployer), 1, type(uint160).max)));
        vm.prank(deployer);
        Conditionals created = new Conditionals();
        assertEq(created.balanceOf(deployer), SUPPLY);
        assertEq(created.totalSupply(), SUPPLY);
        assertEq(created.balanceOf(address(0)), 0);
        if (deployer != address(this)) assertEq(created.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripRestoresBalancesAndApprovals(uint256 rawBalance, uint256 rawAmount, uint256 allowance)
        public
    {
        uint256 held = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, held);
        token.transfer(alice, held);
        token.transfer(bob, SUPPLY - held);
        vm.prank(alice);
        token.approve(spender, allowance);
        vm.prank(bob);
        token.approve(spender, allowance);

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), held - amount);
        assertEq(token.balanceOf(bob), SUPPLY - held + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), SUPPLY - held);
        assertEq(token.allowance(alice, spender), allowance);
        assertEq(token.allowance(bob, spender), allowance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_directAndDelegatedTransfersAgree(uint256 rawAmount, bool infinite) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        Conditionals direct = new Conditionals();
        assertTrue(direct.transfer(alice, amount));
        uint256 approved = infinite ? type(uint256).max : amount;
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), direct.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), direct.balanceOf(address(this)));
        assertEq(token.totalSupply(), direct.totalSupply());
        assertEq(token.allowance(address(this), spender), infinite ? type(uint256).max : 0);
    }

    function testFuzz_splitTransfersAgreeWithSingleTransfer(uint256 rawTotal, uint256 rawFirst) public {
        uint256 total = bound(rawTotal, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, total);
        Conditionals combined = new Conditionals();
        assertTrue(combined.transfer(alice, total));
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, total - first));
        assertEq(token.balanceOf(alice), combined.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), combined.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 rawBalance, uint256 rawAmount, bool infinite) public {
        uint256 held = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, held + 1, SUPPLY);
        token.transfer(alice, held);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);

        token.transfer(alice, amount - held);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalIsScopedToOwnerAndSpender(uint256 rawAmount, uint256 approved) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.prank(bob);
        token.approve(spender, type(uint256).max);

        // Bob cannot use Alice's approval to the spender, even though Bob can approve that spender himself.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        vm.prank(bob);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(bob, spender), type(uint256).max);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
