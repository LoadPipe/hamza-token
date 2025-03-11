// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@hamza-escrow/IPurchaseTracker.sol";

interface ICommunityRewardsCalculator {
    function getRewardsToDistribute(
        address token, 
        address[] calldata recipients,
        IPurchaseTracker purchaseTracker
    ) external returns (uint256[] memory);
}

/**
 * @title CommunityRewardsCalculator
 * @dev Contains the logic for calculating who gets what rewards, and for what reasons. The rewards are 
 * distributed through the CommunityVault. 
 */
contract CommunityRewardsCalculator is ICommunityRewardsCalculator {
    
    function getRewardsToDistribute(
        address token, 
        address[] calldata recipients,
        IPurchaseTracker purchaseTracker
    ) external returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](recipients.length);

        // for every purchase or sale made by the recipient, distribute 1 loot token
        for (uint i=0; i<recipients.length; i++) {
            uint256 totalPurchase = purchaseTracker.getPurchaseCount(recipients[i]);
            uint256 totalSales = purchaseTracker.getSalesAmount(recipients[i]);
            uint256 totalRewards = totalPurchase + totalSales;
            amounts[i] = totalRewards;
        }

        return amounts;
    }
}
