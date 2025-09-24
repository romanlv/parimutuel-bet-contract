// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ParimutuelBetV0 is ReentrancyGuard {
    struct Market {
        address creator;
        string question;
        uint256 deadline;
        uint256 yesPool;
        uint256 noPool;
        bool resolved;
        bool outcome;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => uint256)) public yesBets;
    mapping(uint256 => mapping(address => uint256)) public noBets;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    mapping(uint256 => mapping(address => bool)) public hasRefunded;

    uint256 public nextMarketId;
    uint256 public constant REFUND_PERIOD = 7 days;

    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint256 deadline);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, bool betYes, uint256 amount);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event Claimed(uint256 indexed marketId, address indexed claimer, uint256 amount);
    event Refunded(uint256 indexed marketId, address indexed refundee, uint256 amount);

    function createMarket(string memory question, uint256 deadline) external returns (uint256) {
        require(deadline > block.timestamp, "Deadline must be in future");

        uint256 marketId = nextMarketId++;
        markets[marketId] = Market({
            creator: msg.sender,
            question: question,
            deadline: deadline,
            yesPool: 0,
            noPool: 0,
            resolved: false,
            outcome: false
        });

        emit MarketCreated(marketId, msg.sender, question, deadline);
        return marketId;
    }

    function placeBet(uint256 marketId, bool betYes) external payable {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(markets[marketId].creator != address(0), "Market does not exist");
        require(block.timestamp < markets[marketId].deadline, "Betting period has ended");
        require(!markets[marketId].resolved, "Market already resolved");

        if (betYes) {
            yesBets[marketId][msg.sender] += msg.value;
            markets[marketId].yesPool += msg.value;
        } else {
            noBets[marketId][msg.sender] += msg.value;
            markets[marketId].noPool += msg.value;
        }

        emit BetPlaced(marketId, msg.sender, betYes, msg.value);
    }

    function resolve(uint256 marketId, bool outcome) external {
        require(markets[marketId].creator != address(0), "Market does not exist");
        require(msg.sender == markets[marketId].creator, "Only creator can resolve");
        require(block.timestamp > markets[marketId].deadline, "Cannot resolve before deadline");
        require(!markets[marketId].resolved, "Market already resolved");

        markets[marketId].resolved = true;
        markets[marketId].outcome = outcome;

        emit MarketResolved(marketId, outcome);
    }

    function claim(uint256 marketId) external nonReentrant {
        require(markets[marketId].resolved, "Market not resolved");
        require(!hasClaimed[marketId][msg.sender], "Already claimed");

        uint256 payout = 0;
        uint256 totalPot = markets[marketId].yesPool + markets[marketId].noPool;

        require(totalPot > 0, "No bets to claim");

        if (markets[marketId].outcome) {
            // YES won
            uint256 userYesBet = yesBets[marketId][msg.sender];
            require(userYesBet > 0, "No winning bet to claim");

            // Handle case where only losing side has bets (division by zero protection)
            if (markets[marketId].yesPool == 0) {
                // Everyone bet NO but YES won - return user's bet
                payout = userYesBet;
            } else {
                payout = (userYesBet * totalPot) / markets[marketId].yesPool;
            }
        } else {
            // NO won
            uint256 userNoBet = noBets[marketId][msg.sender];
            require(userNoBet > 0, "No winning bet to claim");

            // Handle case where only losing side has bets (division by zero protection)
            if (markets[marketId].noPool == 0) {
                // Everyone bet YES but NO won - return user's bet
                payout = userNoBet;
            } else {
                payout = (userNoBet * totalPot) / markets[marketId].noPool;
            }
        }

        // Mark as claimed (prevent reentrancy)
        hasClaimed[marketId][msg.sender] = true;

        // Send payout
        if (payout > 0) {
            payable(msg.sender).transfer(payout);
            emit Claimed(marketId, msg.sender, payout);
        }
    }

    // View functions for market data access
    function getMarket(uint256 marketId) external view returns (
        address creator,
        string memory question,
        uint256 deadline,
        uint256 yesPool,
        uint256 noPool,
        bool resolved,
        bool outcome
    ) {
        Market memory market = markets[marketId];
        return (
            market.creator,
            market.question,
            market.deadline,
            market.yesPool,
            market.noPool,
            market.resolved,
            market.outcome
        );
    }

    function getUserBets(uint256 marketId, address user) external view returns (uint256 yesBet, uint256 noBet) {
        return (yesBets[marketId][user], noBets[marketId][user]);
    }

    function getMarketPools(uint256 marketId) external view returns (uint256 yesPool, uint256 noPool, uint256 totalPool) {
        Market memory market = markets[marketId];
        return (market.yesPool, market.noPool, market.yesPool + market.noPool);
    }

    function marketExists(uint256 marketId) external view returns (bool) {
        return markets[marketId].creator != address(0);
    }

    function refund(uint256 marketId) external nonReentrant {
        require(markets[marketId].creator != address(0), "Market does not exist");
        require(!markets[marketId].resolved, "Market already resolved");
        require(block.timestamp > markets[marketId].deadline + REFUND_PERIOD, "Refund period not reached");
        require(!hasRefunded[marketId][msg.sender], "Already refunded");

        uint256 userYesBet = yesBets[marketId][msg.sender];
        uint256 userNoBet = noBets[marketId][msg.sender];
        uint256 totalRefund = userYesBet + userNoBet;

        require(totalRefund > 0, "No bets to refund");

        // Mark as refunded to prevent double refunds
        hasRefunded[marketId][msg.sender] = true;

        // Send refund
        payable(msg.sender).transfer(totalRefund);
        emit Refunded(marketId, msg.sender, totalRefund);
    }

    function canRefund(uint256 marketId) external view returns (bool) {
        return markets[marketId].creator != address(0) &&
               !markets[marketId].resolved &&
               block.timestamp > markets[marketId].deadline + REFUND_PERIOD;
    }
}
