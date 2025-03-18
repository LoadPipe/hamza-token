// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@hamza-escrow/IPurchaseTracker.sol";
import "./ICommunityRewardsCalculator.sol";

/**
 * @title CommunityRewardsCalculator
 * @dev Contains the logic for calculating who gets what rewards, and for what reasons. The rewards are 
 * distributed through the CommunityVault. 
 */
contract CommunityRewardsCalculator is ICommunityRewardsCalculator {
    
    /**
     * @notice Legacy method for backwards compatibility
     */
    function getRewardsToDistribute(
        address /*token*/, 
        address[] calldata recipients,
        IPurchaseTracker purchaseTracker,
        uint256[] calldata claimedRewards
    ) external view returns (uint256[] memory) {
        require(recipients.length == claimedRewards.length, "Array lengths must match");
        uint256[] memory amounts = new uint256[](recipients.length);

        // for every purchase or sale made by the recipient, distribute 1 loot token
        for (uint i=0; i<recipients.length; i++) {
            uint256 totalPurchase = purchaseTracker.getPurchaseCount(recipients[i]);
            uint256 totalSales = purchaseTracker.getSalesCount(recipients[i]);
            uint256 totalRewards = totalPurchase + totalSales;
            
            // Subtract already claimed rewards to prevent double claiming
            if (totalRewards > claimedRewards[i]) {
                amounts[i] = totalRewards - claimedRewards[i];
            } else {
                amounts[i] = 0; // No new rewards to claim
            }
        }

        return amounts;
    }
    
    /**
     * @notice Calculate rewards for a single user based on their purchase/sales activity and checkpoint
     * @dev This is the newer, more gas-efficient implementation that works with checkpoints
     */
    function calculateUserRewards(
        address /*token*/,
        address user,
        IPurchaseTracker purchaseTracker,
        uint256 lastClaimedPurchases,
        uint256 lastClaimedSales
    ) external view returns (uint256) {
        // Get current purchase and sales counts
        uint256 currentPurchases = purchaseTracker.getPurchaseCount(user);
        uint256 currentSales = purchaseTracker.getSalesCount(user);
        
        // Calculate new (unclaimed) purchases and sales
        uint256 newPurchases = currentPurchases > lastClaimedPurchases ?
            currentPurchases - lastClaimedPurchases : 0;
            
        uint256 newSales = currentSales > lastClaimedSales ?
            currentSales - lastClaimedSales : 0;
        
        // Return the total rewards (1 token per purchase/sale)
        return newPurchases + newSales;
    }
}
