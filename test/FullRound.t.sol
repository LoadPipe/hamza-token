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
    function testRewardsFlow() public {
        // Setup references
        CommunityVault cVault = CommunityVault(communityVault);
        GovernanceVault gVault = GovernanceVault(govVault);
        GovernanceToken gToken = GovernanceToken(govToken);
        IERC20 lToken = IERC20(lootToken);

        // Check user has loot tokens (script mints 50 to user (OWNER_ONE))
        uint256 userLootBalance = lToken.balanceOf(user);
        console2.log("User's initial lootToken balance:", userLootBalance);
        assertEq(userLootBalance, 50, "User should have 50 loot tokens");


        //  The user deposits some loot into GovernanceVault
        uint256 depositAmount = 20;

        vm.startPrank(user); // act as user

        lToken.approve(address(gToken), depositAmount);

        // deposit 20 loot tokens user gets 20 GovTokens minted
        gVault.deposit(depositAmount);

        vm.stopPrank();

        // Check the deposit is recorded
        (uint256 depositedAmt,,) = gVault.deposits(user, 0);
        assertEq(depositedAmt, depositAmount, "Deposit record mismatch");

        // After deposit user should have 30 loot left
        userLootBalance = lToken.balanceOf(user);
        assertEq(userLootBalance, 30, "User should have 30 loot tokens left");

        // User also should have 20 GovTokens minted
        uint256 userGovBalance = gToken.balanceOf(user);
        console2.log("User's govToken balance after deposit:", userGovBalance);
        assertEq(userGovBalance, 20, "User's govToken minted mismatch");
        
        // (C) Warp forward in time so user can fully vest
        skip(31); // 31 seconds

        // Now if we call gVault.rewards(user it should reflect almost full deposit as reward

        uint256 pendingReward = gVault.rewards(user);
        console2.log("User's computed reward after 31s:", pendingReward);
        // Because deposit = 20, vesting = 30 seconds if 31s have passed reward = 20
        assertEq(pendingReward, 20, "Expected full deposit as reward");


        // (D) Distribute Rewards from the CommunityVault
        address[] memory stakers = new address[](1);
        stakers[0] = user;

        // user allows govToken to stake there reward loot token
        gVault.distributeRewardsMultiple(stakers);

        // Confirm the user now has 2 deposits in the gVault:
        //   - The original deposit of 20
        //   - The new deposit of 20 from rewards
        (uint256 dep1Amt,,) = gVault.deposits(user, 0);
        (uint256 dep2Amt,,) = gVault.deposits(user, 1);
        console2.log("User deposit #1:", dep1Amt);
        console2.log("User deposit #2 (reward deposit):", dep2Amt);
        // The second deposit should be 20
        assertEq(dep2Amt, 20, "Second deposit should be 20 from reward");

        // Also confirm the user's govToken balance went from 20 -> 40
        userGovBalance = gToken.balanceOf(user);
        console2.log("User's govToken balance after reward distribution:", userGovBalance);
        assertEq(userGovBalance, 40, "User govToken balance mismatch after reward distribution");

        // Confirm the CommunityVault's lootToken balance decreased by 20
        uint256 commVaultLoot = lToken.balanceOf(communityVault);
        console2.log("CommunityVault lootToken balance after distributing reward:", commVaultLoot);
        // Initially the script minted 50 loot to the vault. It's now 30
        // Because we pulled 20 in the reward distribution
        assertEq(commVaultLoot, 30, "CommunityVault should have 30 left");

        // ---------------------------------------------------
        // (E) Everything worked. 
        //     The user has 40 GovTokens total. 
        //     The user also can withdraw if they want.
        // ---------------------------------------------------
        console2.log("testRewardsFlow completed successfully.");
    }
}
