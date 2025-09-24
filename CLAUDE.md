# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Foundry-based Solidity project implementing a parimutuel betting platform smart contract system. The project allows creation of binary outcome betting markets using any ERC20 token, with trustless parimutuel-style payouts where winners split the total pool proportionally.

## Core Architecture

### Main Contracts

- **`src/ParimutuelBet.sol`** - Main production contract implementing the full betting platform with ERC20 token support, creator fees, refund mechanisms, and comprehensive market management
- **`src/ParimutuelBetV0.sol`** - Simple initial version using ETH only (for reference/testing)
- **`src/Counter.sol`** - Standard Foundry template contract

### Key Features

The main `ParimutuelBet` contract implements:
- Token-agnostic betting (any ERC20 per market)
- Creator-controlled market resolution with optional delays
- Proportional winner payouts with configurable creator fees (0-10%)
- 7-day refund mechanism if creators fail to resolve
- Token whitelist support (optional)
- Comprehensive view functions for market data and user positions

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

## Market Lifecycle

1. **Creation**: `createMarket()` - Creator sets token, question, deadline, resolution delay, and fee
2. **Betting**: `placeBet()` - Users bet YES/NO with specified ERC20 token until deadline
3. **Resolution**: `resolve()` - Creator resolves to YES/NO after deadline (and optional delay)
4. **Claiming**: `claim()` - Winners claim proportional share of total pool minus creator fee
5. **Refunds**: `refund()` - Users can reclaim bets if creator fails to resolve within 7 days

## Data Structures

```solidity
struct Market {
    address creator;
    address token;              // ERC20 token for this market
    string question;
    string description;
    uint256 deadline;
    uint256 resolveAfter;       // Optional minimum resolution time
    uint16 creatorFeePercentage; // 0-1000 (0-10%)
    uint256 yesPool;
    uint256 noPool;
    uint256 resolvedAt;
    bool resolved;
    bool outcome;
    bool cancelled;
    bool creatorFeeClaimed;
}
```

## Key Mappings

- `markets[marketId]` - Market details
- `yesBets[marketId][user]` - User's YES bet amounts
- `noBets[marketId][user]` - User's NO bet amounts
- `hasClaimed[marketId][user]` - Claim status tracking

## Security Features

- ReentrancyGuard on betting and claiming functions
- Creator fee capped at 10% (MAX_CREATOR_FEE = 1000 basis points)
- Safe ERC20 transfer checks with fallback token metadata handling
- Proper access controls (only creator can resolve their markets)
- Time-based validation (deadline enforcement, resolution delays)

## Project Documentation

The `docs/bet-contract-prd.md` file contains the complete product requirements document detailing the intended functionality, workflow, edge cases, and UI specifications for the betting platform.

## Dependencies

- OpenZeppelin contracts for ERC20 interface and ReentrancyGuard
- Foundry's forge-std for testing utilities