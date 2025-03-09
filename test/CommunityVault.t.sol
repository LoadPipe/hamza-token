// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./DeploymentSetup.t.sol";
import "../src/PurchaseTracker.sol";
import "@hamza-escrow/PaymentEscrow.sol" as EscrowLib;
import "@hamza-escrow/security/Roles.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@hamza-escrow/ISystemSettings.sol";
import "@hamza-escrow/TestToken.sol";

/**
 * @notice This test suite tests that the CommunityVault behaves as expected. 
 */
contract TestCommunityVault is DeploymentSetup {
    CommunityVault internal vault;
    PurchaseTracker internal tracker;
    TestToken internal testToken;

    address internal depositor;
    address internal recipient;

    address internal depositor1;
    address internal recipient1;

    address internal depositor2;
    address internal recipient2;

    address internal depositor3;
    address internal recipient3;

    address[] internal recipients;
    uint256[] internal amounts;

    uint256 internal constant INITIAL_USER_BALANCE = 100_000 ether;
    IERC20 internal loot;

    function setUp() public virtual override {
        super.setUp();

        // Cast addresses into actual contract instances
        testToken = new TestToken("ABC", "123");
        tracker = PurchaseTracker(purchaseTracker);
        vault = CommunityVault(communityVault);
        loot = IERC20(lootToken);

        // Define test addresses
        depositor1 = makeAddr("depositor1");
        recipient1 = makeAddr("recipient1");

        depositor2 = makeAddr("depositor2");
        recipient2 = makeAddr("recipient2");

        depositor3 = makeAddr("depositor3");
        recipient3 = makeAddr("recipient3");

        depositor = depositor1;
        recipient = recipient1;

        // Fund the depositor with both ETH and ERC20 tokens
        vm.deal(depositor, INITIAL_USER_BALANCE);
        deal(address(loot), depositor1, INITIAL_USER_BALANCE);
        deal(address(loot), depositor2, INITIAL_USER_BALANCE);
        deal(address(loot), depositor3, INITIAL_USER_BALANCE);
        deal(address(testToken), depositor1, INITIAL_USER_BALANCE);
        deal(address(testToken), depositor2, INITIAL_USER_BALANCE);
        deal(address(testToken), depositor3, INITIAL_USER_BALANCE);
    }

    // Test that getBalance gets the right balance 
    function testGetCorrectBalance() public {
        uint256 depositAmount1 = 1000;
        uint256 depositAmount2 = 1200;
        uint256 depositAmount3 = 10040;
        uint256 withdrawAmount1 = 100;
        uint256 withdrawAmount2 = 120;
        uint256 withdrawAmount3 = 1400;

        deposit(depositor1, IERC20(loot), depositAmount1);
        assertEq(vault.getBalance(address(loot)), depositAmount1);

        deposit(depositor2, IERC20(loot), depositAmount2);
        assertEq(vault.getBalance(address(loot)), depositAmount1 + depositAmount2);

        deposit(depositor3, IERC20(testToken), depositAmount3);
        assertEq(vault.getBalance(address(loot)), depositAmount1 + depositAmount2);
        assertEq(vault.getBalance(address(testToken)), depositAmount3);

        vm.prank(admin);
        vault.withdraw(address(loot), recipient1, depositAmount1);
        assertEq(vault.getBalance(address(loot)), depositAmount2);
        assertEq(vault.getBalance(address(testToken)), depositAmount3);

        vm.prank(admin);
        vault.withdraw(address(loot), recipient1, depositAmount2);
        assertEq(vault.getBalance(address(loot)), 0);
        assertEq(vault.getBalance(address(testToken)), depositAmount3);

        vm.prank(admin);
        vault.withdraw(address(testToken), recipient1, depositAmount3);
        assertEq(vault.getBalance(address(loot)), 0);
        assertEq(vault.getBalance(address(testToken)), 0);
    }

    // Test that deposit emits the Deposit event
    function testDepositEmitsEvent() public {
        uint256 depositAmount = 1000;

        vm.startPrank(depositor1);
        loot.approve(address(vault), depositAmount);
        vm.expectEmit(false, false, false, false);
        emit CommunityVault.Deposit(address(loot), depositor1, depositAmount);
        vault.deposit(address(loot), depositAmount);
        vm.stopPrank();
    }

    // Test that deposit Incorrect ETH amount error
    function testDepositIncorrectAmount() public {
        vm.startPrank(depositor1);
        vm.expectRevert("Incorrect ETH amount");
        vault.deposit(address(0), 1000);
        vm.stopPrank();
    }
    
    // Test that deposit transfers token in the correct way
    function testDepositTransfersTokens() public {
        uint256 depositAmount1 = 1000;
        uint256 depositAmount2 = 1100;
        uint256 depositAmount3 = 1200;

        //initial balances
        uint256 initialDepositor1Balance = loot.balanceOf(depositor1);
        uint256 initialDepositor2Balance = loot.balanceOf(depositor2);
        uint256 initialVaultBalance = loot.balanceOf(address(vault));

        //first deposit 
        deposit(depositor1, IERC20(loot), depositAmount1);

        //check balances
        assertEq(loot.balanceOf(depositor1), (initialDepositor1Balance - depositAmount1));
        assertEq(loot.balanceOf(address(vault)), (initialVaultBalance + depositAmount1));

        //second deposit 
        deposit(depositor1, IERC20(loot), depositAmount2);

        //check balances
        assertEq(loot.balanceOf(depositor1), (initialDepositor1Balance - depositAmount1 - depositAmount2));
        assertEq(loot.balanceOf(address(vault)), (initialVaultBalance + depositAmount1 + depositAmount2));

        //third deposit 
        deposit(depositor2, IERC20(loot), depositAmount3);

        //check balances
        assertEq(loot.balanceOf(depositor2), (initialDepositor2Balance - depositAmount3));
        assertEq(loot.balanceOf(address(vault)), (initialVaultBalance + depositAmount1 + depositAmount2 + depositAmount3));
    }
    
    // Test that deposit transfers ETH in the correct way
    function testDepositTransfersEth() public {
        
    }
    
    // Test that deposit behaves correctly when balance too low 
    function testDepositOverLimit() public {

    }
    
    // Test that withdraw Insufficient Balance error 
    function testWithdrawInsufficientBalanceError() public {
        uint256 depositAmount = 1000;

        deposit(depositor1, IERC20(loot), depositAmount);

        vm.startPrank(admin);
        vm.expectRevert();
        vault.withdraw(address(loot), recipient1, depositAmount + 1);
        vm.stopPrank();
    }
    
    // Test that withdraw transfers token correctly
    function testWithdrawTransfersTokens() public {

    }
    
    // Test that withdraw emits Withdraw event
    function testWithdrawEmitsEvent() public {

    }
    
    // Test that withdraw behaves correctly when balance too low 
    function testWithdrawOverLimit() public {

    }
    
    // Test that withdraw is only callable if authorized
    function testWithdrawRestricted() public {
        uint256 depositAmount = 100;
        deposit(depositor1, IERC20(loot), depositAmount);

        vm.expectRevert();
        vault.withdraw(address(loot), depositor2, depositAmount);
    }
    
    // Test that distribute is only callable if authorized
    function testDistributeRestricted() public {
        uint256 depositAmount = 100;
        deposit(depositor1, IERC20(loot), depositAmount);

        recipients.push(recipient1);
        amounts.push(50);

        vm.expectRevert();
        vault.distribute(address(loot), recipients, amounts);
    }
    
    // Test that distribute "Mismatched arrays" error 
    function testDistributeMimatchedArraysError() public {
        uint256 depositAmount = 100;
        deposit(depositor1, IERC20(loot), depositAmount);

        recipients.push(recipient1);
        amounts.push(50);
        amounts.push(10);

        vm.startPrank(admin);
        vm.expectRevert("Mismatched arrays");
        vault.distribute(address(loot), recipients, amounts);
        vm.stopPrank();
    }
    
    // Test that distribute adjusts balances & distributes token correctly 
    function testDistributeRewards() public {

    }
    
    // Test that distribute handles insufficient balances correctly
    function testDistributeInsufficientBalance() public {

    }
    
    // Test that distribute emits Distribute event 
    function testDistributeEmitsEvent() public {
        uint256 depositAmount = 100;
        deposit(depositor1, IERC20(loot), depositAmount);

        recipients.push(recipient1);
        amounts.push(50);

        vm.startPrank(admin);
        vm.expectEmit(false, false, false, false);
        emit CommunityVault.Distribute(address(loot), recipients[0], amounts[0]);
        vault.distribute(address(loot), recipients, amounts);
        vm.stopPrank();
    }
    
    // Test that setGovernanceVault can be only called by admin
    function testSetGovernanceVaultRestricted() public {
        vm.expectRevert();
        vault.setGovernanceVault(govVault, address(loot));
    }
    
    // Test that setGovernanceVault sets the GovernanceVault
    function testSetGovernanceVault() public {
        GovernanceVault newGovVault = new GovernanceVault(
            ISecurityContext(hatsCtx),
            address(testToken),
            GovernanceToken(address(govToken)),
            100
        );

        vm.prank(admin);
        vault.setGovernanceVault(address(newGovVault), address(testToken));

        assertEq(address(vault.governanceVault()), address(newGovVault));
        assertEq(testToken.allowance(address(vault), address(vault.governanceVault())), type(uint256).max);
    }
    
    // Test that setGovernanceVault validates address arguments
    function testSetGovernanceVaultAddressZero() public {
        vm.startPrank(admin);

        //invalid governance vault
        vm.expectRevert("Invalid staking contract address");
        vault.setGovernanceVault(address(0), address(loot));

        //invalid loot token
        vm.expectRevert("Invalid loot token address");
        vault.setGovernanceVault(govVault, address(0));

        vm.stopPrank();
    }
    
    // Test that setPurchaseTracker can be only called by admin
    function testSetPurchaseTrackerRestricted() public {
        vm.expectRevert();
        vault.setPurchaseTracker(purchaseTracker, address(loot));
    }
    
    // Test that setPurchaseTracker sets the PurchaseTracker
    function testSetPurchaseTracker() public {
        PurchaseTracker newTracker = new PurchaseTracker(
            ISecurityContext(hatsCtx), address(vault), address(testToken)
        );

        vm.prank(admin);
        vault.setPurchaseTracker(address(newTracker), address(testToken));

        assertEq(address(vault.purchaseTracker()), address(newTracker));
        assertEq(testToken.allowance(address(vault), address(vault.purchaseTracker())), type(uint256).max);
    }
    
    // Test that setPurchaseTracker validates address arguments
    function testSetPurchaseTrackerAddressZero() public {
        vm.startPrank(admin);

        //invalid purchase tracker
        vm.expectRevert("Invalid purchase tracker address");
        vault.setPurchaseTracker(address(0), address(loot));

        //invalid loot token
        vm.expectRevert("Invalid loot token address");
        vault.setPurchaseTracker(address(tracker), address(0));

        vm.stopPrank();
    }

    function deposit(address _depositor, IERC20 token, uint256 amount) private {
        vm.startPrank(_depositor); 
        token.approve(address(vault), amount); 
        vault.deposit(address(token), amount);
        vm.stopPrank();
    }
}
