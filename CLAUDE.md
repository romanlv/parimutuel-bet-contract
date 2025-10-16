# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Foundry-based Solidity project implementing a parimutuel betting platform smart contract system. The project allows creation of binary outcome betting markets using ETH, with trustless parimutuel-style payouts where winners split the total pool proportionally.

## Core Architecture

### Main Contracts

- **`src/ParimutuelBets.sol`** - Main betting platform contract implementing ETH-based parimutuel betting with display names, refund mechanisms, and comprehensive market management
- **`src/Counter.sol`** - Standard Foundry template contract

### Key Features

The main `ParimutuelBets` contract implements:
- ETH-based betting with binary YES/NO outcomes
- Separate resolver role (can be creator or another address)
- Proportional winner payouts using parimutuel formula
- 7-day refund mechanism if resolver fails to resolve
- Display name support for bettors
- One-sided market protection (prevents fund lockup)
- Comprehensive view functions for market data and user positions
- Pagination support for bet discovery

## Development Commands

### Building and Testing
```bash
forge build                    # Compile contracts
forge test                     # Run all tests
forge test -vv                 # Run tests with verbose output
forge test --match-test <name> # Run specific test
```

### Code Quality
```bash
forge fmt                      # Format Solidity code
forge snapshot                 # Generate gas usage snapshots
```

### Deployment and Interaction
```bash
# Deploy (replace with actual values)
forge script script/Counter.s.sol:CounterScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>

# Local blockchain for testing
anvil

# Interact with contracts
cast <subcommand>
```

### Useful Cast Commands
```bash
cast call <CONTRACT> <METHOD> <ARGS>        # Call view function
cast send <CONTRACT> <METHOD> <ARGS>        # Send transaction
cast balance <ADDRESS>                      # Check balance
cast logs <EVENT_SIGNATURE>                 # Filter logs
```

## Bet Lifecycle

1. **Creation**: `createBet()` - Creator sets question, deadline, and resolver address
2. **Betting**: `takePosition()` - Users bet YES/NO with ETH until deadline (optional display name)
3. **Resolution**: `resolve()` - Resolver resolves to YES/NO after deadline
4. **Claiming**: `claim()` - Winners claim proportional share of total pool
5. **Refunds**: `refund()` - Users can reclaim bets if resolver fails to resolve within 7 days

## Data Structures

```solidity
struct Bet {
    address creator;
    address resolver;           // Address allowed to resolve (can be creator or another address)
    string question;
    uint256 deadline;
    uint256 createdAt;
    uint256 yesTotal;
    uint256 noTotal;
    bool resolved;
    bool outcome;
}
```

## Key Mappings

- `bets[betId]` - Bet details
- `yesPositions[betId][user]` - User's YES bet amounts
- `noPositions[betId][user]` - User's NO bet amounts
- `hasClaimed[betId][user]` - Claim status tracking
- `hasRefunded[betId][user]` - Refund status tracking
- `displayNames[betId][user]` - Optional display names

## Security Features

- ReentrancyGuard on claim and refund functions
- One-sided market protection (prevents fund lockup if only one side has bets)
- Safe ETH transfers using call() instead of transfer() for smart contract wallet compatibility
- Proper access controls (only designated resolver can resolve bets)
- Time-based validation (deadline enforcement, max 365 days, refund period)
- Prevention of resolution after refunds have started
- Claim-for/refund-for functionality allowing anyone to trigger on behalf of users

## Project Documentation

The `docs/bet-contract-prd.md` file contains the complete product requirements document detailing the intended functionality, workflow, edge cases, and UI specifications for the betting platform.

## Dependencies

- OpenZeppelin contracts for ReentrancyGuard
- Foundry's forge-std for testing utilities

## Query Functions

The contract provides comprehensive query functions for frontend integration:
- `getOpenBetIds()` - Paginated list of active bets
- `getAwaitingResolutionIds()` - Bets past deadline awaiting resolution
- `getResolvedBetIds()` - Paginated list of resolved bets
- `getUserAllPositions()` - All positions for a user with state info
- `getCreatorBets()` - All bets created by an address
- `getBetWithUserData()` - Complete bet info with user-specific data
- `getBetStats()` - Comprehensive statistics for a bet