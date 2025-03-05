// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "../src/CommunityVault.sol";
import "../src/GovernanceVault.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/HamzaGovernor.sol";
import "../src/CustomBaal.sol";
import "@hamza-escrow/SystemSettings.sol";

import "./DeploymentSetup.t.sol";

/**
 * @dev FullRound contract tests
 */
contract FullRound is DeploymentSetup {

    // Basic deployment checks
    function testDeployment() public {
        assertTrue(baal != address(0),          "Baal address is zero");
        assertTrue(communityVault != address(0), "CommunityVault address is zero");
        assertTrue(govToken != address(0),       "GovernanceToken address is zero");
        assertTrue(govVault != address(0),       "GovernanceVault address is zero");
        assertTrue(safe != address(0),           "Safe address is zero");
        assertTrue(hatsCtx != address(0),        "HatsSecurityContext address is zero");
        assertTrue(lootToken != address(0),      "Loot token address is zero");

        // Check that the GovernanceVault's vestingPeriod matches config
        GovernanceVault gVault = GovernanceVault(govVault);
        uint256 actualVesting = gVault.vestingPeriodSeconds();
        assertEq(
            actualVesting,
            vestingPeriodFromConfig,
            "Vault vestingPeriod does not match config"
        );

        // Check that the SystemSettings feeBps matches config's initial setting
        SystemSettings sysSettings = SystemSettings(systemSettings);
        uint256 actualFeeBps = sysSettings.feeBps();
        assertEq(
            actualFeeBps,
            initialFeeBps,
            "System feeBps does not match config's initial feeBps"
        );

        // Ensure Baal correctly records the CommunityVault address
        CustomBaal baalContract = CustomBaal(baal);
        address recordedCommunityVault = baalContract.communityVault();
        assertEq(
            recordedCommunityVault,
            communityVault,
            "Baal's recorded CommunityVault does not match the deployed address"
        );
    }

    // End-to-End Flow: deposit + vest + distribute rewards
    function testVestingAndRewardsFlow() public {
        // Setup references
        CommunityVault cVault = CommunityVault(communityVault);
        GovernanceVault gVault = GovernanceVault(govVault);
        GovernanceToken gToken = GovernanceToken(govToken);
        IERC20 lToken = IERC20(lootToken);

        // Check user has LOOT tokens minted by Baal (from config "userLootAmount")
        uint256 userLootBalance = lToken.balanceOf(user);
        console2.log("User's initial LOOT balance:", userLootBalance);

        // The test expects the minted LOOT to match config
        assertEq(
            userLootBalance, 
            userLootAmountFromConfig, 
            "User's minted LOOT does not match config"
        );

        // STEP 1: User deposits LOOT into GovernanceVault
        // First check how much LOOT the community vault has for rewards
        uint256 communityVaultLootBalance = lToken.balanceOf(communityVault);
        console2.log("Community vault LOOT balance:", communityVaultLootBalance);
        
        // Choose a deposit amount that ensures the community vault has enough for rewards
        // We'll deposit at most half of what the community vault has, to ensure it can match
        uint256 depositAmount = communityVaultLootBalance > 0 
            ? Math.min(20*10**18, communityVaultLootBalance / 2) 
            : 20*10**18;
        
        console2.log("Deposit amount for test:", depositAmount);
        
        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        gVault.deposit(depositAmount); // This mints user GOV tokens equal to deposit
        vm.stopPrank();

        // Confirm deposit is recorded
        (uint256 dAmount, , bool dRewardsDist) = gVault.deposits(user, 0);
        assertEq(dAmount, depositAmount, "User's deposit amount mismatch");
        assertEq(dRewardsDist, false, "rewardsDistributed should be false initially");

        // Check user LOOT and GOV after deposit
        userLootBalance = lToken.balanceOf(user);
        uint256 userGovBalance = gToken.balanceOf(user);

        console2.log("User LOOT after deposit:", userLootBalance);
        console2.log("User GOV after deposit:", userGovBalance);

        // userLootAmountFromConfig was 50 in config; we've deposited 20
        assertEq(
            userLootBalance,
            userLootAmountFromConfig - depositAmount,
            "User LOOT after deposit mismatch"
        );
        assertEq(
            userGovBalance,
            depositAmount, 
            "User GOV balance mismatch after deposit"
        );

        // STEP 2: Move time forward so deposit is fully vested
        // We'll skip vestingPeriodFromConfig + 1 seconds
        skip(vestingPeriodFromConfig + 1);

        // STEP 3: Distribute Rewards
        vm.prank(user);
        gVault.distributeRewards(user);

        // After distribution, deposit #0's rewardsDistributed becomes true
        (dAmount, , dRewardsDist) = gVault.deposits(user, 0);
        assertTrue(dRewardsDist, "Original deposit's rewardsDistributed should now be true");

        // The totalReward = depositAmount
        (uint256 rewardDepositAmt, , bool rewardDepositDist) = gVault.deposits(user, 1);
        console2.log("Reward deposit amount:", rewardDepositAmt);
        assertEq(rewardDepositAmt, depositAmount, "Reward deposit should be equal to the original deposit");
        assertFalse(rewardDepositDist, "Reward deposit's rewardsDistributed should be false initially");

        // User also gets minted additional depositAmount GOV tokens
        uint256 userGovBalanceAfterReward = gToken.balanceOf(user);
        console2.log("User GOV after reward distribution:", userGovBalanceAfterReward);
        assertEq(userGovBalanceAfterReward, userGovBalance + depositAmount, "User GOV should be doubled after reward distribution");

        uint256 userLootBalanceAfterReward = lToken.balanceOf(user);
        console2.log("User LOOT after reward distribution:", userLootBalanceAfterReward);

        // Check the community vault's LOOT balance after distributing rewards
        uint256 commVaultLootBalance = lToken.balanceOf(communityVault);
        console2.log("CommunityVault LOOT after distributing reward:", commVaultLootBalance);
        assertEq(commVaultLootBalance, vaultLootAmountFromConfig - depositAmount, "CommunityVault should have reduced LOOT after distributing reward");

        // STEP 4: Attempt partial withdrawal of half the original deposit
        uint256 partialWithdrawAmount = depositAmount / 2;
        vm.startPrank(user);
        gVault.withdraw(partialWithdrawAmount);
        vm.stopPrank();

        // The oldest deposit (#0) should be reduced by the partial withdrawal amount
        (uint256 updatedDep0Amt,,) = gVault.deposits(user, 0);
        console2.log("Updated deposit #0 after partial withdraw:", updatedDep0Amt);
        assertEq(updatedDep0Amt, depositAmount - partialWithdrawAmount, "Deposit #0 should be reduced by withdrawal amount");

        // The user burned GOV tokens upon withdrawal
        uint256 userGovBalanceAfterPartialWithdraw = gToken.balanceOf(user);
        console2.log("User GOV after partial withdraw:", userGovBalanceAfterPartialWithdraw);
        assertEq(userGovBalanceAfterPartialWithdraw, userGovBalanceAfterReward - partialWithdrawAmount, "User GOV should be reduced by withdrawal amount");

        // The user gets LOOT back
        uint256 userLootBalanceAfterPartialWithdraw = lToken.balanceOf(user);
        console2.log("User LOOT after partial withdraw:", userLootBalanceAfterPartialWithdraw);
        assertEq(userLootBalanceAfterPartialWithdraw, userLootBalanceAfterReward + partialWithdrawAmount, "User LOOT should increase by withdrawal amount");

        // STEP 5: Wait for the reward deposit (#1) to vest, then do a full withdrawal
        skip(vestingPeriodFromConfig + 1);

        // Calculate remaining deposits (deposit #0 remainder + deposit #1)
        uint256 remainingDeposits = (depositAmount - partialWithdrawAmount) + depositAmount;
        
        vm.startPrank(user);

        uint256 initialDepositCount = getDepositCount(gVault, user);
        console2.log("User's initial deposit count:", initialDepositCount);
        // Get the current balance of user's governance tokens before final withdrawal
        uint256 userGovBalanceBeforeFinalWithdraw = gToken.balanceOf(user);
        console2.log("User GOV balance before final withdraw:", userGovBalanceBeforeFinalWithdraw);

        // Withdraw all remaining deposits
        gVault.withdraw(remainingDeposits);

        vm.stopPrank();

        // deposit count after withdraw
        uint256 depositCount = getDepositCount(gVault, user);
        console2.log("User's deposit count after final withdraw:", depositCount);
        assertEq(depositCount, 1, "One deposit stub might remain after clearing these deposits");

        // The user also burns GOV tokens
        uint256 userGovBalanceAfterFinalWithdraw = gToken.balanceOf(user);
        console2.log("Final user GOV balance:", userGovBalanceAfterFinalWithdraw);
        assertEq(userGovBalanceAfterFinalWithdraw, userGovBalanceAfterPartialWithdraw - remainingDeposits + depositAmount, "User GOV should be reduced by final withdrawal amount");

        // The user receives LOOT
        uint256 userLootBalanceAfterFinalWithdraw = lToken.balanceOf(user);
        console2.log("Final user LOOT balance:", userLootBalanceAfterFinalWithdraw);
        assertEq(userLootBalanceAfterFinalWithdraw, userLootBalanceAfterPartialWithdraw + remainingDeposits, "User LOOT should increase by final withdrawal amount");

        // Voting flow: 
        HamzaGovernor gov = HamzaGovernor(governor);
        vm.startPrank(user);
        
        address[] memory targets = new address[](1);
        targets[0] = systemSettings;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        // Propose to change feeBps from 0 => 1
        calldatas[0] = abi.encodeWithSignature("setFeeBps(uint256)", 1);

        uint256 proposal = gov.propose(targets, values, calldatas, "Test proposal");
        console2.log("Proposal ID:", proposal);
        assertGt(proposal, 0, "Proposal ID should be greater than 0");

        // Move time forward to activate voting
        vm.roll(block.number + 2);

        // Check proposal state
        uint256 state = uint256(gov.state(proposal));
        console2.log("Proposal state:", state);
        assertEq(state, uint256(ProposalState.Active), "Proposal should be active");

        // Vote for the proposal
        gov.castVote(proposal, 1);

        // Move time forward
        vm.roll(block.number + 50401);

        // Check the user's voting power
        uint256 votes = gToken.getVotes(user);
        console2.log("Voting power:", votes);
        assertEq(votes, userGovBalanceAfterFinalWithdraw, "Voting power should match user's GOV balance");

        // The proposal should have succeeded
        state = uint256(gov.state(proposal));
        console2.log("Proposal state after voting:", state);
        assertEq(state, uint256(ProposalState.Succeeded), "Proposal should have succeeded");

        // Queue and execute the proposal
        gov.queue(targets, values, calldatas, keccak256("Test proposal"));
        vm.warp(block.timestamp + timeLockDelay + 1);
        gov.execute(targets, values, calldatas, keccak256("Test proposal"));

        // Check the proposal state
        state = uint256(gov.state(proposal));
        console2.log("Proposal state after execution:", state);
        assertEq(state, uint256(ProposalState.Executed), "Proposal should be executed");

        // Check the SystemSettings now has feeBps = 1
        SystemSettings sysSettings = SystemSettings(systemSettings);
        console2.log("Fee basis points:", sysSettings.feeBps());
        assertEq(sysSettings.feeBps(), 1, "Fee basis points should be 1 after proposal");
    }
}
