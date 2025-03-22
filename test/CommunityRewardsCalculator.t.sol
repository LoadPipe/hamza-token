// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "./DeploymentSetup.t.sol";
import "../src/CommunityRewardsCalculator.sol";
import "../src/PurchaseTracker.sol";
import "../src/ICommunityRewardsCalculator.sol";
import "@hamza-escrow/IPurchaseTracker.sol";

contract MockPurchaseTracker {
    mapping(address => uint256) private purchaseCounts;
    mapping(address => uint256) private salesCounts;
    
    function setPurchaseCount(address user, uint256 count) external {
        purchaseCounts[user] = count;
    }
    
    function setSalesCount(address user, uint256 count) external {
        salesCounts[user] = count;
    }
    
    function getPurchaseCount(address user) external view returns (uint256) {
        return purchaseCounts[user];
    }
    
    function getSalesCount(address user) external view returns (uint256) {
        return salesCounts[user];
    }
}

contract CommunityRewardsCalculatorTest is DeploymentSetup {
    using stdJson for string;
    
    // Test-specific variables
    CommunityRewardsCalculator private calculator;
    MockPurchaseTracker private mockTracker;
    
    // Test users
    address private user1;
    address private user2;
    address private user3;
    
    function setUp() public override {
        // Call the parent setup which deploys all contracts
        super.setUp();
        
        // Deploy a new calculator for isolated testing
        calculator = new CommunityRewardsCalculator();
        
        // Deploy a mock purchase tracker to control test scenarios
        mockTracker = new MockPurchaseTracker();
        
        // Setup test users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
    }
    
    // Test legacy getRewardsToDistribute method with single user
    function testGetRewardsToDistributeSingleUser() public {
        // Setup purchase and sales for user1
        mockTracker.setPurchaseCount(user1, 5);
        mockTracker.setSalesCount(user1, 3);
        
        // Create arrays for inputs
        address[] memory recipients = new address[](1);
        recipients[0] = user1;
        
        uint256[] memory claimedRewards = new uint256[](1);
        claimedRewards[0] = 0; // No previously claimed rewards
        
        // Calculate rewards
        uint256[] memory rewards = calculator.getRewardsToDistribute(
            lootToken, 
            recipients, 
            IPurchaseTracker(address(mockTracker)), 
            claimedRewards
        );
        
        // Assert correct rewards calculation: 5 purchases + 3 sales = 8 tokens
        assertEq(rewards[0], 8);
    }
    
    // Test legacy method with multiple users
    function testGetRewardsToDistributeMultipleUsers() public {
        // Setup purchase and sales counts
        mockTracker.setPurchaseCount(user1, 5);
        mockTracker.setSalesCount(user1, 3);
        
        mockTracker.setPurchaseCount(user2, 10);
        mockTracker.setSalesCount(user2, 2);
        
        mockTracker.setPurchaseCount(user3, 0);
        mockTracker.setSalesCount(user3, 7);
        
        // Create arrays for inputs
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        
        uint256[] memory claimedRewards = new uint256[](3);
        claimedRewards[0] = 0; // No previously claimed rewards
        claimedRewards[1] = 5; // Some previously claimed rewards
        claimedRewards[2] = 10; // More claimed than earned (edge case)
        
        // Calculate rewards
        uint256[] memory rewards = calculator.getRewardsToDistribute(
            lootToken, 
            recipients, 
            IPurchaseTracker(address(mockTracker)), 
            claimedRewards
        );
        
        // Assert correct rewards calculations
        assertEq(rewards[0], 8);  // 5 purchases + 3 sales = 8 tokens
        assertEq(rewards[1], 7);  // 10 purchases + 2 sales - 5 claimed = 7 tokens
        assertEq(rewards[2], 0);  // 0 purchases + 7 sales = 7 tokens, but 10 claimed, so 0 rewards
    }
    
    // Test that arrays must be the same length
    function testGetRewardsToDistributeWithUnequalArrayLengths() public {
        // Create arrays with different lengths
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;
        
        uint256[] memory claimedRewards = new uint256[](1);
        claimedRewards[0] = 0;
        
        // Expect the function to revert
        vm.expectRevert("Array lengths must match");
        calculator.getRewardsToDistribute(
            lootToken, 
            recipients, 
            IPurchaseTracker(address(mockTracker)), 
            claimedRewards
        );
    }
    
    // Test the newer, more gas-efficient calculateUserRewards method
    function testCalculateUserRewardsNoCheckpoint() public {
        // Setup purchase and sales for user1
        mockTracker.setPurchaseCount(user1, 5);
        mockTracker.setSalesCount(user1, 3);
        
        // Calculate rewards with no previous claims
        uint256 rewards = calculator.calculateUserRewards(
            lootToken,
            user1,
            IPurchaseTracker(address(mockTracker)),
            0, // lastClaimedPurchases
            0  // lastClaimedSales
        );
        
        // Assert correct rewards calculation: 5 purchases + 3 sales = 8 tokens
        assertEq(rewards, 8);
    }
    
    // Test calculateUserRewards with existing checkpoints
    function testCalculateUserRewardsWithCheckpoints() public {
        // Setup purchase and sales for user1
        mockTracker.setPurchaseCount(user1, 10);
        mockTracker.setSalesCount(user1, 7);
        
        // Calculate rewards with previous claims
        uint256 rewards = calculator.calculateUserRewards(
            lootToken,
            user1,
            IPurchaseTracker(address(mockTracker)),
            3, // lastClaimedPurchases
            2  // lastClaimedSales
        );
        
        // Assert correct rewards calculation: (10-3) purchases + (7-2) sales = 12 tokens
        assertEq(rewards, 12);
    }
    
    // Test calculateUserRewards when current counts are less than checkpoints (edge case)
    function testCalculateUserRewardsWithCheckpointsHigherThanCurrent() public {
        // Setup purchase and sales less than checkpoints
        mockTracker.setPurchaseCount(user1, 2);
        mockTracker.setSalesCount(user1, 1);
        
        // Calculate rewards with higher previous claims (simulating a reset or data issue)
        uint256 rewards = calculator.calculateUserRewards(
            lootToken,
            user1,
            IPurchaseTracker(address(mockTracker)),
            5, // lastClaimedPurchases higher than current
            3  // lastClaimedSales higher than current
        );
        
        // Assert zero rewards since current < checkpoint
        assertEq(rewards, 0);
    }
    
    // Test with mix of purchases and sales, some above checkpoint and some below
    function testCalculateUserRewardsMixedCheckpoints() public {
        // Setup purchase and sales
        mockTracker.setPurchaseCount(user1, 10);
        mockTracker.setSalesCount(user1, 3); // Less than checkpoint
        
        // Calculate rewards with mixed checkpoints
        uint256 rewards = calculator.calculateUserRewards(
            lootToken,
            user1,
            IPurchaseTracker(address(mockTracker)),
            5,  // lastClaimedPurchases less than current
            5   // lastClaimedSales higher than current
        );
        
        // Assert correct rewards: (10-5) purchases + 0 sales = 5 tokens
        assertEq(rewards, 5);
    }
    
    // Test with zero purchases and sales
    function testCalculateUserRewardsZeroCounts() public {
        // Setup zero purchase and sales
        mockTracker.setPurchaseCount(user1, 0);
        mockTracker.setSalesCount(user1, 0);
        
        // Calculate rewards
        uint256 rewards = calculator.calculateUserRewards(
            lootToken,
            user1,
            IPurchaseTracker(address(mockTracker)),
            0, // lastClaimedPurchases
            0  // lastClaimedSales
        );
        
        // Assert zero rewards
        assertEq(rewards, 0);
    }
    
    // Test with large numbers to ensure no overflows
    function testCalculateUserRewardsLargeNumbers() public {
        // Setup large purchase and sales counts
        mockTracker.setPurchaseCount(user1, 10000);
        mockTracker.setSalesCount(user1, 20000);
        
        // Calculate rewards with previous large claims
        uint256 rewards = calculator.calculateUserRewards(
            lootToken,
            user1,
            IPurchaseTracker(address(mockTracker)),
            9000,  // lastClaimedPurchases
            15000  // lastClaimedSales
        );
        
        // Assert correct rewards: (10000-9000) purchases + (20000-15000) sales = 6000 tokens
        assertEq(rewards, 6000);
    }
} 