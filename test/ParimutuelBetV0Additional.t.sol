// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ParimutuelBetV0} from "../src/ParimutuelBetV0.sol";

contract ParimutuelBetV0AdditionalTest is Test {
    ParimutuelBetV0 public parimutuel;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public creator = makeAddr("creator");

    uint256 constant INITIAL_BALANCE = 10 ether;

    function setUp() public {
        parimutuel = new ParimutuelBetV0();
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(creator, INITIAL_BALANCE);
    }

    // Test refund functionality
    function test_RefundAfterDeadline() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Place bets
        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(bob);
        parimutuel.takePosition{value: 3 ether}(betId, false);

        // Move past deadline + refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        // Test refund
        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        vm.prank(bob);
        parimutuel.refund(betId, address(0));

        // Verify refunds
        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertEq(bob.balance, bobBalanceBefore + 3 ether);
    }

    function test_CannotRefundTwice() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 7 days + 1);

        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        vm.prank(alice);
        vm.expectRevert("Already refunded");
        parimutuel.refund(betId, address(0));
    }

    function test_RefundBeforeRefundPeriod() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Only move past deadline, not refund period
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(alice);
        vm.expectRevert("Refund period not reached");
        parimutuel.refund(betId, address(0));
    }

    function test_RefundAfterResolution() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Resolve before refund period
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Move past refund period
        vm.warp(block.timestamp + 7 days);

        vm.prank(alice);
        vm.expectRevert("Bet already resolved");
        parimutuel.refund(betId, address(0));
    }

    // Test single-sided betting scenarios
    function test_OnlyYesBets() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Only YES bets
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 1);

        // Resolve to YES (Alice wins, no NO bets to split with)
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Alice should get full pot since she's the only bettor
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        parimutuel.claim(betId, address(0));

        assertEq(alice.balance, balanceBefore + 1 ether);
    }

    function test_OnlyNoBets() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Only NO bets
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, false);

        vm.warp(block.timestamp + 1 days + 1);

        // Resolve to NO (Alice wins, no YES bets to split with)
        vm.prank(creator);
        parimutuel.resolve(betId, false);

        // Alice should get full pot since she's the only bettor
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        parimutuel.claim(betId, address(0));

        assertEq(alice.balance, balanceBefore + 1 ether);
    }

    // Test market creation edge cases
    function test_CreateMarketWithPastDeadline() public {
        vm.prank(creator);
        vm.expectRevert("Deadline must be in future");
        parimutuel.createBet("Test", block.timestamp - 1);
    }

    function test_CreateMarketWithCurrentTimestamp() public {
        vm.prank(creator);
        vm.expectRevert("Deadline must be in future");
        parimutuel.createBet("Test", block.timestamp);
    }

    // Test betting edge cases
    function test_ZeroBetReverts() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectRevert("Amount must be greater than 0");
        parimutuel.takePosition{value: 0}(betId, true);
    }

    function test_BetOnNonexistentMarket() public {
        vm.prank(alice);
        vm.expectRevert("Bet does not exist");
        parimutuel.takePosition{value: 1 ether}(999, true);
    }

    function test_BetAfterDeadlinePrecedesResolvedCheck() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Move past deadline and resolve
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Try to bet - deadline check comes before resolved check
        vm.prank(bob);
        vm.expectRevert("Betting period has ended");
        parimutuel.takePosition{value: 1 ether}(betId, false);
    }

    // Test multiple bets by same user
    function test_MultipleBetsBySameUser() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Alice makes multiple YES bets
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        // Alice also makes a NO bet
        vm.prank(alice);
        parimutuel.takePosition{value: 0.5 ether}(betId, false);

        // Verify accumulated bets
        ParimutuelBetV0.BetWithUserData memory aliceData = parimutuel.getBetWithUserData(betId, alice);
        assertEq(aliceData.userYesPosition, 3 ether);
        assertEq(aliceData.userNoPosition, 0.5 ether);
    }

    // Test resolution edge cases
    function test_ResolveBeforeDeadline() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(creator);
        vm.expectRevert("Cannot resolve before deadline");
        parimutuel.resolve(betId, true);
    }

    function test_ResolveAlreadyResolvedMarket() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        vm.prank(creator);
        vm.expectRevert("Bet already resolved");
        parimutuel.resolve(betId, false);
    }

    function test_ResolveNonexistentMarket() public {
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        vm.expectRevert("Bet does not exist");
        parimutuel.resolve(999, true);
    }

    // Test claiming edge cases
    function test_ClaimUnresolvedMarket() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.prank(alice);
        vm.expectRevert("Bet not resolved");
        parimutuel.claim(betId, address(0));
    }

    function test_ClaimEmptyMarket() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // No bets placed
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        vm.prank(alice);
        vm.expectRevert("No winning position to claim");
        parimutuel.claim(betId, address(0));
    }

    // Test events
    function test_EventEmissions() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit BetCreated(0, creator, "Test", block.timestamp + 1 days);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit PositionTaken(betId, alice, true, 1 ether, 1 ether, 0);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit BetResolved(betId, true, 1 ether, 0);
        parimutuel.resolve(betId, true);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Claimed(betId, alice, 1 ether, alice);
        parimutuel.claim(betId, address(0));
    }

    // Pool accounting after refunds
    function test_PoolAccountingAfterRefund() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(bob);
        parimutuel.takePosition{value: 3 ether}(betId, false);

        // Check pools before refund
        ParimutuelBetV0.BetWithUserData memory dataBefore = parimutuel.getBetWithUserData(betId, address(0));
        uint256 yesTotalBefore = dataBefore.bet.yesTotal;
        uint256 noTotalBefore = dataBefore.bet.noTotal;
        assertEq(yesTotalBefore, 2 ether);
        assertEq(noTotalBefore, 3 ether);

        // Refund Alice
        vm.warp(block.timestamp + 1 days + 7 days + 1);
        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        // Pool accounting after refund - pools are not updated
        ParimutuelBetV0.BetWithUserData memory dataAfter = parimutuel.getBetWithUserData(betId, address(0));
        uint256 yesTotalAfter = dataAfter.bet.yesTotal;
        uint256 totalAfter = dataAfter.bet.yesTotal + dataAfter.bet.noTotal;

        // Current behavior: pools not updated after refunds
        assertEq(yesTotalAfter, 2 ether); // Pool shows original amount
        assertEq(totalAfter, 5 ether); // Total shows original sum
        assertEq(address(parimutuel).balance, 3 ether); // Actual contract balance is different
    }

    // Test new query functions
    function test_GetUserRefundable() public {
        // Create market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Place bets
        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, false);

        // Move past deadline + refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Check refundable
        ParimutuelBetV0.UserPosition memory refundable = parimutuel.getUserRefundable(alice);

        assertEq(refundable.betIds.length, 1);
        assertEq(refundable.betIds[0], betId);
        assertEq(refundable.amounts[0], 3 ether); // 2 + 1

        // After refund, should be empty
        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        refundable = parimutuel.getUserRefundable(alice);
        assertEq(refundable.betIds.length, 0);
    }

    function test_GetAwaitingResolutionIds() public {
        // Create multiple markets
        vm.prank(creator);
        uint256 market1 = parimutuel.createBet("Market 1", block.timestamp + 1 days);

        vm.prank(creator);
        uint256 market2 = parimutuel.createBet("Market 2", block.timestamp + 2 days);

        vm.prank(creator);
        uint256 market3 = parimutuel.createBet("Market 3", block.timestamp + 3 days);

        // Move past first deadline
        vm.warp(block.timestamp + 1 days + 1);

        ParimutuelBetV0.PaginatedBetIds memory result = parimutuel.getAwaitingResolutionIds(0, 10);
        assertEq(result.ids.length, 1);
        assertEq(result.ids[0], market1);
        assertFalse(result.hasMore);

        // Move past second deadline
        vm.warp(block.timestamp + 1 days);

        result = parimutuel.getAwaitingResolutionIds(0, 10);
        assertEq(result.ids.length, 2);
        assertEq(result.ids[0], market1);
        assertEq(result.ids[1], market2);
        assertFalse(result.hasMore);

        // Resolve market1
        vm.prank(creator);
        parimutuel.resolve(market1, true);

        result = parimutuel.getAwaitingResolutionIds(0, 10);
        assertEq(result.ids.length, 1);
        assertEq(result.ids[0], market2);
    }

    function test_MarketCreatedAtTimestamp() public {
        uint256 creationTime = block.timestamp;

        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        ParimutuelBetV0.BetWithUserData memory data = parimutuel.getBetWithUserData(betId, address(0));
        assertEq(data.bet.createdAt, creationTime);
    }

    function test_GetAwaitingResolutionPagination() public {
        // Create 5 markets that will need resolution
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(creator);
            parimutuel.createBet(string(abi.encodePacked("Market ", i)), block.timestamp + 1 days);
        }

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Test pagination with limit 2
        ParimutuelBetV0.PaginatedBetIds memory result = parimutuel.getAwaitingResolutionIds(0, 2);
        assertEq(result.ids.length, 2);
        assertTrue(result.hasMore);

        // Get next page
        result = parimutuel.getAwaitingResolutionIds(2, 2);
        assertEq(result.ids.length, 2);
        assertTrue(result.hasMore);

        // Get last page
        result = parimutuel.getAwaitingResolutionIds(4, 2);
        assertEq(result.ids.length, 1);
        assertFalse(result.hasMore);
    }

    // ============================================
    // SECURITY FIX TESTS
    // ============================================

    // Test that resolve fails after any refunds have been claimed
    function test_CannotResolveAfterRefunds() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(bob);
        parimutuel.takePosition{value: 3 ether}(betId, false);

        // Move past deadline + refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Alice refunds
        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        // Now creator tries to resolve - should fail
        vm.prank(creator);
        vm.expectRevert("Cannot resolve after refunds have been claimed");
        parimutuel.resolve(betId, true);
    }

    function test_CannotResolveAfterPartialRefunds() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(bob);
        parimutuel.takePosition{value: 3 ether}(betId, false);

        // Move past deadline + refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Only alice refunds
        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        // Creator tries to resolve - should fail even if only partial refunds
        vm.prank(creator);
        vm.expectRevert("Cannot resolve after refunds have been claimed");
        parimutuel.resolve(betId, true);
    }

    // Test that ETH transfers work with call() instead of transfer()
    // This would test smart contract wallets that need more than 2300 gas
    function test_ClaimWorksWithHighGasRecipient() public {
        // Deploy a contract that consumes more gas in receive
        HighGasReceiver receiver = new HighGasReceiver();
        vm.deal(address(receiver), INITIAL_BALANCE);

        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Receiver contract places bet
        vm.prank(address(receiver));
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Receiver should be able to claim (would fail with transfer())
        uint256 balanceBefore = address(receiver).balance;
        vm.prank(address(receiver));
        parimutuel.claim(betId, address(0));

        assertEq(address(receiver).balance, balanceBefore + 1 ether);
    }

    function test_RefundWorksWithHighGasRecipient() public {
        HighGasReceiver receiver = new HighGasReceiver();
        vm.deal(address(receiver), INITIAL_BALANCE);

        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(address(receiver));
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 7 days + 1);

        uint256 balanceBefore = address(receiver).balance;
        vm.prank(address(receiver));
        parimutuel.refund(betId, address(0));

        assertEq(address(receiver).balance, balanceBefore + 1 ether);
    }

    // Events to match contract
    event BetCreated(uint256 indexed betId, address indexed creator, string question, uint256 deadline);
    event PositionTaken(
        uint256 indexed betId, address indexed user, bool isYes, uint256 amount, uint256 yesTotal, uint256 noTotal
    );
    event BetResolved(uint256 indexed betId, bool outcome, uint256 yesTotal, uint256 noTotal);
    event Claimed(uint256 indexed betId, address indexed user, uint256 amount, address indexed triggeredBy);
    event Refunded(uint256 indexed betId, address indexed user, uint256 amount, address indexed triggeredBy);

    // ============================================
    // CLAIM FOR / REFUND FOR TESTS
    // ============================================

    function test_ClaimForAnotherUser() public {
        // Setup market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Alice bets
        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        // Resolve
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Bob claims on behalf of Alice
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(bob);
        parimutuel.claim(betId, alice);

        // Verify Alice received the funds (not Bob)
        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertTrue(parimutuel.hasClaimed(betId, alice));
    }

    function test_ClaimForEmitsCorrectEvent() public {
        // Setup and resolve market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Bob claims for Alice - event should show Alice as claimer, Bob as triggerer
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Claimed(betId, alice, 1 ether, bob);
        parimutuel.claim(betId, alice);
    }

    function test_ClaimForSelfWithAddressZero() public {
        // Setup and resolve market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Alice claims with address(0), should default to msg.sender
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        parimutuel.claim(betId, address(0));

        assertEq(alice.balance, aliceBalanceBefore + 1 ether);
        assertTrue(parimutuel.hasClaimed(betId, alice));
    }

    function test_CannotClaimForSameUserTwice() public {
        // Setup and resolve market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Bob claims for Alice
        vm.prank(bob);
        parimutuel.claim(betId, alice);

        // Try to claim again - should fail
        vm.prank(bob);
        vm.expectRevert("Already claimed");
        parimutuel.claim(betId, alice);

        // Alice also cannot claim for herself
        vm.prank(alice);
        vm.expectRevert("Already claimed");
        parimutuel.claim(betId, address(0));
    }

    function test_RefundForAnotherUser() public {
        // Setup market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        // Alice and Bob bet
        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(bob);
        parimutuel.takePosition{value: 1 ether}(betId, false);

        // Move past refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Charlie triggers refund for Alice
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(charlie);
        parimutuel.refund(betId, alice);

        // Verify Alice received the refund (not Charlie)
        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertTrue(parimutuel.hasRefunded(betId, alice));
        assertFalse(parimutuel.hasRefunded(betId, charlie));
    }

    function test_RefundForEmitsCorrectEvent() public {
        // Setup market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 3 ether}(betId, true);

        // Move past refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Bob triggers refund for Alice - event should show Alice as refundee, Bob as triggerer
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Refunded(betId, alice, 3 ether, bob);
        parimutuel.refund(betId, alice);
    }

    function test_RefundForSelfWithAddressZero() public {
        // Setup market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        // Move past refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Alice refunds with address(0), should default to msg.sender
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        parimutuel.refund(betId, address(0));

        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertTrue(parimutuel.hasRefunded(betId, alice));
    }

    function test_CannotRefundForSameUserTwice() public {
        // Setup market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        // Move past refund period
        vm.warp(block.timestamp + 1 days + 7 days + 1);

        // Bob triggers refund for Alice
        vm.prank(bob);
        parimutuel.refund(betId, alice);

        // Try to refund again - should fail
        vm.prank(bob);
        vm.expectRevert("Already refunded");
        parimutuel.refund(betId, alice);

        // Alice also cannot refund for herself
        vm.prank(alice);
        vm.expectRevert("Already refunded");
        parimutuel.refund(betId, address(0));
    }

    function test_MultipleUsersCanClaimForDifferentBeneficiaries() public {
        // Setup market with multiple winners
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        vm.prank(bob);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Resolve
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Charlie helps both Alice and Bob claim
        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(charlie);
        parimutuel.claim(betId, alice);

        vm.prank(charlie);
        parimutuel.claim(betId, bob);

        // Verify both received their payouts
        assertEq(alice.balance, aliceBalanceBefore + 2 ether);
        assertEq(bob.balance, bobBalanceBefore + 1 ether);
        assertTrue(parimutuel.hasClaimed(betId, alice));
        assertTrue(parimutuel.hasClaimed(betId, bob));
    }
}

// Helper contract for testing call() vs transfer()
contract HighGasReceiver {
    uint256 public counter;

    receive() external payable {
        // Consume more than 2300 gas (would fail with transfer())
        for (uint256 i = 0; i < 10; i++) {
            counter += i;
        }
    }
}
