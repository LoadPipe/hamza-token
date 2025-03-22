// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "./DeploymentSetup.t.sol";
import "../src/tokens/GovernanceToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GovernanceTokenTest is DeploymentSetup {
    using stdJson for string;
    
    // Test-specific variables
    GovernanceToken private govTokenContract;
    string private tokenName;
    string private tokenSymbol;
    address private nonMinterUser;
    
    function setUp() public override {
        // Call the parent setup which deploys all contracts
        super.setUp();
        
        // Cast the address to the contract type for easier access to functions
        govTokenContract = GovernanceToken(govToken);
        
        // Read token name and symbol from config.json
        string memory config = vm.readFile("./config.json");
        tokenName = config.readString(".governanceToken.name");
        tokenSymbol = config.readString(".governanceToken.symbol");
        
        // Create a non-minter user for testing
        nonMinterUser = makeAddr("nonMinterUser");
    }
    
    // Test basic token properties
    function testTokenMetadata() public {
        // Despite name and symbol being passed in constructor, they're hardcoded in the contract
        // This test ensures if that changes, we catch it
        assertEq(govTokenContract.name(), "HamGov");
        assertEq(govTokenContract.symbol(), "HAM");
        assertEq(govTokenContract.decimals(), 18);
    }
    
    // Test that the wrapped token is correctly set
    function testWrappedToken() public {
        assertEq(address(govTokenContract.underlying()), lootToken);
    }
    
    // Test minting functionality
    function testMintWithMinterRole() public {
        // GovernanceVault has the minter role
        vm.startPrank(govVault);
        
        uint256 initialBalance = govTokenContract.balanceOf(user);
        uint256 amountToMint = 100 * 10**18;
        
        govTokenContract.mint(user, amountToMint);
        
        assertEq(govTokenContract.balanceOf(user), initialBalance + amountToMint);
        
        vm.stopPrank();
    }
    
    // Test that non-minters cannot mint
    function testMintWithoutMinterRoleFails() public {
        // Use the non-minter user we created in setUp
        vm.startPrank(nonMinterUser);
        
        uint256 amountToMint = 100 * 10**18;
        
        vm.expectRevert();
        govTokenContract.mint(nonMinterUser, amountToMint);
        
        vm.stopPrank();
    }
    
    // Test burning functionality
    function testBurnWithBurnerRole() public {
        // First mint some tokens to burn
        vm.startPrank(govVault);
        uint256 amountToMint = 100 * 10**18;
        govTokenContract.mint(user, amountToMint);
        
        uint256 balanceAfterMint = govTokenContract.balanceOf(user);
        uint256 amountToBurn = 50 * 10**18;
        
        // Test burning
        govTokenContract.burn(user, amountToBurn);
        
        assertEq(govTokenContract.balanceOf(user), balanceAfterMint - amountToBurn);
        
        vm.stopPrank();
    }
    
    // Test that non-burners cannot burn
    function testBurnWithoutBurnerRoleFails() public {
        // Use the non-minter user we created in setUp
        vm.startPrank(nonMinterUser);
        
        uint256 amountToBurn = 10 * 10**18;
        
        vm.expectRevert();
        govTokenContract.burn(user, amountToBurn);
        
        vm.stopPrank();
    }
    
    // Test depositFor functionality
    function testDepositForWithMinterRole() public {
        // Set up test amounts
        uint256 dealAmount = 100 * 10**18;
        uint256 depositAmount = 50 * 10**18;
        
        // Give tokens directly to the govVault account
        deal(lootToken, govVault, dealAmount);
        
        // Approve from the govVault account
        vm.startPrank(govVault);
        IERC20(lootToken).approve(address(govTokenContract), dealAmount);
        
        // Check initial balances
        uint256 initialWrappedBalance = govTokenContract.balanceOf(admin);
        uint256 initialUnderlyingBalance = IERC20(lootToken).balanceOf(govVault);
        
        // Call depositFor, which should transfer from govVault to the token contract
        bool success = govTokenContract.depositFor(admin, depositAmount);
        vm.stopPrank();
        
        assertTrue(success);
        assertEq(govTokenContract.balanceOf(admin), initialWrappedBalance + depositAmount);
        assertEq(IERC20(lootToken).balanceOf(govVault), initialUnderlyingBalance - depositAmount);
    }
    
    // Test that non-minters cannot call depositFor
    function testDepositForWithoutMinterRoleFails() public {
        vm.startPrank(nonMinterUser);
        
        uint256 depositAmount = 50 * 10**18;
        
        vm.expectRevert();
        govTokenContract.depositFor(nonMinterUser, depositAmount);
        
        vm.stopPrank();
    }
    
    // Test withdrawTo functionality
    function testWithdrawToWithMinterRole() public {
        uint256 mintAmount = 100 * 10**18;
        uint256 withdrawAmount = 50 * 10**18;
        
        // Give governance tokens to governance vault
        vm.startPrank(govVault);
        govTokenContract.mint(govVault, mintAmount);
        vm.stopPrank();
        
        // Give underlying tokens to the governance token contract to fulfill withdrawals
        deal(lootToken, address(govTokenContract), withdrawAmount);
        
        // Check initial balances before withdraw
        vm.startPrank(govVault);
        uint256 initialWrappedBalance = govTokenContract.balanceOf(govVault);
        uint256 initialRecipientUnderlyingBalance = IERC20(lootToken).balanceOf(admin);
        
        // Now withdraw from govVault to admin
        bool success = govTokenContract.withdrawTo(admin, withdrawAmount);
        vm.stopPrank();
        
        assertTrue(success);
        // The governance vault's wrapped token balance should decrease
        assertEq(govTokenContract.balanceOf(govVault), initialWrappedBalance - withdrawAmount);
        // The admin's underlying token balance should increase
        assertEq(IERC20(lootToken).balanceOf(admin), initialRecipientUnderlyingBalance + withdrawAmount);
    }
    
    // Test that non-minters cannot call withdrawTo
    function testWithdrawToWithoutMinterRoleFails() public {
        vm.startPrank(nonMinterUser);
        
        uint256 withdrawAmount = 50 * 10**18;
        
        vm.expectRevert();
        govTokenContract.withdrawTo(nonMinterUser, withdrawAmount);
        
        vm.stopPrank();
    }
    
    // Test voting delegation happens on mint
    function testVotingDelegationOnMint() public {
        vm.startPrank(govVault);
        
        address newUser = address(0x123);
        uint256 mintAmount = 100 * 10**18;
        
        // Mint tokens to the new user
        govTokenContract.mint(newUser, mintAmount);
        
        // Check that the user has delegated to themselves
        assertEq(govTokenContract.delegates(newUser), newUser);
        
        vm.stopPrank();
    }
    
    // Test the afterTokenTransfer hook maintains voting power correctly
    function testVotingPowerAfterTransfer() public {
        vm.startPrank(govVault);
        
        address sender = user;
        address recipient = address(0x456);
        uint256 mintAmount = 100 * 10**18;
        
        // Mint tokens to the sender
        govTokenContract.mint(sender, mintAmount);
        
        // Check initial voting power
        assertEq(govTokenContract.getVotes(sender), mintAmount);
        
        // Transfer tokens
        vm.stopPrank();
        
        vm.startPrank(sender);
        govTokenContract.transfer(recipient, mintAmount / 2);
        
        // Check voting power after transfer
        assertEq(govTokenContract.getVotes(sender), mintAmount / 2);
        
        // Recipient needs to delegate to themselves to get voting power
        vm.stopPrank();
        
        vm.startPrank(recipient);
        govTokenContract.delegate(recipient);
        
        assertEq(govTokenContract.getVotes(recipient), mintAmount / 2);
        
        vm.stopPrank();
    }
} 