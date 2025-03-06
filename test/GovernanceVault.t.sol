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
}
