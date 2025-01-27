// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../scripts/DeployHamzaVault.s.sol";
import "../src/CommunityVault.sol";
import "../src/GovernanceVault.sol";
import "../src/tokens/GovernanceToken.sol";

/**
 * @dev Example Foundry test that deploys all contracts using DeployHamzaVault,
 *      then verifies deposits and rewards logic.
 */
contract FullRound is Test {
    DeployHamzaVault public script;

    // Addresses returned from the script
    address public baal;
    address payable public communityVault;
    address public govToken;
    address public govVault;
    address public safe;
    address public hatsCtx;

    // Extra fields from script
    uint256 public adminHatId;
    address public admin;
    address public lootToken;

    // A "normal user" who will do deposits (script.OWNER_ONE)
    address public user;

    function setUp() public {
        // Run the deployment script
        script = new DeployHamzaVault();

        (
            baal,
            communityVault,
            govToken,
            govVault,
            safe,
            hatsCtx
        ) = script.run();

        adminHatId = script.adminHatId();

        // The script sets OWNER_ONE as a constant
        admin = script.OWNER_ONE(); 
        user = script.OWNER_ONE();  // We'll treat OWNER_ONE as our "end-user" for demonstration

        // This is the loot token minted by the Baal
        lootToken = script.hamzaToken();
    }

    // Basic Test
    function testDeployment() public {
        assertTrue(baal != address(0), "Baal address is zero");
        assertTrue(communityVault != address(0), "CommunityVault address is zero");
        assertTrue(govToken != address(0), "GovernanceToken address is zero");
        assertTrue(govVault != address(0), "GovernanceVault address is zero");
        assertTrue(safe != address(0), "Safe address is zero");
        assertTrue(hatsCtx != address(0), "HatsSecurityContext address is zero");
        assertTrue(lootToken != address(0), "Loot token address is zero");
    }

    // End-to-End Flow: deposit + vest + distribute rewards
    function testVestingAndRewardsFlow() public {
        // Setup references
        CommunityVault cVault = CommunityVault(communityVault);
        GovernanceVault gVault = GovernanceVault(govVault);
        GovernanceToken gToken = GovernanceToken(govToken);
        IERC20 lToken = IERC20(lootToken);

        // Check user has loot tokens (script mints 50 to user)
        uint256 userLootBalance = lToken.balanceOf(user);
        console2.log("User's initial LOOT balance:", userLootBalance);
        assertEq(userLootBalance, 50, "User should have 50 LOOT initially.");

        // STEP 1: User deposits LOOT into GovernanceVault
        uint256 depositAmount = 20;

        vm.startPrank(user);
        lToken.approve(address(gVault), depositAmount);
        gVault.deposit(depositAmount); // This mints user 20 governance tokens
        vm.stopPrank();

        // Confirm deposit is recorded
        (uint256 dAmount, uint256 dStakedAt, bool dRewardsDist) = gVault.deposits(user, 0);
        assertEq(dAmount, depositAmount, "User's deposit amount mismatch");
        assertEq(dRewardsDist, false, "rewardsDistributed should be false initially");

        // Check user LOOT and GOV balances after deposit
        userLootBalance = lToken.balanceOf(user);
        uint256 userGovBalance = gToken.balanceOf(user);
        console2.log("User LOOT after deposit:", userLootBalance);
        console2.log("User GOV after deposit:", userGovBalance);

        assertEq(userLootBalance, 30, "User should have 30 LOOT left");
        assertEq(userGovBalance, 20, "User should have 20 GOV tokens minted");

        // STEP 2: Move time forward so deposit is fully vested
        skip(31); // skip 31 seconds

        // STEP 3: Distribute Rewards
        vm.prank(user);
        gVault.distributeRewards(user);

        // After distribution, deposit #0's rewardsDistributed becomes true
        (dAmount, , dRewardsDist) = gVault.deposits(user, 0);
        console2.log("User's original deposit after distribution:", dAmount);
        console2.log("rewardsDistributed for deposit #0:", dRewardsDist);
        assertTrue(dRewardsDist, "Original deposit's rewardsDistributed should now be true");

        // The totalReward = depositAmount = 20
        (uint256 rewardDepositAmt, , bool rewardDepositDist) = gVault.deposits(user, 1);
        console2.log("Reward deposit amount:", rewardDepositAmt);
        assertEq(rewardDepositAmt, 20, "Reward deposit should be equal to the original deposit");
        assertFalse(rewardDepositDist, "Reward deposit's rewardsDistributed should be false initially");

        // Also user now gets minted additional 20 GOV tokens
        userGovBalance = gToken.balanceOf(user);
        console2.log("User GOV after reward distribution:", userGovBalance);
        assertEq(userGovBalance, 40, "User GOV should be 40 now");
        userLootBalance = lToken.balanceOf(user);
        console2.log("User LOOT after reward distribution:", userLootBalance);

        // Check the CommunityVault LOOT was transferred out
        // The script minted 50 LOOT to CommunityVault, now it should have 30 left
        uint256 commVaultLootBalance = lToken.balanceOf(communityVault);
        console2.log("CommunityVault LOOT after distributing reward:", commVaultLootBalance);
        assertEq(commVaultLootBalance, 30, "CommunityVault should have 30 LOOT after distributing 20");

        // STEP 4: Attempt partial withdrawal
        // The user has two deposits in the vault:
        //    deposit #0: amount=20, vested, rewardsDistributed=true
        //    deposit #1: amount=20 (the reward deposit), stakedAt=block.timestamp (31s after original)
        // The second deposit is not yet vested because it's brand new. 
        // try to withdraw 10 tokens
        uint256 partialWithdrawAmount = 10;

        vm.startPrank(user);
        gVault.withdraw(partialWithdrawAmount);
        vm.stopPrank();

        // The oldest deposit (#0) had 20. We withdrew 10, so deposit #0 now has 10 left.
        (uint256 updatedDep0Amt,,) = gVault.deposits(user, 0);
        console2.log("Updated deposit #0 after partial withdraw:", updatedDep0Amt);
        assertEq(updatedDep0Amt, 10, "Deposit #0 should be reduced from 20 to 10");

        // The user burned 10 GOV tokens upon withdrawal, so GOV should be 30
        userGovBalance = gToken.balanceOf(user);
        console2.log("User GOV after partial withdraw:", userGovBalance);
        assertEq(userGovBalance, 30, "User should have burned 10 GOV, leaving 30");

        // The user gets 10 LOOT back
        userLootBalance = lToken.balanceOf(user);
        console2.log("User LOOT after partial withdraw:", userLootBalance);
        assertEq(userLootBalance, 40, "User LOOT should be 40 now (30 + 10 withdrawn)");

        // STEP 5: Wait for the reward deposit (#1) to vest, then do a full withdrawal
        skip(31); // skip 31 more seconds

        // Now deposit #1 is also fully vested. Let's withdraw everything left, i.e. 30 tokens:
        //   deposit #0 has 10 left
        //   deposit #1 has 20
        // total = 30
        vm.startPrank(user);

        // deposit count before withdraw
        uint256 initialDepositCount = getDepositCount(gVault, user);
        console2.log("User's initial deposit count:", initialDepositCount);

        gVault.withdraw(30);
        vm.stopPrank();

        // After withdrawing 30 more deposit count should drop to 1 (1 for reward restaking)
        uint256 depositCount = getDepositCount(gVault, user);
        console2.log("User's deposit count after final withdraw:", depositCount);
        assertEq(depositCount, 1, "One deposit should remain after withdrawing 30 total");

        // The user also burns 30 GOV tokens
        userGovBalance = gToken.balanceOf(user);
        console2.log("Final user GOV balance:", userGovBalance);
    
        assertEq(userGovBalance, 20, "User should have 20 GOV after final withdraw");

        // The user receives 30 LOOT in the final withdrawal
        userLootBalance = lToken.balanceOf(user);
        console2.log("Final user LOOT balance:", userLootBalance);
        // Previously 40, plus 30 = 70
        assertEq(userLootBalance, 70, "User should have 70 LOOT after final withdraw");

        console2.log("testVestingAndRewardsFlow completed successfully.");
    }

    /**
     * @dev Helper function to read how many deposits a user has in the GovernanceVault.
     */
    function getDepositCount(GovernanceVault gVault, address account) internal view returns (uint256) {
        uint256 count;
        try gVault.deposits(account, 0) returns (uint256, uint256, bool) {
            // deposit 0 exists
        } catch {
            return 0;
        }
        // If deposit(0) works keep going until it fails
        while (true) {
            try gVault.deposits(account, count) returns (uint256, uint256, bool) {
                count++;
            } catch {
                break;
            }
        }
        return count;
    }
}
