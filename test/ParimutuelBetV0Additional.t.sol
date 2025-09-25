// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ParimutuelBetV0} from "../src/ParimutuelBetV0.sol";

contract ParimutuelBetV0AdditionalTest is Test {
    ParimutuelBetV0 public parimutuel;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public creator = makeAddr("creator");

    uint256 constant INITIAL_BALANCE = 10 ether;

    function setUp() public {
        parimutuel = new ParimutuelBetV0();
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(creator, INITIAL_BALANCE);
    }

    // Test refund functionality
    function test_RefundAfterDeadline() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        // Place bets
        vm.prank(alice);
        parimutuel.placeBet{value: 2 ether}(marketId, true);

        vm.prank(bob);
        parimutuel.placeBet{value: 3 ether}(marketId, false);

        // Move past deadline + refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        // Test refund
        vm.prank(alice);
        parimutuel.refund(marketId);

        vm.prank(bob);
        parimutuel.refund(marketId);

        // Verify refunds
        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertEq(bob.balance, bobBalanceBefore + 3 ether);
    }

    function test_CannotRefundTwice() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        vm.warp(block.timestamp + 1 days + 7 days + 1);

        vm.prank(alice);
        parimutuel.refund(marketId);

        vm.prank(alice);
        vm.expectRevert("Already refunded");
        parimutuel.refund(marketId);
    }

    function test_RefundBeforeRefundPeriod() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        // Only move past deadline, not refund period
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(alice);
        vm.expectRevert("Refund period not reached");
        parimutuel.refund(marketId);
    }

    function test_RefundAfterResolution() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        // Resolve before refund period
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

        // Move past refund period
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        vm.expectRevert("Market already resolved");
        parimutuel.refund(marketId);
    }

    // Test single-sided betting scenarios
    function test_OnlyYesBets() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        // Only YES bets
        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        vm.warp(block.timestamp + 1 days + 1);

        // Resolve to YES (Alice wins, no NO bets to split with)
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

        // Alice should get full pot since she's the only bettor
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        parimutuel.claim(marketId);

        assertEq(alice.balance, balanceBefore + 1 ether);
    }

    function test_OnlyNoBets() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        // Only NO bets
        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, false);

        vm.warp(block.timestamp + 1 days + 1);

        // Resolve to NO (Alice wins, no YES bets to split with)
        vm.prank(creator);
        parimutuel.resolve(marketId, false);

        // Alice should get full pot since she's the only bettor
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        parimutuel.claim(marketId);

        assertEq(alice.balance, balanceBefore + 1 ether);
    }

    // Test market creation edge cases
    function test_CreateMarketWithPastDeadline() public {
        vm.prank(creator);
        vm.expectRevert("Deadline must be in future");
        parimutuel.createMarket("Test", block.timestamp - 1);
    }

    function test_CreateMarketWithCurrentTimestamp() public {
        vm.prank(creator);
        vm.expectRevert("Deadline must be in future");
        parimutuel.createMarket("Test", block.timestamp);
    }

    // Test betting edge cases
    function test_ZeroBetReverts() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectRevert("Bet amount must be greater than 0");
        parimutuel.placeBet{value: 0}(marketId, true);
    }

    function test_BetOnNonexistentMarket() public {
        vm.prank(alice);
        vm.expectRevert("Market does not exist");
        parimutuel.placeBet{value: 1 ether}(999, true);
    }

    function test_BetAfterDeadlinePrecedesResolvedCheck() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        // Move past deadline and resolve
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

        // Try to bet - deadline check comes before resolved check
        vm.prank(bob);
        vm.expectRevert("Betting period has ended");
        parimutuel.placeBet{value: 1 ether}(marketId, false);
    }

    // Test multiple bets by same user
    function test_MultipleBetsBySameUser() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        // Alice makes multiple YES bets
        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        vm.prank(alice);
        parimutuel.placeBet{value: 2 ether}(marketId, true);

        // Alice also makes a NO bet
        vm.prank(alice);
        parimutuel.placeBet{value: 0.5 ether}(marketId, false);

        // Verify accumulated bets
        (uint256 yesAmount, uint256 noAmount) = parimutuel.getUserBets(marketId, alice);
        assertEq(yesAmount, 3 ether);
        assertEq(noAmount, 0.5 ether);
    }

    // Test resolution edge cases
    function test_ResolveBeforeDeadline() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(creator);
        vm.expectRevert("Cannot resolve before deadline");
        parimutuel.resolve(marketId, true);
    }

    function test_ResolveAlreadyResolvedMarket() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

        vm.prank(creator);
        vm.expectRevert("Market already resolved");
        parimutuel.resolve(marketId, false);
    }

    function test_ResolveNonexistentMarket() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        vm.expectRevert("Market does not exist");
        parimutuel.resolve(999, true);
    }

    // Test claiming edge cases
    function test_ClaimUnresolvedMarket() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        vm.prank(alice);
        vm.expectRevert("Market not resolved");
        parimutuel.claim(marketId);
    }

    function test_ClaimEmptyMarket() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        // No bets placed
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

        vm.prank(alice);
        vm.expectRevert("No bets to claim");
        parimutuel.claim(marketId);
    }

    // Test events
    function test_EventEmissions() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit MarketCreated(0, creator, "Test", block.timestamp + 1 days);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit BetPlaced(marketId, alice, true, 1 ether);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit MarketResolved(marketId, true);
        parimutuel.resolve(marketId, true);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Claimed(marketId, alice, 1 ether);
        parimutuel.claim(marketId);
    }

    // Pool accounting after refunds
    function test_PoolAccountingAfterRefund() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 2 ether}(marketId, true);

        vm.prank(bob);
        parimutuel.placeBet{value: 3 ether}(marketId, false);

        // Check pools before refund
        (uint256 yesPoolBefore, uint256 noPoolBefore,) = parimutuel.getMarketPools(marketId);
        assertEq(yesPoolBefore, 2 ether);
        assertEq(noPoolBefore, 3 ether);

        // Refund Alice
        vm.warp(block.timestamp + 1 days + 7 days + 1);
        vm.prank(alice);
        parimutuel.refund(marketId);

        // Pool accounting after refund - pools are not updated
        (uint256 yesPoolAfter,, uint256 totalAfter) = parimutuel.getMarketPools(marketId);

        // Current behavior: pools not updated after refunds
        assertEq(yesPoolAfter, 2 ether);  // Pool shows original amount
        assertEq(totalAfter, 5 ether);    // Total shows original sum
        assertEq(address(parimutuel).balance, 3 ether);  // Actual contract balance is different
    }

    // Events to match contract
    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint256 deadline);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool betYes, uint256 amount);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event Claimed(uint256 indexed marketId, address indexed claimer, uint256 amount);
    event Refunded(uint256 indexed marketId, address indexed refundee, uint256 amount);
}