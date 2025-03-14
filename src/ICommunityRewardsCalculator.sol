// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@hamza-escrow/IPurchaseTracker.sol";

/**
 * @title ICommunityRewardsCalculator
 * @dev Defines the logic for calculating who gets what rewards, and for what reasons. The rewards are 
 * distributed through the CommunityVault. 
 */
interface ICommunityRewardsCalculator {
    function getRewardsToDistribute(
        address token, 
        address[] calldata recipients,
        IPurchaseTracker purchaseTracker,
        uint256[] calldata claimedRewards
    ) external view returns (uint256[] memory);
}
