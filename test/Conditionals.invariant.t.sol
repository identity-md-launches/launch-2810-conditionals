// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev Only these four actors can receive tokens during this stateful test.
/// The independent balance/allowance model checks each operation, including self-transfers.
contract ConditionalsHandler is Test {
    Conditionals public immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public transferCalls;
    uint256 public approvalCalls;
    uint256 public transferFromCalls;
    uint256 public rejectedCalls;
    uint256 public roundTripCalls;

    constructor(Conditionals token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = token_.totalSupply();
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ++transferCalls;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        ++approvalCalls;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        uint256 amount = bound(rawAmount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        ++transferFromCalls;
    }

    /// @dev Explicitly reach approvals that unrestricted random values rarely produce.
    function boundaryApproval(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[4] memory amounts = [uint256(0), 1, type(uint256).max - 1, type(uint256).max];
        uint256 amount = amounts[mode % amounts.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        ++approvalCalls;
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ++transferCalls;
    }

    /// @dev Always spend a positive amount, even before random approvals have accumulated.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, bool infinite)
        external
    {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 1, expectedBalance[owner]);
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedAllowance[owner][spender] = infinite ? approved : 0;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        ++approvalCalls;
        ++transferFromCalls;
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = held + bound(rawExcess, 1, type(uint256).max - held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
        ++rejectedCalls;
    }

    function rejectTransferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawAllowance
    ) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        // Keep the balance sufficient, so only the allowance can reject this call.
        uint256 approved = bound(rawAllowance, 0, expectedBalance[owner] - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
        ++approvalCalls;
        ++rejectedCalls;
    }

    function rejectTransferFromAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[owner];
        uint256 amount = held + 1;
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // In particular, a finite allowance must not be consumed by this failure.
        ++approvalCalls;
        ++rejectedCalls;
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[owner]);
        if (delegated) {
            vm.prank(owner);
            assertTrue(token.approve(spender, amount));
            expectedAllowance[owner][spender] = amount;
            ++approvalCalls;
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
        ++rejectedCalls;
    }

    /// @dev An inverse property independent of the balance update model.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % actors.length];
        if (to == from) to = actors[(toSeed % actors.length + 1) % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 1, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), beforeFrom - amount);
        assertEq(token.balanceOf(to), beforeTo + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), beforeFrom);
        assertEq(token.balanceOf(to), beforeTo);
        ++roundTripCalls;
        transferCalls += 2;
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(start + i) % actors.length];
            if (expectedBalance[candidate] > 0) return candidate;
        }
        revert("the fixed supply must have a holder");
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ConditionalsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    Conditionals private token;
    ConditionalsHandler private handler;

    function setUp() public {
        token = new Conditionals();
        address[4] memory actors = [makeAddr("actor0"), makeAddr("actor1"), makeAddr("actor2"), makeAddr("actor3")];
        handler = new ConditionalsHandler(token, actors);
        token.transfer(actors[0], SUPPLY);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = ConditionalsHandler.transfer.selector;
        selectors[1] = ConditionalsHandler.approve.selector;
        selectors[2] = ConditionalsHandler.transferFrom.selector;
        selectors[3] = ConditionalsHandler.boundaryApproval.selector;
        selectors[4] = ConditionalsHandler.transferAll.selector;
        selectors[5] = ConditionalsHandler.approveAndSpend.selector;
        selectors[6] = ConditionalsHandler.rejectTransferAboveBalance.selector;
        selectors[7] = ConditionalsHandler.rejectTransferFromAboveAllowance.selector;
        selectors[8] = ConditionalsHandler.rejectTransferFromAboveBalance.selector;
        selectors[9] = ConditionalsHandler.rejectZeroReceiver.selector;
        selectors[10] = ConditionalsHandler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_metadataIsStable() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev Pin a nonzero failure/recovery sequence alongside the random campaigns.
    function test_handlerFailureAndRecoverySequence() public {
        handler.transferAll(0, 1);
        handler.rejectTransferAboveBalance(0, 1, 1);
        handler.rejectTransferFromAboveAllowance(1, 2, 3, 1);
        handler.rejectTransferFromAboveBalance(1, 2, 3, false);
        handler.rejectTransferFromAboveBalance(1, 2, 3, true);
        handler.rejectZeroReceiver(1, 2, 1, true);
        handler.rejectZeroReceiver(1, 2, 0, false);
        handler.boundaryApproval(1, 2, 3);
        handler.approveAndSpend(1, 2, 3, SUPPLY, false);
        handler.roundTrip(3, 0, SUPPLY);
        assertEq(handler.rejectedCalls(), 6);
        assertEq(handler.roundTripCalls(), 1);
        assertEq(handler.transferFromCalls(), 1);
        invariant_totalSupplyIsFixed();
        invariant_metadataIsStable();
        invariant_balancesMatchModelAndConserveSupply();
        invariant_allowancesMatchModel();
    }

    function invariant_balancesMatchModelAndConserveSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actor(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actor(i);
                address spender = handler.actor(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
