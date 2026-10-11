// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PebbleToken} from "../src/PebbleToken.sol";

/// @dev Exercises arbitrary sequences of ERC-20 operations among a closed set of holders.
contract TokenHandler is Test {
    PebbleToken public immutable token;
    address[3] public actors;
    // Independent accounting starts from the specified supply, never from observed balances.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PebbleToken token_) {
        token = token_;
        actors = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three")];
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = _amountAtEdges(amount, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Frequently exercise revocation, unlimited approval, and the largest finite approval.
        uint256 mode = amount % 4;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = _amountAtEdges(amount, balance < allowance ? balance : allowance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowance == type(uint256).max ? allowance : allowance - amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _recordTransfer(owner, to, amount);
    }

    function rejectOverBalance(uint256 ownerSeed, uint256 toSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(owner);
        token.transfer(to, amount);
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approved) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, 1_000_000_000 * 10 ** 18);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function rejectApprovedOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        _approve(owner, spender, balance + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, balance + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, balance + 1);
        // The global allowance invariant checks rollback of the attempted allowance deduction.
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = _amountAtEdges(amount, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        // Sequential updates also express the identity property when from == to.
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _amountAtEdges(uint256 seed, uint256 maximum) internal pure returns (uint256) {
        uint256 mode = seed % 4;
        if (mode == 0) return 0;
        if (mode == 1) return maximum;
        if (mode == 2) return maximum == 0 ? 0 : 1;
        return bound(seed, 0, maximum);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract PebbleTokenInvariantTest is StdInvariant, Test {
    PebbleToken private token;
    TokenHandler private handler;
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new PebbleToken();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectOverBalance.selector;
        selectors[4] = TokenHandler.rejectOverAllowance.selector;
        selectors[5] = TokenHandler.rejectApprovedOverBalance.selector;
        selectors[6] = TokenHandler.rejectZeroReceiver.selector;
        selectors[7] = TokenHandler.rejectZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndAllBalancesAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 balances;
        for (uint256 i; i < 3; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_EachHolderOwnsExactlyItsAccountedTokens() public view {
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder balance diverged");
        }
    }

    function invariant_OnlyApprovalsAndAuthorizedSpendingChangeAllowances() public view {
        for (uint256 i; i < 3; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 3; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "allowance diverged"
                );
            }
        }
    }

    function invariant_MetadataRemainsUnchanged() public view {
        assertEq(token.name(), "Pebble Agent");
        assertEq(token.symbol(), "PEBBLE");
        assertEq(token.decimals(), 18);
    }
}
