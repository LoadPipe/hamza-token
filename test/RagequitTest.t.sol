// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./DeploymentSetup.t.sol";
import "../src/CustomBaal.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev RagequitTest contract to test the ragequit functionality of the Baal DAO
 */
contract RagequitTest is DeploymentSetup {
    
    // Test ragequit with ETH
    function testRagequitWithEth() public {
        // Get the Baal contract instance
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get the user's initial loot balance
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        console2.log("User's initial LOOT balance:", initialLootBalance);
        
        // Calculate how much loot to burn (half of the user's balance)
        uint256 lootToBurn = initialLootBalance / 2;
        console2.log("LOOT to burn:", lootToBurn);
        
        // Get the initial total supply of shares and loot
        uint256 initialTotalSupply = baalContract.totalSupply();
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        
        // Send 10 ETH to the Baal avatar (Safe)
        vm.deal(address(this), 10 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 10 ether}("");
        require(success, "ETH transfer to Baal avatar failed");
        
        // Verify the ETH balance of the Baal avatar
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar ETH balance:", avatarEthBalance);
        
        // Calculate expected ETH return based on proportion
        uint256 expectedEthReturn = (lootToBurn * avatarEthBalance) / initialTotalSupply;
        console2.log("Expected ETH return:", expectedEthReturn);
        
        // Record user's initial ETH balance
        uint256 initialUserEthBalance = user.balance;
        console2.log("User's initial ETH balance:", initialUserEthBalance);
        
        // Execute ragequit as the user
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH reference
        
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens); // Burn loot only, not shares
        vm.stopPrank();
        
        // Verify user's new loot balance
        uint256 newLootBalance = IERC20(lootToken).balanceOf(user);
        console2.log("User's new LOOT balance:", newLootBalance);
        assertEq(newLootBalance, initialLootBalance - lootToBurn, "Incorrect loot balance after ragequit");
        
        // Verify user received ETH
        uint256 newUserEthBalance = user.balance;
        console2.log("User's new ETH balance:", newUserEthBalance);
        assertEq(newUserEthBalance, initialUserEthBalance + expectedEthReturn, "User did not receive the correct amount of ETH");
        
        // Verify the Baal avatar's ETH balance is reduced
        uint256 newAvatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar new ETH balance:", newAvatarEthBalance);
        assertEq(newAvatarEthBalance, avatarEthBalance - expectedEthReturn, "Avatar ETH balance not reduced correctly");
    }
    
    // Test ragequit with both shares and loot
    function testRagequitWithSharesAndLoot() public {
        // Get the Baal contract instance
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get initial balances
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        uint256 initialSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(user);
        console2.log("User's initial LOOT balance:", initialLootBalance);
        console2.log("User's initial SHARES balance:", initialSharesBalance);
        
        // Calculate how much to burn (25% of each)
        uint256 lootToBurn = initialLootBalance / 4;
        uint256 sharesToBurn = initialSharesBalance / 4;
        console2.log("LOOT to burn:", lootToBurn);
        console2.log("SHARES to burn:", sharesToBurn);
        
        // Get the initial total supply of shares and loot
        uint256 initialTotalSupply = baalContract.totalSupply();
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        
        // Send 5 ETH to the Baal avatar (Safe)
        vm.deal(address(this), 5 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 5 ether}("");
        require(success, "ETH transfer to Baal avatar failed");
        
        // Also send some ERC20 tokens if needed for a more comprehensive test
        // (I'll skip this for now, since we're focusing on ETH)
        
        // Verify the ETH balance of the Baal avatar
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar ETH balance:", avatarEthBalance);
        
        // Calculate expected ETH return based on proportion
        uint256 expectedEthReturn = ((lootToBurn + sharesToBurn) * avatarEthBalance) / initialTotalSupply;
        console2.log("Expected ETH return:", expectedEthReturn);
        
        // Record user's initial ETH balance
        uint256 initialUserEthBalance = user.balance;
        console2.log("User's initial ETH balance:", initialUserEthBalance);
        
        // Execute ragequit as the user
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH reference
        
        vm.startPrank(user);
        baalContract.ragequit(user, sharesToBurn, lootToBurn, tokens);
        vm.stopPrank();
        
        // Verify user's new balances
        uint256 newLootBalance = IERC20(lootToken).balanceOf(user);
        uint256 newSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(user);
        console2.log("User's new LOOT balance:", newLootBalance);
        console2.log("User's new SHARES balance:", newSharesBalance);
        
        assertEq(newLootBalance, initialLootBalance - lootToBurn, "Incorrect loot balance after ragequit");
        assertEq(newSharesBalance, initialSharesBalance - sharesToBurn, "Incorrect shares balance after ragequit");
        
        // Verify user received ETH
        uint256 newUserEthBalance = user.balance;
        console2.log("User's new ETH balance:", newUserEthBalance);
        assertEq(newUserEthBalance, initialUserEthBalance + expectedEthReturn, "User did not receive the correct amount of ETH");
        
        // Verify the Baal avatar's ETH balance is reduced
        uint256 newAvatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar new ETH balance:", newAvatarEthBalance);
        assertEq(newAvatarEthBalance, avatarEthBalance - expectedEthReturn, "Avatar ETH balance not reduced correctly");
    }
    
    // Test ragequit with community vault balance exclusion
    function testRagequitWithCommunityVaultExclusion() public {
        // Get the Baal contract instance
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get initial loot balance
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        console2.log("User's initial LOOT balance:", initialLootBalance);
        
        // Calculate how much to burn (half)
        uint256 lootToBurn = initialLootBalance / 2;
        console2.log("LOOT to burn:", lootToBurn);
        
        // Get the initial total supply of shares and loot
        uint256 initialTotalSupply = baalContract.totalSupply();
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        
        // Send 8 ETH to the Baal avatar
        vm.deal(address(this), 10 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 8 ether}("");
        require(success, "ETH transfer to Baal avatar failed");
        
        // Send 2 ETH to the community vault
        (success, ) = payable(communityVault).call{value: 2 ether}("");
        require(success, "ETH transfer to community vault failed");
        
        // Verify balances
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        uint256 vaultEthBalance = address(communityVault).balance;
        console2.log("Baal avatar ETH balance:", avatarEthBalance);
        console2.log("Community vault ETH balance:", vaultEthBalance);
        
        // Record initial user ETH balance
        uint256 initialUserEthBalance = user.balance;
        console2.log("User's initial ETH balance:", initialUserEthBalance);
        
        // Calculate expected ETH return based on CustomBaal's _ragequit implementation:
        // It subtracts the community vault balance from the DAO's balance before calculating
        uint256 adjustedBalance = avatarEthBalance; // This is the DAO balance
        // The vault balance isn't counted for ETH calculation
        uint256 expectedEthReturn = (lootToBurn * adjustedBalance) / initialTotalSupply;
        console2.log("Expected ETH return:", expectedEthReturn);
        
        // Execute ragequit as the user
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH reference
        
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens); // Burn loot only
        vm.stopPrank();
        
        // Verify user's new loot balance
        uint256 newLootBalance = IERC20(lootToken).balanceOf(user);
        console2.log("User's new LOOT balance:", newLootBalance);
        assertEq(newLootBalance, initialLootBalance - lootToBurn, "Incorrect loot balance after ragequit");
        
        // Verify user received ETH
        uint256 newUserEthBalance = user.balance;
        console2.log("User's new ETH balance:", newUserEthBalance);
        assertEq(newUserEthBalance, initialUserEthBalance + expectedEthReturn, "User did not receive the correct amount of ETH");
        
        // Verify the Baal avatar's ETH balance is reduced
        uint256 newAvatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar new ETH balance:", newAvatarEthBalance);
        assertEq(newAvatarEthBalance, avatarEthBalance - expectedEthReturn, "Avatar ETH balance not reduced correctly");
        
        // Verify the community vault's ETH balance remains unchanged
        uint256 newVaultEthBalance = address(communityVault).balance;
        console2.log("Community vault new ETH balance:", newVaultEthBalance);
        assertEq(newVaultEthBalance, vaultEthBalance, "Community vault ETH balance should not change");
    }
} 