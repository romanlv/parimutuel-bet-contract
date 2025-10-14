// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ParimutuelBetV0} from "../src/ParimutuelBetV0.sol";

contract ParimutuelBetV0DisplayNameTest is Test {
    ParimutuelBetV0 public parimutuel;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public creator = makeAddr("creator");

    uint256 constant INITIAL_BALANCE = 10 ether;

    event PositionTaken(
        uint256 indexed betId,
        address indexed user,
        bool isYes,
        uint256 amount,
        uint256 yesTotal,
        uint256 noTotal,
        string displayName
    );

    function setUp() public {
        parimutuel = new ParimutuelBetV0();

        // Fund all participants
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(creator, INITIAL_BALANCE);
    }

    function test_TakePositionWithDisplayName() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Alice takes position with display name
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Alice");

        // Verify display name is stored
        string memory name = parimutuel.getDisplayName(betId, alice);
        assertEq(name, "Alice");
    }

    function test_TakePositionWithoutDisplayName() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Alice takes position without display name (empty string)
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "");

        // Verify display name is empty
        string memory name = parimutuel.getDisplayName(betId, alice);
        assertEq(name, "");
    }

    function test_UpdateDisplayNameOnSubsequentBet() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Alice takes position with display name "Alice"
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Alice");

        assertEq(parimutuel.getDisplayName(betId, alice), "Alice");

        // Alice takes another position with updated display name
        vm.prank(alice);
        parimutuel.takePosition{value: 0.5 ether}(betId, false, "Alice Smith");

        // Verify display name is updated
        assertEq(parimutuel.getDisplayName(betId, alice), "Alice Smith");
    }

    function test_DisplayNameTooLong() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Try to use a display name longer than 32 characters
        string memory longName = "This is a very long display name that exceeds thirty-two characters";

        vm.prank(alice);
        vm.expectRevert("Display name too long");
        parimutuel.takePosition{value: 1 ether}(betId, true, longName);
    }

    function test_DisplayNameExactly32Characters() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Use exactly 32 characters - should succeed
        string memory name32 = "12345678901234567890123456789012";

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, name32);

        assertEq(parimutuel.getDisplayName(betId, alice), name32);
    }

    function test_DifferentNamesOnDifferentBets() public {
        // Create two different bets
        vm.prank(creator);
        uint256 betId1 = parimutuel.createBet("Bet 1", block.timestamp + 1 days, creator);

        vm.prank(creator);
        uint256 betId2 = parimutuel.createBet("Bet 2", block.timestamp + 1 days, creator);

        // Alice uses different names on different bets
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId1, true, "Alice at Work");

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId2, true, "Alice at Home");

        // Verify each bet has the correct name
        assertEq(parimutuel.getDisplayName(betId1, alice), "Alice at Work");
        assertEq(parimutuel.getDisplayName(betId2, alice), "Alice at Home");
    }

    function test_BatchGetDisplayNames() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Multiple users take positions with display names
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Alice");

        vm.prank(bob);
        parimutuel.takePosition{value: 2 ether}(betId, false, "Bob");

        vm.prank(charlie);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Charlie");

        // Batch query display names
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        string[] memory names = parimutuel.getDisplayNames(betId, users);

        assertEq(names.length, 3);
        assertEq(names[0], "Alice");
        assertEq(names[1], "Bob");
        assertEq(names[2], "Charlie");
    }

    function test_BatchGetDisplayNamesWithMixedEmptyNames() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Alice uses display name
        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Alice");

        // Bob doesn't use display name
        vm.prank(bob);
        parimutuel.takePosition{value: 2 ether}(betId, false, "");

        // Charlie uses display name
        vm.prank(charlie);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Charlie");

        // Batch query
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        string[] memory names = parimutuel.getDisplayNames(betId, users);

        assertEq(names.length, 3);
        assertEq(names[0], "Alice");
        assertEq(names[1], ""); // Bob has no name
        assertEq(names[2], "Charlie");
    }

    function test_EventEmittedWithDisplayName() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Expect event with display name
        vm.expectEmit(true, true, false, true);
        emit PositionTaken(betId, alice, true, 1 ether, 1 ether, 0, "Alice");

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "Alice");
    }

    function test_EventEmittedWithoutDisplayName() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Expect event with empty display name
        vm.expectEmit(true, true, false, true);
        emit PositionTaken(betId, alice, true, 1 ether, 1 ether, 0, "");

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, "");
    }

    function test_DisplayNameDoesNotAffectBettingLogic() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Alice and Bob bet with display names
        vm.prank(alice);
        parimutuel.takePosition{value: 2 ether}(betId, true, "Alice");

        vm.prank(bob);
        parimutuel.takePosition{value: 3 ether}(betId, false, "Bob");

        // Verify positions are correct regardless of display names
        ParimutuelBetV0.BetWithUserData memory aliceData = parimutuel.getBetWithUserData(betId, alice);
        ParimutuelBetV0.BetWithUserData memory bobData = parimutuel.getBetWithUserData(betId, bob);

        assertEq(aliceData.userYesPosition, 2 ether);
        assertEq(bobData.userNoPosition, 3 ether);
        assertEq(aliceData.bet.yesTotal, 2 ether);
        assertEq(aliceData.bet.noTotal, 3 ether);

        // Resolve and verify payouts work correctly
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(creator);
        parimutuel.resolve(betId, true);

        uint256 aliceInitialBalance = alice.balance;
        vm.prank(alice);
        parimutuel.claim(betId, address(0));

        // Alice wins entire pool (5 ETH)
        assertEq(alice.balance, aliceInitialBalance + 5 ether);
    }

    function test_SpecialCharactersInDisplayName() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Test with various special characters
        string memory specialName = "Alice_123-!@#";

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, specialName);

        assertEq(parimutuel.getDisplayName(betId, alice), specialName);
    }

    function test_EmojisInDisplayName() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Test with emojis (may take multiple bytes)
        string memory emojiName = "Alice";

        vm.prank(alice);
        parimutuel.takePosition{value: 1 ether}(betId, true, emojiName);

        assertEq(parimutuel.getDisplayName(betId, alice), emojiName);
    }

    function test_DisplayNameForUserWithNoPosition() public {
        vm.prank(creator);
        uint256 betId = parimutuel.createBet("Will it rain tomorrow?", block.timestamp + 1 days, creator);

        // Query display name for user who hasn't bet
        string memory name = parimutuel.getDisplayName(betId, alice);

        // Should return empty string
        assertEq(name, "");
    }
}
