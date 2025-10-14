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
        // Creator creates a market
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Will it rain tomorrow?", block.timestamp + 1 days);

        // Alice bets 2 ETH on YES
        vm.prank(alice);
        parimutuel.placeBet{value: 2 ether}(marketId, true);

        // Bob bets 3 ETH on NO
        vm.prank(bob);
        parimutuel.placeBet{value: 3 ether}(marketId, false);

        // Charlie bets 1 ETH on YES
        vm.prank(charlie);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        // Verify pool states and user bets using new struct interface
        ParimutuelBetV0.MarketWithUserData memory aliceData = parimutuel.getMarketWithUserData(marketId, alice);

        assertEq(aliceData.market.yesPool, 3 ether); // Alice (2) + Charlie (1)
        assertEq(aliceData.market.noPool, 3 ether); // Bob (3)
        assertEq(aliceData.userYesBet, 2 ether);
        assertEq(aliceData.userNoBet, 0);

        ParimutuelBetV0.MarketWithUserData memory bobData = parimutuel.getMarketWithUserData(marketId, bob);
        assertEq(bobData.userYesBet, 0);
        assertEq(bobData.userNoBet, 3 ether);

        ParimutuelBetV0.MarketWithUserData memory charlieData = parimutuel.getMarketWithUserData(marketId, charlie);
        assertEq(charlieData.userYesBet, 1 ether);
        assertEq(charlieData.userNoBet, 0);

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Creator resolves to YES (Alice and Charlie win)
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

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
        parimutuel.claim(marketId, address(0));

        // Charlie claims his winnings
        vm.prank(charlie);
        parimutuel.claim(marketId, address(0));

        // Verify payouts
        assertEq(alice.balance, aliceInitialBalance + 4 ether);
        assertEq(charlie.balance, charlieInitialBalance + 2 ether);

        // Bob (loser) should not be able to claim
        vm.prank(bob);
        vm.expectRevert("No winning bet to claim");
        parimutuel.claim(marketId, address(0));

        // Bob's balance should remain unchanged
        assertEq(bob.balance, bobInitialBalance);

        // Verify claim status
        assertTrue(parimutuel.hasClaimed(marketId, alice));
        assertTrue(parimutuel.hasClaimed(marketId, charlie));
        assertFalse(parimutuel.hasClaimed(marketId, bob));
    }

    function test_NOWinsScenario() public {
        // Creator creates a market
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Will it snow tomorrow?", block.timestamp + 1 days);

        // Alice bets 1 ETH on YES
        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        // Bob bets 2 ETH on NO
        vm.prank(bob);
        parimutuel.placeBet{value: 2 ether}(marketId, false);

        // Charlie bets 3 ETH on NO
        vm.prank(charlie);
        parimutuel.placeBet{value: 3 ether}(marketId, false);

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Creator resolves to NO (Bob and Charlie win)
        vm.prank(creator);
        parimutuel.resolve(marketId, false);

        // Calculate expected payouts
        // Total pot: 6 ETH
        // NO pool: 5 ETH (Bob 2 + Charlie 3)
        // Bob should get: (2/5) * 6 = 2.4 ETH
        // Charlie should get: (3/5) * 6 = 3.6 ETH

        uint256 bobInitialBalance = bob.balance;
        uint256 charlieInitialBalance = charlie.balance;

        // Bob and Charlie claim their winnings
        vm.prank(bob);
        parimutuel.claim(marketId, address(0));

        vm.prank(charlie);
        parimutuel.claim(marketId, address(0));

        // Verify payouts
        assertEq(bob.balance, bobInitialBalance + 2.4 ether);
        assertEq(charlie.balance, charlieInitialBalance + 3.6 ether);

        // Alice (loser) should not be able to claim
        vm.prank(alice);
        vm.expectRevert("No winning bet to claim");
        parimutuel.claim(marketId, address(0));
    }

    function test_DoubleClaimPrevention() public {
        // Setup market and bets
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test question", block.timestamp + 1 days);

        vm.prank(alice);
        parimutuel.placeBet{value: 1 ether}(marketId, true);

        // Resolve and claim
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(marketId, true);

        vm.prank(alice);
        parimutuel.claim(marketId, address(0));

        // Try to claim again - should fail
        vm.prank(alice);
        vm.expectRevert("Already claimed");
        parimutuel.claim(marketId, address(0));
    }

    function test_CannotBetAfterDeadline() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test question", block.timestamp + 1 days);

        // Move past deadline
        vm.warp(block.timestamp + 1 days + 1);

        // Try to bet - should fail
        vm.prank(alice);
        vm.expectRevert("Betting period has ended");
        parimutuel.placeBet{value: 1 ether}(marketId, true);
    }

    function test_OnlyCreatorCanResolve() public {
        vm.prank(creator);
        uint256 marketId = parimutuel.createMarket("Test question", block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days + 1);

        // Alice tries to resolve - should fail
        vm.prank(alice);
        vm.expectRevert("Only creator can resolve");
        parimutuel.resolve(marketId, true);

        // Creator can resolve - should succeed
        vm.prank(creator);
        parimutuel.resolve(marketId, true);
    }
}
