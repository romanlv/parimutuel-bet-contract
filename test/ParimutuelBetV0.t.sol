// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ParimutuelBetV0} from "../src/ParimutuelBetV0.sol";

contract ParimutuelBetV0Test is Test {
    ParimutuelBetV0 public parimutuel;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public creator = makeAddr("creator");

    uint256 constant INITIAL_BALANCE = 10 ether;

    function setUp() public {
        parimutuel = new ParimutuelBetV0();

        // Fund all participants
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(creator, INITIAL_BALANCE);
    }

    function test_BasicBettingScenario() public {
        // Creator creates a bet
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Alice takes position 2 ETH on YES
        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true);

        // Bob takes position 3 ETH on NO
        vm.prank(bob);
        parimutuel.takePosition{value: 3 ether}(betId, false);

        // Charlie takes position 1 ETH on YES
        vm.prank(charlie);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Verify total states and user positions using new struct interface
        ParimutuelBetV0.BetWithUserData memory aliceData = parimutuel.getBetWithUserData(betId, alice);

        assertEq(aliceData.bet.yesTotal, 3 ether); // Alice (2) + Charlie (1)
        assertEq(aliceData.bet.noTotal, 3 ether); // Bob (3)
        assertEq(aliceData.userYesPosition, 2 ether);
        assertEq(aliceData.userNoPosition, 0);

        ParimutuelBetV0.BetWithUserData memory bobData = parimutuel.getBetWithUserData(betId, bob);
        assertEq(bobData.userYesPosition, 0);
        assertEq(bobData.userNoPosition, 3 ether);

        ParimutuelBetV0.BetWithUserData memory charlieData = parimutuel.getBetWithUserData(betId, charlie);
        assertEq(charlieData.userYesPosition, 1 ether);
        assertEq(charlieData.userNoPosition, 0);

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Creator resolves to YES (Alice and Charlie win)
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        // Calculate expected payouts
        // Total pot: 6 ETH
        // YES pool: 3 ETH (Alice 2 + Charlie 1)
        // Alice should get: (2/3) * 6 = 4 ETH
        // Charlie should get: (1/3) * 6 = 2 ETH

        uint256 aliceInitialBalance = alice.balance;
        uint256 charlieInitialBalance = charlie.balance;
        uint256 bobInitialBalance = bob.balance;

        // Alice claims her winnings
        vm.prank(alice);
        parimutuel.claim(betId, address(0));

        // Charlie claims his winnings
        vm.prank(charlie);
        parimutuel.claim(betId, address(0));

        // Verify payouts
        assertEq(alice.balance, aliceInitialBalance + 4 ether);
        assertEq(charlie.balance, charlieInitialBalance + 2 ether);

        // Bob (loser) should not be able to claim
        vm.prank(bob);
        vm.expectRevert("No winning position to claim");
        parimutuel.claim(betId, address(0));

        // Bob's balance should remain unchanged
        assertEq(bob.balance, bobInitialBalance);

        // Verify claim status
        assertTrue(parimutuel.hasClaimed(betId, alice));
        assertTrue(parimutuel.hasClaimed(betId, charlie));
        assertFalse(parimutuel.hasClaimed(betId, bob));
    }

    function test_NOWinsScenario() public {
        // Creator creates a market
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it snow tomorrow?", block.timestamp + 1 days, creator);

        // Alice bets 1 ETH on YES
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Bob bets 2 ETH on NO
        vm.prank(bob);
        parimutuel.takePosition{value: 2 ether}(betId, false);

        // Charlie bets 3 ETH on NO
        vm.prank(charlie);
        parimutuel.takePosition{value: 3 ether}(betId, false);

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Creator resolves to NO (Bob and Charlie win)
        vm.prank(creator);
        parimutuel.resolve(betId, false);

        // Calculate expected payouts
        // Total pot: 6 ETH
        // NO pool: 5 ETH (Bob 2 + Charlie 3)
        // Bob should get: (2/5) * 6 = 2.4 ETH
        // Charlie should get: (3/5) * 6 = 3.6 ETH

        uint256 bobInitialBalance = bob.balance;
        uint256 charlieInitialBalance = charlie.balance;

        // Bob and Charlie claim their winnings
        vm.prank(bob);
        parimutuel.claim(betId, address(0));

        vm.prank(charlie);
        parimutuel.claim(betId, address(0));

        // Verify payouts
        assertEq(bob.balance, bobInitialBalance + 2.4 ether);
        assertEq(charlie.balance, charlieInitialBalance + 3.6 ether);

        // Alice (loser) should not be able to claim
        vm.prank(alice);
        vm.expectRevert("No winning position to claim");
        parimutuel.claim(betId, address(0));
    }

    function test_DoubleClaimPrevention() public {
        // Setup market and bets
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test question", block.timestamp + 1 days, creator);

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true);

        // Resolve and claim
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        vm.prank(alice);
        parimutuel.claim(betId, address(0));

        // Try to claim again - should fail
        vm.prank(alice);
        vm.expectRevert("Already claimed");
        parimutuel.claim(betId, address(0));
    }

    function test_CannotBetAfterDeadline() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test question", block.timestamp + 1 days, creator);

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Try to bet - should fail
        vm.prank(alice);
        vm.expectRevert("Betting period has ended");
        parimutuel.takePosition{value: 1 ether}(betId, true);
    }

    function test_OnlyCreatorCanResolve() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Test question", block.timestamp + 1 days, creator);

        vm.warp(block.timestamp + 1 days + 1);

        // Alice tries to resolve - should fail
        vm.prank(alice);
        vm.expectRevert("Only resolver can resolve");
        parimutuel.resolve(betId, true);

        // Creator can resolve - should succeed
        vm.prank(creator);
        parimutuel.resolve(betId, true);
    }
}
