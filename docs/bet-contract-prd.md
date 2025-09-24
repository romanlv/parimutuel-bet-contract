# PRD: Parimutuel Betting Platform - Smart Contract

## Intent
Create a simple, trustless betting protocol where anyone can create binary outcome markets using any ERC20 token, with parimutuel-style payouts where winners split the total pool proportionally.

## Core Principles
- **Token Agnostic**: Any ERC20 can be used per market
- **No Liquidity Required**: Users are the liquidity
- **Creator Controlled**: Market creator resolves outcome
- **Fair Distribution**: Winners split total pool proportionally to their stake

## Ideal Workflow

### Market Creation
1. Creator specifies:
   - ERC20 token address for denominating bets
   - Question/proposition text
   - Description with resolution criteria
   - Betting deadline (when betting stops)
   - Resolution time (optional minimum time before resolution allowed)
   - Creator fee (0-10% of losing pool)
2. Market goes live immediately, no upfront capital needed

### Betting Phase
1. Users choose YES or NO position
2. Send any amount of the market's token
3. Odds update dynamically as pool ratio changes
4. Users can bet multiple times, amounts accumulate
5. Betting closes at deadline

### Resolution Phase
1. After deadline (and optional resolution delay), creator resolves to YES or NO
2. Creator fee automatically deducted from losing pool
3. Winners can claim their proportional share of remaining pool
4. If creator fails to resolve within 7 days, users can reclaim their bets

## Contract Requirements

### Core Functions

#### `createMarket()`
- **Inputs**: token, question, description, deadline, resolveAfter, creatorFeePercentage
- **Validation**: 
  - Deadline must be future
  - Resolution time >= deadline (if set)
  - Fee <= 10%
- **Returns**: marketId
- **Events**: MarketCreated

#### `placeBet()`
- **Inputs**: marketId, side (YES/NO), amount
- **Validation**:
  - Before deadline
  - Market not cancelled/resolved
  - Valid token transfer
- **Effects**: Update pool totals and user position
- **Events**: BetPlaced

#### `resolve()`
- **Inputs**: marketId, outcome (YES/NO)
- **Access**: Creator only
- **Validation**:
  - After deadline
  - After resolution delay (if set)
  - Not already resolved
- **Events**: MarketResolved

#### `claim()`
- **Inputs**: marketId
- **Validation**: 
  - Market resolved
  - User hasn't claimed
  - User has winning position
- **Calculation**: 
  ```
  payout = (user_stake / winning_pool) * (total_pool - creator_fee)
  ```
- **Events**: WinningsClaimed

#### `cancel()`
- **Access**: Creator only
- **Validation**: No bets placed yet
- **Events**: MarketCancelled

#### `refund()`
- **Validation**: any time past deadline with no resolution
- **Effects**: Return original bet amounts to users

### View Functions

#### `getMarketDetails()`
Returns:
- All market parameters
- Current pool sizes
- Current odds (as percentages)
- Token symbol and decimals
- Resolution status

#### `getUserPosition()`
Returns:
- User's YES amount
- User's NO amount
- Potential payout at current odds
- Claim status

#### `getActiveMarkets()`
Returns array of active market IDs with pagination

#### `calculatePotentialPayout()`
Given a hypothetical bet, returns potential winnings

### Data Structures

```solidity
struct Market {
    address creator;
    address token;
    string question;
    string description;
    uint256 deadline;
    uint256 resolveAfter;
    uint16 creatorFeePercentage;
    uint256 yesPool;
    uint256 noPool;
    uint256 resolvedAt;
    bool resolved;
    bool outcome;
    bool cancelled;
    bool creatorFeeClaimed;
}
```

### Storage Mappings
- `markets`: marketId → Market struct
- `yesBets`: marketId → user → amount
- `noBets`: marketId → user → amount  
- `hasClaimed`: marketId → user → bool

## Security Requirements

### Access Control
- Only creator can resolve their market
- Only creator can cancel (if no bets)
- Users can only claim once per market

### Economic Security
- No withdrawal until resolution
- Creator fee capped at 10%
- Refund mechanism if creator disappears
- ReentrancyGuard on claims

### Token Safety
- Check return values on transfers
- Handle tokens with varying decimals
- Support tokens without metadata functions

## Edge Cases to Handle

1. **Creator doesn't resolve**: 7-day refund window
2. **No bets on one side**: Winners take entire pool
3. **Equal pools**: 1:1 payout (minus fees)
4. **Token without symbol()**: Fallback to address display
5. **Creator bets on own market**: Allowed, treated like any user
6. **Zero creator fee**: Winners split 100% of pool

## Gas Optimizations
- Pack struct variables efficiently
- Use mappings over arrays where possible
- Avoid loops in claim calculations
- Single transfer per claim

## Events for Frontend
- `MarketCreated`: Monitor for new markets
- `BetPlaced`: Update pool sizes and odds
- `MarketResolved`: Enable claiming
- `WinningsClaimed`: Update UI state

## Optional Features (Consider for V2)
- Token whitelist/blacklist
- Maximum bet limits
- Early market closure by creator
- Partial refunds if cancelled with bets
- Multi-outcome markets (>2 choices)
- Oracle integration for auto-resolution
- Minimum pool size for valid resolution

## Not in Scope (Explicitly)
- KYC/AML
- Built-in DEX integration
- Liquidity provision
- Market making
- Cross-chain betting
- NFT betting
- Partial claims


# UI 

## Bet page layout 

```
[Question Title]
by: 0x123...abc | Ends: 2h 34m

[YES 60%]              [NO 40%]
████████░░░░░░         ░░░░░░░░████
15.5 USDC              10.3 USDC
12 bettors             8 bettors

Your Position: 2.5 USDC on YES
Potential Win: 4.16 USDC

[Amount Input] [BET YES] [BET NO]

[Share Bet] [Copy Link]
```