// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./DeploymentSetup.t.sol";
import "../src/CustomBaal.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { console2 } from "forge-std/console2.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

/**
 * @dev RagequitTest contract to test the ragequit functionality of the Baal DAO
 */
contract RagequitTest is DeploymentSetup {
    
    // For config-agnostic tests
    CustomBaal public customBaalDirect; 
    address public mockCommunityVault;
    address public mockLootToken;
    address public mockSharesToken;
    address public testUser1;
    address public testUser2;
    address public testUser3;
    ERC20PresetMinterPauser public testToken1;
    ERC20PresetMinterPauser public testToken2;
    
    // Override setup to initialize config-agnostic test variables
    function setUp() public override {
        super.setUp();
        
        // Create test users
        testUser1 = makeAddr("testUser1");
        testUser2 = makeAddr("testUser2");
        testUser3 = makeAddr("testUser3");
        
        // Deploy test tokens for ragequit
        testToken1 = new ERC20PresetMinterPauser("Test Token 1", "TT1");
        testToken2 = new ERC20PresetMinterPauser("Test Token 2", "TT2");
    }
    
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
        
        // Get initial supplies
        uint256 initialTotalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        console2.log("Community vault LOOT balance:", vaultLootBalance);
        console2.log("Community vault SHARES balance:", vaultSharesBalance);
        
        // Calculate adjusted total supply (excluding community vault tokens)
        uint256 adjustedTotalSupply = initialTotalSupply > (vaultLootBalance + vaultSharesBalance)
            ? initialTotalSupply - (vaultLootBalance + vaultSharesBalance)
            : 1;
        console2.log("Adjusted total supply:", adjustedTotalSupply);
        
        // Send 10 ETH to the Baal avatar (Safe)
        vm.deal(address(this), 10 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 10 ether}("");
        require(success, "ETH transfer to Baal avatar failed");
        
        // Verify the ETH balance of the Baal avatar
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar ETH balance:", avatarEthBalance);
        
        // Calculate expected ETH return based on proportion
        // The correct calculation now uses adjustedTotalSupply
        uint256 expectedEthReturn = (lootToBurn * avatarEthBalance) / adjustedTotalSupply;
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
        
        // Get initial supplies and vault balances
        uint256 initialTotalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        console2.log("Community vault LOOT balance:", vaultLootBalance);
        console2.log("Community vault SHARES balance:", vaultSharesBalance);
        
        // Calculate adjusted total supply (excluding community vault tokens)
        uint256 adjustedTotalSupply = initialTotalSupply > (vaultLootBalance + vaultSharesBalance)
            ? initialTotalSupply - (vaultLootBalance + vaultSharesBalance)
            : 1;
        console2.log("Adjusted total supply:", adjustedTotalSupply);
        
        // Send 5 ETH to the Baal avatar (Safe)
        vm.deal(address(this), 5 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 5 ether}("");
        require(success, "ETH transfer to Baal avatar failed");
        
        // Verify the ETH balance of the Baal avatar
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar ETH balance:", avatarEthBalance);
        
        // Calculate expected ETH return based on proportion
        uint256 expectedEthReturn = ((lootToBurn + sharesToBurn) * avatarEthBalance) / adjustedTotalSupply;
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
        
        // Get the initial total supply and vault balances
        uint256 initialTotalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        console2.log("Community vault LOOT balance:", vaultLootBalance);
        console2.log("Community vault SHARES balance:", vaultSharesBalance);
        
        // Calculate adjusted total supply (excluding community vault tokens)
        uint256 adjustedTotalSupply = initialTotalSupply > (vaultLootBalance + vaultSharesBalance)
            ? initialTotalSupply - (vaultLootBalance + vaultSharesBalance)
            : 1;
        console2.log("Adjusted total supply:", adjustedTotalSupply);
        
        // Send 8 ETH to the Baal avatar (DAO treasury)
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
        
        // Calculate expected ETH return
        // Step 1: Get the adjusted ETH balance (excluding vault's ETH)
        uint256 adjustedEthBalance = avatarEthBalance;
        console2.log("Adjusted ETH balance (avatar only):", adjustedEthBalance);
        
        // Step 2: Calculate expected ETH return
        uint256 expectedEthReturn = (lootToBurn * adjustedEthBalance) / adjustedTotalSupply;
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
    
    // Test the extreme case where community vault owns most tokens
    function testRagequitWithMajorityVaultOwnership() public {
        // Get the Baal contract instance
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get initial balances
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        console2.log("User's initial LOOT balance:", initialLootBalance);
        
        // Burn all loot
        uint256 lootToBurn = initialLootBalance;
        console2.log("LOOT to burn (all user loot):", lootToBurn);
        
        // Get initial supplies and vault balances
        uint256 initialTotalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        
        console2.log("Initial total supply (shares + loot):", initialTotalSupply);
        console2.log("Community vault LOOT balance:", vaultLootBalance);
        console2.log("Community vault SHARES balance:", vaultSharesBalance);
        
        // Calculate adjusted total supply
        uint256 adjustedTotalSupply = initialTotalSupply > (vaultLootBalance + vaultSharesBalance)
            ? initialTotalSupply - (vaultLootBalance + vaultSharesBalance)
            : 1;
        console2.log("Adjusted total supply:", adjustedTotalSupply);
        
        // Calculate non-vault tokens (should match the user's tokens if they're the only non-vault holder)
        uint256 nonVaultTokens = initialTotalSupply - (vaultLootBalance + vaultSharesBalance);
        console2.log("Non-vault tokens (should match user tokens):", nonVaultTokens);
        console2.log("User's tokens (loot):", initialLootBalance);
        
        // Send 10 ETH to the Baal avatar
        vm.deal(address(this), 10 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 10 ether}("");
        require(success, "ETH transfer to Baal avatar failed");
        
        // Verify the ETH balance of the Baal avatar
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar ETH balance:", avatarEthBalance);
        
        // Calculate expected ETH return - with the adjusted formula
        // If user owns all non-vault tokens, they should get all the avatar's ETH
        uint256 expectedEthReturn = (lootToBurn * avatarEthBalance) / adjustedTotalSupply;
        console2.log("Expected ETH return:", expectedEthReturn);
        
        // If user owns 100% of non-vault tokens, they should get 100% of avatar's ETH
        if (lootToBurn == nonVaultTokens) {
            console2.log("User owns 100% of non-vault tokens, should get all avatar ETH");
            expectedEthReturn = avatarEthBalance;
        }
        
        // Record user's initial ETH balance
        uint256 initialUserEthBalance = user.balance;
        console2.log("User's initial ETH balance:", initialUserEthBalance);
        
        // Execute ragequit as the user
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH reference
        
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens);
        vm.stopPrank();
        
        // Verify user's new loot balance (should be 0)
        uint256 newLootBalance = IERC20(lootToken).balanceOf(user);
        console2.log("User's new LOOT balance:", newLootBalance);
        assertEq(newLootBalance, 0, "User should have 0 loot after burning all loot");
        
        // Verify user received ETH
        uint256 newUserEthBalance = user.balance;
        console2.log("User's new ETH balance:", newUserEthBalance);
        assertEq(newUserEthBalance, initialUserEthBalance + expectedEthReturn, "User did not receive the correct amount of ETH");
        
        // Verify the Baal avatar's ETH balance is reduced appropriately
        uint256 newAvatarEthBalance = address(baalContract.avatar()).balance;
        console2.log("Baal avatar new ETH balance:", newAvatarEthBalance);
        assertEq(newAvatarEthBalance, avatarEthBalance - expectedEthReturn, "Avatar ETH balance not reduced correctly");
    }

    // Direct test of ragequit with multiple tokens
    function testRagequitWithMultipleTokens() public {
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get user's initial loot balance
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        uint256 lootToBurn = initialLootBalance / 3; // Burn a third of the loot
        
        // Setup test tokens in treasury
        uint256 treasuryToken1Amount = 100 ether;
        uint256 treasuryToken2Amount = 200 ether;
        
        // Mint tokens and send to avatar (treasury)
        testToken1.mint(address(this), treasuryToken1Amount);
        testToken2.mint(address(this), treasuryToken2Amount);
        testToken1.transfer(baalContract.avatar(), treasuryToken1Amount);
        testToken2.transfer(baalContract.avatar(), treasuryToken2Amount);
        
        // Send ETH to avatar
        vm.deal(address(this), 5 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 5 ether}("");
        require(success, "ETH transfer failed");
        
        // Get initial balances
        uint256 initialTotalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        
        // Calculate adjusted total supply
        uint256 adjustedTotalSupply = initialTotalSupply - vaultLootBalance - vaultSharesBalance;
        
        // Calculate expected returns for each token
        uint256 expectedEthReturn = (lootToBurn * 5 ether) / adjustedTotalSupply;
        uint256 expectedToken1Return = (lootToBurn * treasuryToken1Amount) / adjustedTotalSupply;
        uint256 expectedToken2Return = (lootToBurn * treasuryToken2Amount) / adjustedTotalSupply;

        // Record initial balances
        uint256 initialUserEthBalance = user.balance;
        uint256 initialUserToken1Balance = testToken1.balanceOf(user);
        uint256 initialUserToken2Balance = testToken2.balanceOf(user);
        
        // Sort token addresses in ascending order for ragequit
        address ethAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        address token1Address = address(testToken1);
        address token2Address = address(testToken2);
        
        // Create the tokens array with sorted addresses
        address[] memory tokens = new address[](3);
        
        // Simple sorting based on address values
        if (token1Address < token2Address && token1Address < ethAddress) {
            tokens[0] = token1Address;
            if (token2Address < ethAddress) {
                tokens[1] = token2Address;
                tokens[2] = ethAddress;
            } else {
                tokens[1] = ethAddress;
                tokens[2] = token2Address;
            }
        } else if (token2Address < token1Address && token2Address < ethAddress) {
            tokens[0] = token2Address;
            if (token1Address < ethAddress) {
                tokens[1] = token1Address;
                tokens[2] = ethAddress;
            } else {
                tokens[1] = ethAddress;
                tokens[2] = token1Address;
            }
        } else {
            tokens[0] = ethAddress;
            if (token1Address < token2Address) {
                tokens[1] = token1Address;
                tokens[2] = token2Address;
            } else {
                tokens[1] = token2Address;
                tokens[2] = token1Address;
            }
        }
        
        // Execute ragequit
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens);
        vm.stopPrank();
        
        // Check loot was burned
        assertEq(IERC20(lootToken).balanceOf(user), initialLootBalance - lootToBurn);
        
        // Check user received tokens and treasury balances were reduced
        // We need to verify each token based on its position in the sorted array
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == ethAddress) {
                assertEq(user.balance, initialUserEthBalance + expectedEthReturn, "ETH balance incorrect");
                assertEq(address(baalContract.avatar()).balance, 5 ether - expectedEthReturn, "Avatar ETH balance incorrect");
            } else if (tokens[i] == token1Address) {
                assertEq(testToken1.balanceOf(user), initialUserToken1Balance + expectedToken1Return, "Token1 balance incorrect");
                assertEq(testToken1.balanceOf(baalContract.avatar()), treasuryToken1Amount - expectedToken1Return, "Avatar Token1 balance incorrect");
            } else if (tokens[i] == token2Address) {
                assertEq(testToken2.balanceOf(user), initialUserToken2Balance + expectedToken2Return, "Token2 balance incorrect");
                assertEq(testToken2.balanceOf(baalContract.avatar()), treasuryToken2Amount - expectedToken2Return, "Avatar Token2 balance incorrect");
            }
        }
    }
    
    // Test multiple users doing ragequit sequentially 
    function testSequentialRagequit() public {
        CustomBaal baalContract = CustomBaal(baal);
        
        // Setup initial state - share loot among test users
        vm.startPrank(user);
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        
        // Keep half, give 1/4 to each test user
        uint256 transferAmount = initialLootBalance / 4;
        IERC20(lootToken).transfer(testUser1, transferAmount);
        IERC20(lootToken).transfer(testUser2, transferAmount);
        vm.stopPrank();
        
        // Send ETH to avatar
        vm.deal(address(this), 12 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 12 ether}("");
        require(success, "ETH transfer failed");
        
        // Get adjusted total supply
        uint256 totalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        uint256 adjustedTotalSupply = totalSupply - vaultLootBalance - vaultSharesBalance;
        
        // User 1 ragequits with all their loot
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH
        
        uint256 user1InitialBalance = testUser1.balance;
        uint256 avatarInitialBalance = address(baalContract.avatar()).balance;
        uint256 expectedReturn1 = (transferAmount * avatarInitialBalance) / adjustedTotalSupply;
        
        vm.startPrank(testUser1);
        baalContract.ragequit(testUser1, 0, transferAmount, tokens);
        vm.stopPrank();
        
        // Check user1 received ETH
        assertEq(testUser1.balance, user1InitialBalance + expectedReturn1);
        
        // User 2 ragequits with all their loot
        uint256 user2InitialBalance = testUser2.balance;
        uint256 avatarUpdatedBalance = address(baalContract.avatar()).balance;
        
        // Recalculate adjusted total supply after user1's ragequit
        adjustedTotalSupply -= transferAmount;
        uint256 expectedReturn2 = (transferAmount * avatarUpdatedBalance) / adjustedTotalSupply;
        
        vm.startPrank(testUser2);
        baalContract.ragequit(testUser2, 0, transferAmount, tokens);
        vm.stopPrank();
        
        // Check user2 received ETH 
        assertEq(testUser2.balance, user2InitialBalance + expectedReturn2);
        
        // Verify original user's loot remains intact
        assertEq(IERC20(lootToken).balanceOf(user), initialLootBalance / 2);
        
        // Verify both test users have 0 loot
        assertEq(IERC20(lootToken).balanceOf(testUser1), 0);
        assertEq(IERC20(lootToken).balanceOf(testUser2), 0);
    }
    
    // Test edge case: total supply equals vault balance
    function testRagequitWithTotalSupplyEqualsVaultBalance() public {
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get user's current loot
        uint256 userLootBalance = IERC20(lootToken).balanceOf(user);
        
        // Mint more loot to the community vault to make adjustedTotalSupply very small
        vm.startPrank(baalContract.avatar());
        baalContract.mintLoot(
            _singleAddressArray(communityVault), 
            _singleUint256Array(baalContract.totalSupply() * 100) // Make vault balance far exceed total supply
        );
        vm.stopPrank();
        
        // Send ETH to avatar
        vm.deal(address(this), 5 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 5 ether}("");
        require(success, "ETH transfer failed");
        
        // Calculate expected return
        uint256 lootToBurn = userLootBalance / 2;
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH
        
        uint256 initialUserEthBalance = user.balance;
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens);
        vm.stopPrank();
        
        // Even with extreme vault balance, user should still get proportional ETH
        assertGt(user.balance, initialUserEthBalance, "User should have received some ETH");
        assertLt(address(baalContract.avatar()).balance, avatarEthBalance, "Avatar balance should have decreased");
    }
    
    // Test ragequit with zero community vault
    function testRagequitWithZeroCommunityVault() public {
        CustomBaal baalContract = CustomBaal(baal);
        
        // Get initial balances and information
        uint256 initialUserLootBalance = IERC20(lootToken).balanceOf(user);
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        console2.log("Initial community vault LOOT balance:", vaultLootBalance);
        
        vm.startPrank(baalContract.avatar());
        
        // Burn all loot tokens from the community vault
        baalContract.burnLoot(
            _singleAddressArray(communityVault),
            _singleUint256Array(vaultLootBalance)
        );
        vm.stopPrank();
        
        // Verify the community vault now has zero loot tokens
        uint256 newVaultBalance = IERC20(lootToken).balanceOf(communityVault);
        console2.log("Community vault LOOT balance after burning:", newVaultBalance);
        assertEq(newVaultBalance, 0, "Vault should have 0 loot");
        
        // Send ETH to the avatar for ragequit
        vm.deal(address(this), 5 ether);
        (bool success, ) = payable(baalContract.avatar()).call{value: 5 ether}("");
        require(success, "ETH transfer failed");
        
        // Record initial balances before ragequit
        uint256 initialTotalSupply = baalContract.totalSupply();
        uint256 initialUserEthBalance = user.balance;
        uint256 avatarEthBalance = address(baalContract.avatar()).balance;
        
        // Calculate loot to burn (half of user's balance)
        uint256 lootToBurn = initialUserLootBalance / 2;
        
        // Prepare token array for ragequit
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // ETH
        
        // Calculate expected return with zero vault balance
        uint256 adjustedTotalSupply = initialTotalSupply;
        uint256 expectedEthReturn = (lootToBurn * avatarEthBalance) / adjustedTotalSupply;
        
        // Execute ragequit with zero vault balance
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens);
        vm.stopPrank();
        
        // Verify user received the expected ETH amount
        assertEq(user.balance, initialUserEthBalance + expectedEthReturn, "User didn't receive correct ETH amount");
        
        // Verify user's loot was burned
        assertEq(IERC20(lootToken).balanceOf(user), initialUserLootBalance - lootToBurn, "Incorrect loot balance after ragequit");
        
        // Verify avatar ETH balance decreased correctly
        assertEq(address(baalContract.avatar()).balance, avatarEthBalance - expectedEthReturn, "Avatar ETH balance didn't decrease correctly");
    }
    
    // Test ragequit with precise amounts and custom loot distribution
    function testRagequitWithPreciseAmounts() public {
        CustomBaal baalContract = CustomBaal(baal);
        
        // User wants to burn exactly 35% of their loot
        uint256 initialLootBalance = IERC20(lootToken).balanceOf(user);
        uint256 lootToBurn = (initialLootBalance * 35) / 100; // 35%
        
        // Send a precise amount of ETH to avatar
        uint256 ethAmount = 7.77777 ether;
        vm.deal(address(this), ethAmount);
        (bool success, ) = payable(baalContract.avatar()).call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        
        // Calculate expected return
        uint256 totalSupply = baalContract.totalSupply();
        uint256 vaultLootBalance = IERC20(lootToken).balanceOf(communityVault);
        uint256 vaultSharesBalance = IERC20(address(baalContract.sharesToken())).balanceOf(communityVault);
        uint256 adjustedTotalSupply = totalSupply - vaultLootBalance - vaultSharesBalance;
        
        uint256 expectedEthReturn = (lootToBurn * ethAmount) / adjustedTotalSupply;
        
        // Record initial balances
        uint256 initialUserEthBalance = user.balance;
        
        // Ragequit with ETH
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        
        vm.startPrank(user);
        baalContract.ragequit(user, 0, lootToBurn, tokens);
        vm.stopPrank();
        
        // Verify results
        assertEq(IERC20(lootToken).balanceOf(user), initialLootBalance - lootToBurn);
        assertEq(user.balance, initialUserEthBalance + expectedEthReturn);
    }
    
    // Helper functions
    function _singleAddressArray(address _addr) private pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = _addr;
        return arr;
    }
    
    function _singleUint256Array(uint256 _val) private pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = _val;
        return arr;
    }
} 