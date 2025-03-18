// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@hamza-escrow/IPurchaseTracker.sol";

/**
 * @title ICommunityRewardsCalculator
 * @dev Defines the logic for calculating who gets what rewards, and for what reasons. The rewards are 
 * distributed through the CommunityVault. 
 */
interface ICommunityRewardsCalculator {
    /**
     * @notice Legacy function for backwards compatibility
     * @dev This function will be kept for compatibility but not used in newer versions
     */
    function getRewardsToDistribute(
        address token, 
        address[] calldata recipients,
        IPurchaseTracker purchaseTracker,
        uint256[] calldata claimedRewards
    ) external view returns (uint256[] memory);
    
    /**
     * @notice Calculate rewards for a specific user based on a checkpoint
     * @param token The token being distributed
     * @param user The user to calculate rewards for
     * @param purchaseTracker The tracker for purchase data
     * @param lastClaimedPurchases The number of purchases already claimed
     * @param lastClaimedSales The number of sales already claimed
     * @return The amount of rewards to distribute
     */
    function calculateUserRewards(
        address token,
        address user,
        IPurchaseTracker purchaseTracker,
        uint256 lastClaimedPurchases,
        uint256 lastClaimedSales
    ) external view returns (uint256);
}
