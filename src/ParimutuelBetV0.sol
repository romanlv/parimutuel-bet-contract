// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ParimutuelBetV0 is ReentrancyGuard {
    string public constant VERSION = "0.7.1";

    struct Bet {
        address creator;
        address resolver;
        string question;
        uint256 deadline;
        uint256 createdAt;
        uint256 yesTotal;
        uint256 noTotal;
        bool resolved;
        bool outcome;
    }

    // Structs for return values (frontend-friendly)
    struct PaginatedBetIds {
        uint256[] ids;
        bool hasMore;
    }

    struct UserPosition {
        uint256[] betIds;
        uint256[] amounts;
    }

    struct BetStats {
        uint256 totalAmount;
        uint256 yesAmountLeft;
        uint256 noAmountLeft;
        uint256 totalClaimed;
        uint256 totalRefunded;
    }

    struct BetWithUserData {
        Bet bet;
        uint256 userYesPosition;
        uint256 userNoPosition;
        uint256 potentialPayoutYes;
        uint256 potentialPayoutNo;
        bool userCanClaim;
        bool userHasClaimed;
    }

    mapping(uint256 => Bet) public bets;
    mapping(uint256 => mapping(address => uint256)) public yesPositions;
    mapping(uint256 => mapping(address => uint256)) public noPositions;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    mapping(uint256 => mapping(address => bool)) public hasRefunded;
    mapping(uint256 => mapping(address => string)) public displayNames;

    // Track total claimed/refunded amounts for accurate payout calculations
    mapping(uint256 => uint256) public yesTotalClaimed;
    mapping(uint256 => uint256) public noTotalClaimed;
    mapping(uint256 => uint256) public yesTotalRefunded;
    mapping(uint256 => uint256) public noTotalRefunded;

    uint256 public nextBetId;
    uint256 public constant REFUND_PERIOD = 7 days;
    uint256 public constant MAX_DEADLINE_DURATION = 365 days;

    // Bet tracking for efficient queries
    uint256[] private allBetIds;
    mapping(address => uint256[]) private userBetIds;
    mapping(address => uint256[]) private creatorBetIds;

    event BetCreated(
        uint256 indexed betId, address indexed creator, address indexed resolver, string question, uint256 deadline
    );
    event PositionTaken(
        uint256 indexed betId,
        address indexed user,
        bool isYes,
        uint256 amount,
        uint256 yesTotal,
        uint256 noTotal,
        string displayName
    );
    event BetResolved(uint256 indexed betId, bool outcome, uint256 yesTotal, uint256 noTotal);
    event Claimed(uint256 indexed betId, address indexed user, uint256 amount, address indexed triggeredBy);
    event Refunded(uint256 indexed betId, address indexed user, uint256 amount, address indexed triggeredBy);

    function createBet(string memory question, uint256 deadline, address resolver) external returns (uint256) {
        require(deadline > block.timestamp, "Deadline must be in future");
        require(deadline <= block.timestamp + MAX_DEADLINE_DURATION, "Deadline too far in future");
        require(resolver != address(0), "Resolver cannot be zero address");

        uint256 betId = nextBetId++;
        bets[betId] = Bet({
            creator: msg.sender,
            resolver: resolver,
            question: question,
            deadline: deadline,
            createdAt: block.timestamp,
            yesTotal: 0,
            noTotal: 0,
            resolved: false,
            outcome: false
        });

        // Track bet for queries
        allBetIds.push(betId);
        creatorBetIds[msg.sender].push(betId);

        emit BetCreated(betId, msg.sender, resolver, question, deadline);
        return betId;
    }

    function takePosition(uint256 betId, bool isYes, string calldata displayName) external payable {
        require(msg.value > 0, "Amount must be greater than 0");
        require(bets[betId].creator != address(0), "Bet does not exist");
        require(block.timestamp < bets[betId].deadline, "Betting period has ended");
        require(!bets[betId].resolved, "Bet already resolved");

        // Only store displayName if it's not empty (gas optimization)
        if (bytes(displayName).length > 0) {
            require(bytes(displayName).length <= 32, "Display name too long");
            displayNames[betId][msg.sender] = displayName;
        }

        // Track user's first position on this bet
        if (yesPositions[betId][msg.sender] == 0 && noPositions[betId][msg.sender] == 0) {
            userBetIds[msg.sender].push(betId);
        }

        if (isYes) {
            yesPositions[betId][msg.sender] += msg.value;
            bets[betId].yesTotal += msg.value;
        } else {
            noPositions[betId][msg.sender] += msg.value;
            bets[betId].noTotal += msg.value;
        }

        emit PositionTaken(betId, msg.sender, isYes, msg.value, bets[betId].yesTotal, bets[betId].noTotal, displayName);
    }

    function resolve(uint256 betId, bool outcome) external {
        require(bets[betId].creator != address(0), "Bet does not exist");
        require(msg.sender == bets[betId].resolver, "Only resolver can resolve");
        require(block.timestamp > bets[betId].deadline, "Cannot resolve before deadline");
        require(!bets[betId].resolved, "Bet already resolved");
        require(
            yesTotalRefunded[betId] == 0 && noTotalRefunded[betId] == 0,
            "Cannot resolve after refunds have been claimed"
        );

        bets[betId].resolved = true;
        bets[betId].outcome = outcome;

        emit BetResolved(betId, outcome, bets[betId].yesTotal, bets[betId].noTotal);
    }

    /**
     * @dev Internal function to calculate payout for a user based on outcome
     * @param betId The bet ID
     * @param user Address of the user
     * @param outcome The outcome to calculate payout for (true = YES, false = NO)
     * @return payout The calculated payout amount
     */
    function _calculatePayout(uint256 betId, address user, bool outcome) internal view returns (uint256) {
        Bet memory bet = bets[betId];
        uint256 totalAmount = bet.yesTotal + bet.noTotal;

        if (totalAmount == 0) {
            return 0;
        }

        if (outcome) {
            uint256 userYesPosition = yesPositions[betId][user];
            if (userYesPosition == 0) {
                return 0;
            }
            if (bet.yesTotal == 0) {
                return userYesPosition;
            }
            return (userYesPosition * totalAmount) / bet.yesTotal;
        } else {
            uint256 userNoPosition = noPositions[betId][user];
            if (userNoPosition == 0) {
                return 0;
            }
            if (bet.noTotal == 0) {
                return userNoPosition;
            }
            return (userNoPosition * totalAmount) / bet.noTotal;
        }
    }

    function claim(uint256 betId, address user) external nonReentrant {
        // Default to msg.sender if user is address(0)
        address beneficiary = user == address(0) ? msg.sender : user;

        require(bets[betId].resolved, "Bet not resolved");
        require(!hasClaimed[betId][beneficiary], "Already claimed");

        uint256 payout = _calculatePayout(betId, beneficiary, bets[betId].outcome);
        require(payout > 0, "No winning position to claim");

        // Mark as claimed (prevent reentrancy)
        hasClaimed[betId][beneficiary] = true;

        // Track claimed amounts for accurate remaining payout calculations
        if (bets[betId].outcome) {
            yesTotalClaimed[betId] += yesPositions[betId][beneficiary];
        } else {
            noTotalClaimed[betId] += noPositions[betId][beneficiary];
        }

        // Send payout to beneficiary
        (bool success,) = payable(beneficiary).call{value: payout}("");
        require(success, "ETH transfer failed");
        emit Claimed(betId, beneficiary, payout, msg.sender);
    }

    function refund(uint256 betId, address user) external nonReentrant {
        // Default to msg.sender if user is address(0)
        address beneficiary = user == address(0) ? msg.sender : user;

        require(bets[betId].creator != address(0), "Bet does not exist");
        require(!bets[betId].resolved, "Bet already resolved");
        require(block.timestamp > bets[betId].deadline + REFUND_PERIOD, "Refund period not reached");
        require(!hasRefunded[betId][beneficiary], "Already refunded");

        uint256 userYesPosition = yesPositions[betId][beneficiary];
        uint256 userNoPosition = noPositions[betId][beneficiary];
        uint256 totalRefund = userYesPosition + userNoPosition;

        require(totalRefund > 0, "No positions to refund");

        // Mark as refunded to prevent double refunds
        hasRefunded[betId][beneficiary] = true;

        // Track refunded amounts for accurate calculations
        yesTotalRefunded[betId] += userYesPosition;
        noTotalRefunded[betId] += userNoPosition;

        // Send refund to beneficiary
        (bool success,) = payable(beneficiary).call{value: totalRefund}("");
        require(success, "ETH transfer failed");
        emit Refunded(betId, beneficiary, totalRefund, msg.sender);
    }

    // ============================================
    // QUERY FUNCTIONS FOR BET DISCOVERY
    // ============================================

    /**
     * @notice Get total number of bets created
     * @return Total count of all bets
     */
    function getTotalBetsCount() external view returns (uint256) {
        return allBetIds.length;
    }

    /**
     * @notice Get paginated list of bets open for positions (not resolved, before deadline)
     * @dev This is the main function for home page bet browsing
     * @param offset Starting index in the bets array
     * @param limit Maximum number of bets to return
     * @return result PaginatedBetIds struct with ids array and hasMore flag
     */
    function getOpenBetIds(uint256 offset, uint256 limit) external view returns (PaginatedBetIds memory result) {
        uint256 totalBets = allBetIds.length;
        if (offset >= totalBets) {
            return PaginatedBetIds({ids: new uint256[](0), hasMore: false});
        }

        // Single-pass: collect up to limit+1 results to detect hasMore
        uint256[] memory tempIds = new uint256[](limit + 1);
        uint256 count = 0;

        for (uint256 i = offset; i < totalBets && count <= limit; i++) {
            uint256 betId = allBetIds[i];
            Bet storage bet = bets[betId];

            if (!bet.resolved && block.timestamp < bet.deadline) {
                tempIds[count] = betId;
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

        return PaginatedBetIds({ids: ids, hasMore: hasMore});
    }

    /**
     * @notice Get paginated list of bets awaiting resolution (past deadline, not resolved)
     * @param offset Starting index in the bets array
     * @param limit Maximum number of bets to return
     * @return result PaginatedBetIds struct with ids array and hasMore flag
     */
    function getAwaitingResolutionIds(uint256 offset, uint256 limit)
        external
        view
        returns (PaginatedBetIds memory result)
    {
        uint256 totalBets = allBetIds.length;
        if (offset >= totalBets) {
            return PaginatedBetIds({ids: new uint256[](0), hasMore: false});
        }

        // Single-pass: collect up to limit+1 results to detect hasMore
        uint256[] memory tempIds = new uint256[](limit + 1);
        uint256 count = 0;

        for (uint256 i = offset; i < totalBets && count <= limit; i++) {
            uint256 betId = allBetIds[i];
            Bet storage bet = bets[betId];

            if (!bet.resolved && block.timestamp >= bet.deadline) {
                tempIds[count] = betId;
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

        return PaginatedBetIds({ids: ids, hasMore: hasMore});
    }

    /**
     * @notice Get paginated list of resolved bet IDs
     * @param offset Starting index in the bets array
     * @param limit Maximum number of bets to return
     * @return result PaginatedBetIds struct with ids array and hasMore flag
     */
    function getResolvedBetIds(uint256 offset, uint256 limit) external view returns (PaginatedBetIds memory result) {
        uint256 totalBets = allBetIds.length;
        if (offset >= totalBets) {
            return PaginatedBetIds({ids: new uint256[](0), hasMore: false});
        }

        // Single-pass: collect up to limit+1 results to detect hasMore
        uint256[] memory tempIds = new uint256[](limit + 1);
        uint256 count = 0;

        for (uint256 i = offset; i < totalBets && count <= limit; i++) {
            uint256 betId = allBetIds[i];
            if (bets[betId].resolved) {
                tempIds[count] = betId;
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

        return PaginatedBetIds({ids: ids, hasMore: hasMore});
    }

    /**
     * @notice Batch fetch bet details for multiple bet IDs
     * @param betIds Array of bet IDs to fetch
     * @return betsData Array of Bet structs
     */
    function getBets(uint256[] calldata betIds) external view returns (Bet[] memory betsData) {
        betsData = new Bet[](betIds.length);
        for (uint256 i = 0; i < betIds.length; i++) {
            betsData[i] = bets[betIds[i]];
        }
        return betsData;
    }

    // ============================================
    // USER POSITION QUERIES
    // ============================================

    /**
     * @notice Batch fetch user positions for multiple bets
     * @param betIds Array of bet IDs to query
     * @param user Address of the user
     * @return yesPositionsArray Array of YES position amounts for each bet
     * @return noPositionsArray Array of NO position amounts for each bet
     */
    function getUserPositions(uint256[] calldata betIds, address user)
        external
        view
        returns (uint256[] memory yesPositionsArray, uint256[] memory noPositionsArray)
    {
        yesPositionsArray = new uint256[](betIds.length);
        noPositionsArray = new uint256[](betIds.length);

        for (uint256 i = 0; i < betIds.length; i++) {
            yesPositionsArray[i] = yesPositions[betIds[i]][user];
            noPositionsArray[i] = noPositions[betIds[i]][user];
        }

        return (yesPositionsArray, noPositionsArray);
    }

    /**
     * @notice Get bets where user can claim winnings
     * @param user Address to query
     * @return result UserPosition struct with betIds and amounts arrays
     */
    function getUserClaimable(address user) external view returns (UserPosition memory result) {
        uint256[] memory userBets = userBetIds[user];
        uint256[] memory tempIds = new uint256[](userBets.length);
        uint256[] memory tempAmounts = new uint256[](userBets.length);
        uint256 count = 0;

        // Single pass: collect claimable bets
        for (uint256 i = 0; i < userBets.length; i++) {
            uint256 betId = userBets[i];
            if (bets[betId].resolved && !hasClaimed[betId][user]) {
                uint256 payout = _calculatePayout(betId, user, bets[betId].outcome);
                if (payout > 0) {
                    tempIds[count] = betId;
                    tempAmounts[count] = payout;
                    count++;
                }
            }
        }

        // Copy to correctly sized arrays
        uint256[] memory betIds = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            betIds[i] = tempIds[i];
            amounts[i] = tempAmounts[i];
        }

        return UserPosition({betIds: betIds, amounts: amounts});
    }

    /**
     * @notice Get bets where user can get refunds
     * @param user Address to query
     * @return result UserPosition struct with betIds and amounts arrays
     */
    function getUserRefundable(address user) external view returns (UserPosition memory result) {
        uint256[] memory userBets = userBetIds[user];
        uint256[] memory tempIds = new uint256[](userBets.length);
        uint256[] memory tempAmounts = new uint256[](userBets.length);
        uint256 count = 0;

        // Single pass: collect refundable bets
        for (uint256 i = 0; i < userBets.length; i++) {
            uint256 betId = userBets[i];
            if (
                bets[betId].creator != address(0) && !bets[betId].resolved
                    && block.timestamp > bets[betId].deadline + REFUND_PERIOD && !hasRefunded[betId][user]
            ) {
                uint256 totalRefund = yesPositions[betId][user] + noPositions[betId][user];
                if (totalRefund > 0) {
                    tempIds[count] = betId;
                    tempAmounts[count] = totalRefund;
                    count++;
                }
            }
        }

        // Copy to correctly sized arrays
        uint256[] memory betIds = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            betIds[i] = tempIds[i];
            amounts[i] = tempAmounts[i];
        }

        return UserPosition({betIds: betIds, amounts: amounts});
    }

    // ============================================
    // CREATOR MANAGEMENT QUERIES
    // ============================================

    /**
     * @notice Get all bet IDs created by a specific creator
     * @param creator Address of the creator
     * @return Array of bet IDs created by this address
     */
    function getCreatorBets(address creator) external view returns (uint256[] memory) {
        return creatorBetIds[creator];
    }

    /**
     * @notice Get bets created by address that need resolution
     * @param creator Address of the creator
     * @return Array of bet IDs that are past deadline but not yet resolved
     */
    function getCreatorPendingResolution(address creator) external view returns (uint256[] memory) {
        uint256[] memory creatorBets = creatorBetIds[creator];
        uint256 count = 0;

        // Count bets that need resolution
        for (uint256 i = 0; i < creatorBets.length; i++) {
            uint256 betId = creatorBets[i];
            if (!bets[betId].resolved && block.timestamp > bets[betId].deadline) {
                count++;
            }
        }

        // Build result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < creatorBets.length; i++) {
            uint256 betId = creatorBets[i];
            if (!bets[betId].resolved && block.timestamp > bets[betId].deadline) {
                result[index] = betId;
                index++;
            }
        }

        return result;
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Get display name for a user on a specific bet
     * @param betId The bet ID to query
     * @param user Address of the user
     * @return Display name string (empty if not set)
     */
    function getDisplayName(uint256 betId, address user) external view returns (string memory) {
        return displayNames[betId][user];
    }

    /**
     * @notice Batch get display names for multiple users on a specific bet
     * @param betId The bet ID to query
     * @param users Array of user addresses
     * @return names Array of display names corresponding to users
     */
    function getDisplayNames(uint256 betId, address[] calldata users) external view returns (string[] memory names) {
        names = new string[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            names[i] = displayNames[betId][users[i]];
        }
        return names;
    }

    /**
     * @notice Get comprehensive statistics for a bet
     * @param betId The bet ID to query
     * @return stats BetStats struct with totals and claim/refund information
     */
    function getBetStats(uint256 betId) external view returns (BetStats memory stats) {
        Bet storage bet = bets[betId];

        stats.totalAmount = bet.yesTotal + bet.noTotal;
        stats.yesAmountLeft = bet.yesTotal - yesTotalClaimed[betId] - yesTotalRefunded[betId];
        stats.noAmountLeft = bet.noTotal - noTotalClaimed[betId] - noTotalRefunded[betId];
        stats.totalClaimed = yesTotalClaimed[betId] + noTotalClaimed[betId];
        stats.totalRefunded = yesTotalRefunded[betId] + noTotalRefunded[betId];

        return stats;
    }

    /**
     * @notice Get comprehensive bet data along with user-specific information
     * @param betId The bet ID to query
     * @param user Address of the user
     * @return data BetWithUserData struct containing all bet and user information
     */
    function getBetWithUserData(uint256 betId, address user) external view returns (BetWithUserData memory data) {
        data.bet = bets[betId];
        data.userYesPosition = yesPositions[betId][user];
        data.userNoPosition = noPositions[betId][user];
        data.userHasClaimed = hasClaimed[betId][user];

        // Calculate potential payouts for both outcomes using helper
        data.potentialPayoutYes = _calculatePayout(betId, user, true);
        data.potentialPayoutNo = _calculatePayout(betId, user, false);

        // Check if user can currently claim
        if (data.bet.resolved && !data.userHasClaimed) {
            uint256 actualPayout = data.bet.outcome ? data.potentialPayoutYes : data.potentialPayoutNo;
            data.userCanClaim = actualPayout > 0;
        }

        return data;
    }
}
