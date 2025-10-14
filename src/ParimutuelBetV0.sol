// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ParimutuelBetV0 is ReentrancyGuard {
    string public constant VERSION = "0.6.0";

    struct Market {
        address creator;
        string question;
        uint256 deadline;
        uint256 createdAt;
        uint256 yesPool;
        uint256 noPool;
        bool resolved;
        bool outcome;
    }

    // Structs for return values (frontend-friendly)
    struct PaginatedMarketIds {
        uint256[] ids;
        bool hasMore;
    }

    struct UserPosition {
        uint256[] marketIds;
        uint256[] amounts;
    }

    struct MarketStats {
        uint256 totalPool;
        uint256 yesPoolUnclaimed;
        uint256 noPoolUnclaimed;
        uint256 totalClaimed;
        uint256 totalRefunded;
    }

    struct MarketWithUserData {
        Market market;
        uint256 userYesBet;
        uint256 userNoBet;
        uint256 potentialPayoutYes;
        uint256 potentialPayoutNo;
        bool userCanClaim;
        bool userHasClaimed;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => uint256)) public yesBets;
    mapping(uint256 => mapping(address => uint256)) public noBets;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    mapping(uint256 => mapping(address => bool)) public hasRefunded;

    // Track total claimed/refunded amounts for accurate payout calculations
    mapping(uint256 => uint256) public yesPoolClaimed;
    mapping(uint256 => uint256) public noPoolClaimed;
    mapping(uint256 => uint256) public yesPoolRefunded;
    mapping(uint256 => uint256) public noPoolRefunded;

    uint256 public nextMarketId;
    uint256 public constant REFUND_PERIOD = 7 days;

    // Market tracking for efficient queries
    uint256[] private allMarketIds;
    mapping(address => uint256[]) private userMarketIds;
    mapping(address => uint256[]) private creatorMarketIds;

    event MarketCreated(uint256 indexed marketId, address indexed creator, string question, uint256 deadline);
    event BetPlaced(
        uint256 indexed marketId, address indexed bettor, bool betYes, uint256 amount, uint256 yesPool, uint256 noPool
    );
    event MarketResolved(uint256 indexed marketId, bool outcome, uint256 yesPool, uint256 noPool);
    event Claimed(uint256 indexed marketId, address indexed claimer, uint256 amount, address indexed triggeredBy);
    event Refunded(uint256 indexed marketId, address indexed refundee, uint256 amount, address indexed triggeredBy);

    function createMarket(string memory question, uint256 deadline) external returns (uint256) {
        require(deadline > block.timestamp, "Deadline must be in future");

        uint256 marketId = nextMarketId++;
        markets[marketId] = Market({
            creator: msg.sender,
            question: question,
            deadline: deadline,
            createdAt: block.timestamp,
            yesPool: 0,
            noPool: 0,
            resolved: false,
            outcome: false
        });

        // Track market for queries
        allMarketIds.push(marketId);
        creatorMarketIds[msg.sender].push(marketId);

        emit MarketCreated(marketId, msg.sender, question, deadline);
        return marketId;
    }

    function placeBet(uint256 marketId, bool betYes) external payable {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(markets[marketId].creator != address(0), "Market does not exist");
        require(block.timestamp < markets[marketId].deadline, "Betting period has ended");
        require(!markets[marketId].resolved, "Market already resolved");

        // Track user's first bet on this market
        if (yesBets[marketId][msg.sender] == 0 && noBets[marketId][msg.sender] == 0) {
            userMarketIds[msg.sender].push(marketId);
        }

        if (betYes) {
            yesBets[marketId][msg.sender] += msg.value;
            markets[marketId].yesPool += msg.value;
        } else {
            noBets[marketId][msg.sender] += msg.value;
            markets[marketId].noPool += msg.value;
        }

        emit BetPlaced(marketId, msg.sender, betYes, msg.value, markets[marketId].yesPool, markets[marketId].noPool);
    }

    function resolve(uint256 marketId, bool outcome) external {
        require(markets[marketId].creator != address(0), "Market does not exist");
        require(msg.sender == markets[marketId].creator, "Only creator can resolve");
        require(block.timestamp > markets[marketId].deadline, "Cannot resolve before deadline");
        require(!markets[marketId].resolved, "Market already resolved");
        require(
            yesPoolRefunded[marketId] == 0 && noPoolRefunded[marketId] == 0,
            "Cannot resolve after refunds have been claimed"
        );

        markets[marketId].resolved = true;
        markets[marketId].outcome = outcome;

        emit MarketResolved(marketId, outcome, markets[marketId].yesPool, markets[marketId].noPool);
    }

    /**
     * @dev Internal function to calculate payout for a user based on outcome
     * @param marketId The market ID
     * @param user Address of the user
     * @param outcome The outcome to calculate payout for (true = YES, false = NO)
     * @return payout The calculated payout amount
     */
    function _calculatePayout(uint256 marketId, address user, bool outcome) internal view returns (uint256) {
        Market memory market = markets[marketId];
        uint256 totalPot = market.yesPool + market.noPool;

        if (totalPot == 0) {
            return 0;
        }

        if (outcome) {
            uint256 userYesBet = yesBets[marketId][user];
            if (userYesBet == 0) {
                return 0;
            }
            if (market.yesPool == 0) {
                return userYesBet;
            }
            return (userYesBet * totalPot) / market.yesPool;
        } else {
            uint256 userNoBet = noBets[marketId][user];
            if (userNoBet == 0) {
                return 0;
            }
            if (market.noPool == 0) {
                return userNoBet;
            }
            return (userNoBet * totalPot) / market.noPool;
        }
    }

    function claim(uint256 marketId, address user) external nonReentrant {
        // Default to msg.sender if user is address(0)
        address beneficiary = user == address(0) ? msg.sender : user;

        require(markets[marketId].resolved, "Market not resolved");
        require(!hasClaimed[marketId][beneficiary], "Already claimed");

        uint256 payout = _calculatePayout(marketId, beneficiary, markets[marketId].outcome);
        require(payout > 0, "No winning bet to claim");

        // Mark as claimed (prevent reentrancy)
        hasClaimed[marketId][beneficiary] = true;

        // Track claimed amounts for accurate remaining payout calculations
        if (markets[marketId].outcome) {
            yesPoolClaimed[marketId] += yesBets[marketId][beneficiary];
        } else {
            noPoolClaimed[marketId] += noBets[marketId][beneficiary];
        }

        // Send payout to beneficiary
        (bool success,) = payable(beneficiary).call{value: payout}("");
        require(success, "ETH transfer failed");
        emit Claimed(marketId, beneficiary, payout, msg.sender);
    }

    function refund(uint256 marketId, address user) external nonReentrant {
        // Default to msg.sender if user is address(0)
        address beneficiary = user == address(0) ? msg.sender : user;

        require(markets[marketId].creator != address(0), "Market does not exist");
        require(!markets[marketId].resolved, "Market already resolved");
        require(block.timestamp > markets[marketId].deadline + REFUND_PERIOD, "Refund period not reached");
        require(!hasRefunded[marketId][beneficiary], "Already refunded");

        uint256 userYesBet = yesBets[marketId][beneficiary];
        uint256 userNoBet = noBets[marketId][beneficiary];
        uint256 totalRefund = userYesBet + userNoBet;

        require(totalRefund > 0, "No bets to refund");

        // Mark as refunded to prevent double refunds
        hasRefunded[marketId][beneficiary] = true;

        // Track refunded amounts for accurate pool calculations
        yesPoolRefunded[marketId] += userYesBet;
        noPoolRefunded[marketId] += userNoBet;

        // Send refund to beneficiary
        (bool success,) = payable(beneficiary).call{value: totalRefund}("");
        require(success, "ETH transfer failed");
        emit Refunded(marketId, beneficiary, totalRefund, msg.sender);
    }

    // ============================================
    // QUERY FUNCTIONS FOR MARKET DISCOVERY
    // ============================================

    /**
     * @notice Get total number of markets created
     * @return Total count of all markets
     */
    function getTotalMarketsCount() external view returns (uint256) {
        return allMarketIds.length;
    }

    /**
     * @notice Get paginated list of markets open for betting (not resolved, before deadline)
     * @dev This is the main function for home page market browsing
     * @param offset Starting index in the markets array
     * @param limit Maximum number of markets to return
     * @return result PaginatedMarketIds struct with ids array and hasMore flag
     */
    function getOpenMarketIds(uint256 offset, uint256 limit) external view returns (PaginatedMarketIds memory result) {
        uint256 totalMarkets = allMarketIds.length;
        if (offset >= totalMarkets) {
            return PaginatedMarketIds({ids: new uint256[](0), hasMore: false});
        }

        // Single-pass: collect up to limit+1 results to detect hasMore
        uint256[] memory tempIds = new uint256[](limit + 1);
        uint256 count = 0;

        for (uint256 i = offset; i < totalMarkets && count <= limit; i++) {
            uint256 marketId = allMarketIds[i];
            Market storage market = markets[marketId];

            if (!market.resolved && block.timestamp < market.deadline) {
                tempIds[count] = marketId;
                count++;
            }
        }

        // Determine if there are more results
        bool hasMore = count > limit;
        uint256 resultSize = hasMore ? limit : count;

        // Copy to correctly sized array
        uint256[] memory ids = new uint256[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            ids[i] = tempIds[i];
        }

        return PaginatedMarketIds({ids: ids, hasMore: hasMore});
    }

    /**
     * @notice Get paginated list of markets awaiting resolution (past deadline, not resolved)
     * @param offset Starting index in the markets array
     * @param limit Maximum number of markets to return
     * @return result PaginatedMarketIds struct with ids array and hasMore flag
     */
    function getAwaitingResolutionIds(uint256 offset, uint256 limit)
        external
        view
        returns (PaginatedMarketIds memory result)
    {
        uint256 totalMarkets = allMarketIds.length;
        if (offset >= totalMarkets) {
            return PaginatedMarketIds({ids: new uint256[](0), hasMore: false});
        }

        // Single-pass: collect up to limit+1 results to detect hasMore
        uint256[] memory tempIds = new uint256[](limit + 1);
        uint256 count = 0;

        for (uint256 i = offset; i < totalMarkets && count <= limit; i++) {
            uint256 marketId = allMarketIds[i];
            Market storage market = markets[marketId];

            if (!market.resolved && block.timestamp >= market.deadline) {
                tempIds[count] = marketId;
                count++;
            }
        }

        // Determine if there are more results
        bool hasMore = count > limit;
        uint256 resultSize = hasMore ? limit : count;

        // Copy to correctly sized array
        uint256[] memory ids = new uint256[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            ids[i] = tempIds[i];
        }

        return PaginatedMarketIds({ids: ids, hasMore: hasMore});
    }

    /**
     * @notice Get paginated list of resolved market IDs
     * @param offset Starting index in the markets array
     * @param limit Maximum number of markets to return
     * @return result PaginatedMarketIds struct with ids array and hasMore flag
     */
    function getResolvedMarketIds(uint256 offset, uint256 limit)
        external
        view
        returns (PaginatedMarketIds memory result)
    {
        uint256 totalMarkets = allMarketIds.length;
        if (offset >= totalMarkets) {
            return PaginatedMarketIds({ids: new uint256[](0), hasMore: false});
        }

        // Single-pass: collect up to limit+1 results to detect hasMore
        uint256[] memory tempIds = new uint256[](limit + 1);
        uint256 count = 0;

        for (uint256 i = offset; i < totalMarkets && count <= limit; i++) {
            uint256 marketId = allMarketIds[i];
            if (markets[marketId].resolved) {
                tempIds[count] = marketId;
                count++;
            }
        }

        // Determine if there are more results
        bool hasMore = count > limit;
        uint256 resultSize = hasMore ? limit : count;

        // Copy to correctly sized array
        uint256[] memory ids = new uint256[](resultSize);
        for (uint256 i = 0; i < resultSize; i++) {
            ids[i] = tempIds[i];
        }

        return PaginatedMarketIds({ids: ids, hasMore: hasMore});
    }

    /**
     * @notice Batch fetch market details for multiple market IDs
     * @param marketIds Array of market IDs to fetch
     * @return marketsData Array of Market structs
     */
    function getMarkets(uint256[] calldata marketIds) external view returns (Market[] memory marketsData) {
        marketsData = new Market[](marketIds.length);
        for (uint256 i = 0; i < marketIds.length; i++) {
            marketsData[i] = markets[marketIds[i]];
        }
        return marketsData;
    }

    // ============================================
    // USER POSITION QUERIES
    // ============================================

    /**
     * @notice Batch fetch user bets for multiple markets
     * @param marketIds Array of market IDs to query
     * @param user Address of the user
     * @return yesBetsArray Array of YES bet amounts for each market
     * @return noBetsArray Array of NO bet amounts for each market
     */
    function getUserBetsForMarkets(uint256[] calldata marketIds, address user)
        external
        view
        returns (uint256[] memory yesBetsArray, uint256[] memory noBetsArray)
    {
        yesBetsArray = new uint256[](marketIds.length);
        noBetsArray = new uint256[](marketIds.length);

        for (uint256 i = 0; i < marketIds.length; i++) {
            yesBetsArray[i] = yesBets[marketIds[i]][user];
            noBetsArray[i] = noBets[marketIds[i]][user];
        }

        return (yesBetsArray, noBetsArray);
    }

    /**
     * @notice Get markets where user can claim winnings
     * @param user Address to query
     * @return result UserPosition struct with marketIds and amounts arrays
     */
    function getUserClaimable(address user) external view returns (UserPosition memory result) {
        uint256[] memory userMarkets = userMarketIds[user];
        uint256[] memory tempIds = new uint256[](userMarkets.length);
        uint256[] memory tempAmounts = new uint256[](userMarkets.length);
        uint256 count = 0;

        // Single pass: collect claimable markets
        for (uint256 i = 0; i < userMarkets.length; i++) {
            uint256 marketId = userMarkets[i];
            if (markets[marketId].resolved && !hasClaimed[marketId][user]) {
                uint256 payout = _calculatePayout(marketId, user, markets[marketId].outcome);
                if (payout > 0) {
                    tempIds[count] = marketId;
                    tempAmounts[count] = payout;
                    count++;
                }
            }
        }

        // Copy to correctly sized arrays
        uint256[] memory marketIds = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            marketIds[i] = tempIds[i];
            amounts[i] = tempAmounts[i];
        }

        return UserPosition({marketIds: marketIds, amounts: amounts});
    }

    /**
     * @notice Get markets where user can get refunds
     * @param user Address to query
     * @return result UserPosition struct with marketIds and amounts arrays
     */
    function getUserRefundable(address user) external view returns (UserPosition memory result) {
        uint256[] memory userMarkets = userMarketIds[user];
        uint256[] memory tempIds = new uint256[](userMarkets.length);
        uint256[] memory tempAmounts = new uint256[](userMarkets.length);
        uint256 count = 0;

        // Single pass: collect refundable markets
        for (uint256 i = 0; i < userMarkets.length; i++) {
            uint256 marketId = userMarkets[i];
            if (
                markets[marketId].creator != address(0) && !markets[marketId].resolved
                    && block.timestamp > markets[marketId].deadline + REFUND_PERIOD && !hasRefunded[marketId][user]
            ) {
                uint256 totalRefund = yesBets[marketId][user] + noBets[marketId][user];
                if (totalRefund > 0) {
                    tempIds[count] = marketId;
                    tempAmounts[count] = totalRefund;
                    count++;
                }
            }
        }

        // Copy to correctly sized arrays
        uint256[] memory marketIds = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            marketIds[i] = tempIds[i];
            amounts[i] = tempAmounts[i];
        }

        return UserPosition({marketIds: marketIds, amounts: amounts});
    }

    // ============================================
    // CREATOR MANAGEMENT QUERIES
    // ============================================

    /**
     * @notice Get all market IDs created by a specific creator
     * @param creator Address of the creator
     * @return Array of market IDs created by this address
     */
    function getCreatorMarkets(address creator) external view returns (uint256[] memory) {
        return creatorMarketIds[creator];
    }

    /**
     * @notice Get markets created by address that need resolution
     * @param creator Address of the creator
     * @return Array of market IDs that are past deadline but not yet resolved
     */
    function getCreatorPendingResolution(address creator) external view returns (uint256[] memory) {
        uint256[] memory creatorMarkets = creatorMarketIds[creator];
        uint256 count = 0;

        // Count markets that need resolution
        for (uint256 i = 0; i < creatorMarkets.length; i++) {
            uint256 marketId = creatorMarkets[i];
            if (!markets[marketId].resolved && block.timestamp > markets[marketId].deadline) {
                count++;
            }
        }

        // Build result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < creatorMarkets.length; i++) {
            uint256 marketId = creatorMarkets[i];
            if (!markets[marketId].resolved && block.timestamp > markets[marketId].deadline) {
                result[index] = marketId;
                index++;
            }
        }

        return result;
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Get comprehensive statistics for a market
     * @param marketId The market ID to query
     * @return stats MarketStats struct with pool and claim/refund information
     */
    function getMarketStats(uint256 marketId) external view returns (MarketStats memory stats) {
        Market storage market = markets[marketId];

        stats.totalPool = market.yesPool + market.noPool;
        stats.yesPoolUnclaimed = market.yesPool - yesPoolClaimed[marketId] - yesPoolRefunded[marketId];
        stats.noPoolUnclaimed = market.noPool - noPoolClaimed[marketId] - noPoolRefunded[marketId];
        stats.totalClaimed = yesPoolClaimed[marketId] + noPoolClaimed[marketId];
        stats.totalRefunded = yesPoolRefunded[marketId] + noPoolRefunded[marketId];

        return stats;
    }

    /**
     * @notice Get comprehensive market data along with user-specific information
     * @param marketId The market ID to query
     * @param user Address of the user
     * @return data MarketWithUserData struct containing all market and user information
     */
    function getMarketWithUserData(uint256 marketId, address user)
        external
        view
        returns (MarketWithUserData memory data)
    {
        data.market = markets[marketId];
        data.userYesBet = yesBets[marketId][user];
        data.userNoBet = noBets[marketId][user];
        data.userHasClaimed = hasClaimed[marketId][user];

        // Calculate potential payouts for both outcomes using helper
        data.potentialPayoutYes = _calculatePayout(marketId, user, true);
        data.potentialPayoutNo = _calculatePayout(marketId, user, false);

        // Check if user can currently claim
        if (data.market.resolved && !data.userHasClaimed) {
            uint256 actualPayout = data.market.outcome ? data.potentialPayoutYes : data.potentialPayoutNo;
            data.userCanClaim = actualPayout > 0;
        }

        return data;
    }
}
