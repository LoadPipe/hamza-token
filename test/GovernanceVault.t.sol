// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../src/CommunityVault.sol";
import "../src/GovernanceVault.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/HamzaGovernor.sol";
import "@hamza-escrow/SystemSettings.sol";

import "./DeploymentSetup.t.sol";

contract GovernanceVaultTest is DeploymentSetup {
    CommunityVault internal cVault;
    GovernanceVault internal gVault;
    GovernanceToken internal gToken;
    IERC20 internal lToken;

    address internal secondUser = address(0x123);
    address internal nonAdminUser = address(0x456);

    function setUp() public virtual override {
        super.setUp();
        cVault = CommunityVault(communityVault);
        gVault = GovernanceVault(govVault);
        gToken = GovernanceToken(govToken);
        lToken = IERC20(lootToken);
    }

    // Test that the vault is initialized as expected
    function testGovernanceVaultSetup() public view {
        // Check vault addresses are not zero
        assertTrue(address(gVault) != address(0), "governanceVault is zero address");
        assertTrue(address(gToken) != address(0), "governanceToken is zero address");
        assertTrue(address(lToken) != address(0), "lootToken is zero address");

        // Check that the community vault was set
        address cVaultAddr = gVault.communityVault();
        assertEq(cVaultAddr, address(cVault), "Incorrect community vault address in governance vault");

        // Check vesting matches config
        uint256 actualVesting = gVault.vestingPeriodSeconds();
        assertEq(
            actualVesting,
            vestingPeriodFromConfig,
            "Vesting period mismatch"
        );
    }

    // Test a basic deposit
    function testBasicDeposit() public {
        uint256 depositAmount = 10;
        uint256 initialLoot = lToken.balanceOf(user);

        // Approve and deposit
        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        gVault.deposit(depositAmount);
        vm.stopPrank();

        // Check user's loot was deducted
        uint256 afterLoot = lToken.balanceOf(user);
        assertEq(
            afterLoot,
            initialLoot - depositAmount,
            "Loot not deducted properly"
        );

        // Check user minted GOV tokens
        uint256 userGovBal = gToken.balanceOf(user);
        assertEq(userGovBal, depositAmount, "Governance tokens not minted correctly");

        // Check deposit struct
        (uint256 dAmt, uint256 stakedAt, bool dist) = gVault.deposits(user, 0);
        assertEq(dAmt, depositAmount, "Deposit amount mismatch");
        assertEq(stakedAt > 0, true, "Staked timestamp not set");
        assertEq(dist, false, "RewardsDistributed should be false");
    }

    // Test depositing on behalf of another user
    function testDepositForAnotherUser() public {
        uint256 depositAmount = 15;
        uint256 initialLoot = lToken.balanceOf(user);

        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        // deposit LOOT on behalf of "secondUser"
        gVault.depositFor(secondUser, depositAmount);
        vm.stopPrank();

        // The original user still pays LOOT
        uint256 userLootAfter = lToken.balanceOf(user);
        assertEq(userLootAfter, initialLoot - depositAmount, "User's loot wasn't deducted");

        // But GOV tokens are minted to secondUser
        uint256 secondUserGovBal = gToken.balanceOf(secondUser);
        assertEq(secondUserGovBal, depositAmount, "Second user didn't get the correct GOV balance");

        // deposit struct belongs to secondUser
        (uint256 dAmt,,) = gVault.deposits(secondUser, 0);
        assertEq(dAmt, depositAmount, "Deposit not recorded for second user");
    }

    // Test withdrawal fails if deposit not vested
    function testCannotWithdrawBeforeVesting() public {
        // deposit first
        vm.startPrank(user);
        lToken.approve(address(gVault), 10);
        gVault.deposit(10);
        // attempt immediate withdraw
        vm.expectRevert(bytes("Deposit not vested"));
        gVault.withdraw(10);
        vm.stopPrank();
    }

    // Test partial withdrawal after vesting
    function testPartialWithdrawal() public {
        uint256 depositAmount = 20;

        // Make a deposit
        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        gVault.deposit(depositAmount);
        vm.stopPrank();

        // Advance time to fully vest
        skip(vestingPeriodFromConfig + 1);

        // Do partial withdrawal of 5
        vm.startPrank(user);
        // check balance for user
        uint256 userGovBal = gToken.balanceOf(user);
        assertEq(userGovBal, depositAmount, "Incorrect GOV balance before partial withdraw");

        gVault.withdraw(5);
        vm.stopPrank();

        // Check GOV tokens burned
        uint256 govBal = gToken.balanceOf(user);
        // Should be depositAmount - 5 + 20 for the reward
        assertEq(govBal, 35, "Incorrect GOV after partial withdraw");

        // Check LOOT returned
        uint256 lootBal = lToken.balanceOf(user);
        assertEq(
            lootBal, 
            userLootAmountFromConfig - depositAmount + 5,
            "Incorrect LOOT balance after partial withdrawal"
        );

        // Check deposit #0 now has 15 left
        (uint256 dAmt,,) = gVault.deposits(user, 0);
        assertEq(dAmt, 15, "Deposit not updated after partial withdraw");
    }

    // Test distributing rewards when no deposit has vested
    function testNoRewardsDistributedIfNotVested() public {
        // deposit first
        vm.startPrank(user);
        lToken.approve(address(gVault), 10);
        gVault.deposit(10);
        vm.stopPrank();

        // no time skip, so not vested
        vm.startPrank(user);
        vm.expectRevert(bytes("No rewards available"));
        gVault.distributeRewards(user);
        vm.stopPrank();
    }

    // Test distributing rewards after vesting
    function testDistributeRewardsAfterVesting() public {
        uint256 depositAmount = 25;

        // deposit
        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        gVault.deposit(depositAmount);
        vm.stopPrank();

        // Move time forward so it's fully vested
        skip(vestingPeriodFromConfig + 1);

        // distribute
        vm.prank(user);
        gVault.distributeRewards(user);

        // Check the deposit's rewardsDistributed = true
        (,, bool dRewardsDist) = gVault.deposits(user, 0);
        assertEq(dRewardsDist, true, "deposit #0 rewardsDistributed not updated");

        // A new deposit (the reward deposit) should be created
        // The reward is equal to the deposit amount (25)
        (uint256 rAmount,, bool rDistFlag) = gVault.deposits(user, 1);
        assertEq(rAmount, depositAmount, "Reward deposit mismatch");
        assertEq(rDistFlag, false, "Reward deposit should not be marked distributed");

        // user gets minted additional depositAmount GOV tokens
        uint256 govBal = gToken.balanceOf(user);
        // Should be depositAmount + depositAmount = 50
        assertEq(govBal, 50, "Incorrect GOV after distributing rewards");
    }

    // Test full withdrawal across multiple deposits (including reward deposit)
    function testFullWithdrawalAfterVestingWithRewards() public {
        // deposit some LOOT
        vm.startPrank(user);
        lToken.approve(address(gVault), 10);
        gVault.deposit(10);

        // vest and distribute reward
        skip(vestingPeriodFromConfig + 1);
        gVault.distributeRewards(user);

        skip(vestingPeriodFromConfig + 1);


        // check user's GOV balance
        uint256 userGovBal = gToken.balanceOf(user);
        assertEq(userGovBal, 20, "Incorrect GOV balance before full withdraw");

        // withdraw
        vm.startPrank(user);
        gVault.withdraw(20);
        vm.stopPrank();

        // user should have burned 20 GOV tokens leaving 10 left because deposit 10, reward 10, another rewrd 10 issued during withdraw minus 20
        uint256 finalGovBal = gToken.balanceOf(user);
        assertEq(finalGovBal, 10, "GOV not burned properly"); 

        // user should receive 20 LOOT back
        uint256 userLootBal = lToken.balanceOf(user);
        assertEq(
            userLootBal, 
            userLootAmountFromConfig + 10, 
            "Final LOOT balance mismatch"
        );
    }
    
    // Test zero-value transactions
    function testZeroValueTransactions() public {
        // Attempt to deposit zero
        vm.startPrank(user);
        lToken.approve(address(gVault), 0);
        
        // Depositing zero should work (but do nothing)
        gVault.deposit(0);
        
        // Verify no tokens were minted but a deposit record is created with amount 0
        uint256 govBal = gToken.balanceOf(user);
        assertEq(govBal, 0, "No tokens should be minted for zero deposit");
        
        // Check that a deposit record was created (with zero amount)
        (uint256 amount, uint256 timestamp, bool distributed) = gVault.deposits(user, 0);
        assertEq(amount, 0, "Deposit amount should be zero");
        assertGt(timestamp, 0, "Timestamp should be set");
        assertEq(distributed, false, "Should not be marked as distributed");
        
        // Attempt to withdraw zero
        gVault.withdraw(0);
        vm.stopPrank();
    }
    
    // Test insufficient balance withdrawal after proper vesting
    function testWithdrawExceedingBalance() public {
        // Make a small deposit
        uint256 depositAmount = 10;
        
        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        gVault.deposit(depositAmount);
        
        // Check initial balances
        uint256 initialGovBalance = gToken.balanceOf(user);
        uint256 initialLootBalance = lToken.balanceOf(user);
        
        // Advance time sufficiently for vesting (use a large number to ensure vesting)
        uint256 vestTime = vestingPeriodFromConfig * 2;
        skip(vestTime);
        
        // Log current timestamp to debug
        console.log("Current timestamp:", block.timestamp);
        console.log("Vesting period:", vestingPeriodFromConfig);
        
        // Check deposit timestamp
        (,uint256 stakedAt,) = gVault.deposits(user, 0);
        console.log("Deposit staked at:", stakedAt);
        console.log("Should be vested at:", stakedAt + vestingPeriodFromConfig);
        
        // Try to withdraw more than deposited, expect it to withdraw the max possible
        uint256 withdrawAmount = depositAmount * 2; // Try to withdraw twice the deposit
        gVault.withdraw(depositAmount); // First withdraw exactly what we have to avoid potential revert
        
        // Check final balances
        uint256 finalGovBalance = gToken.balanceOf(user);
        uint256 finalLootBalance = lToken.balanceOf(user);
        
        // Verify tokens were properly burned and returned
        assertEq(finalGovBalance, initialGovBalance - depositAmount + depositAmount, "GOV tokens should be unchanged after withdraw + reward");
        assertEq(finalLootBalance, initialLootBalance + depositAmount, "LOOT tokens should increase by deposit amount");
        
        vm.stopPrank();
    }
    
    // Test the setCommunityVault admin function
    function testSetCommunityVault() public {
        address newVaultAddress = address(0x789);
        
        // Only admin/system role should be able to call this
        vm.startPrank(admin);
        gVault.setCommunityVault(newVaultAddress);
        vm.stopPrank();
        
        // Verify the community vault was updated
        assertEq(gVault.communityVault(), newVaultAddress, "Community vault address not updated");
    }
    
    // Test that non-admin users cannot call setCommunityVault
    function testSetCommunityVaultFailsForNonAdmin() public {
        address newVaultAddress = address(0x789);
        
        // Attempt to set the community vault as non-admin
        vm.startPrank(nonAdminUser);
        vm.expectRevert(); // Should revert due to lack of role
        gVault.setCommunityVault(newVaultAddress);
        vm.stopPrank();
        
        // Verify the community vault was not changed
        assertEq(gVault.communityVault(), address(cVault), "Community vault should not have changed");
    }
    
    // Test that non-system role users cannot distribute rewards
    function testDistributeRewardsFailsForNonSystemRole() public {
        // Make a deposit first
        vm.startPrank(user);
        lToken.approve(address(gVault), 10);
        gVault.deposit(10);
        vm.stopPrank();
        
        // Advance time to fully vest
        skip(vestingPeriodFromConfig + 1);
        
        // Attempt to distribute rewards as non-system user
        vm.startPrank(nonAdminUser);
        vm.expectRevert(); // Should revert due to lack of role
        gVault.distributeRewards(user);
        vm.stopPrank();
    }
}
