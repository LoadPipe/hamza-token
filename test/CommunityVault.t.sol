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
        vm.deal(depositor1, INITIAL_USER_BALANCE);
        vm.deal(depositor2, INITIAL_USER_BALANCE);
        vm.deal(depositor3, INITIAL_USER_BALANCE);
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
        //assertEq(vault.getBalance(address(loot)), 1); //loot.balanceOf(address(vault))); 3300
        //assertEq(loot.balanceOf(address(vault)), 1); //loot.balanceOf(address(vault))); 50000000000000003300
    }
    
    // Test that deposit transfers ETH in the correct way
    function testDepositTransfersEth() public {
        uint256 depositAmount1 = 1000;
        uint256 depositAmount2 = 1100;
        uint256 depositAmount3 = 1200;

        //initial balances
        uint256 initialDepositor1Balance = depositor1.balance;
        uint256 initialDepositor2Balance = depositor2.balance;
        uint256 initialVaultBalance = address(vault).balance;

        assertNotEq(initialDepositor1Balance, 0);
        assertNotEq(initialDepositor2Balance, 0);

        //first deposit 
        deposit(depositor1, IERC20(address(0)), depositAmount1);

        //check balances
        assertEq(depositor1.balance, (initialDepositor1Balance - depositAmount1));
        assertEq(address(vault).balance, (initialVaultBalance + depositAmount1));

        //second deposit 
        deposit(depositor1, IERC20(address(0)), depositAmount2);

        //check balances
        assertEq(depositor1.balance, (initialDepositor1Balance - depositAmount1 - depositAmount2));
        assertEq(address(vault).balance, (initialVaultBalance + depositAmount1 + depositAmount2));

        //third deposit 
        deposit(depositor2, IERC20(address(0)), depositAmount3);

        //check balances
        assertEq(depositor2.balance, (initialDepositor2Balance - depositAmount3));
        assertEq(address(vault).balance, (initialVaultBalance + depositAmount1 + depositAmount2 + depositAmount3));
        assertEq(vault.getBalance(address(0)), address(vault).balance);
    }
    
    // Test that deposit behaves correctly when balance too low 
    function testDepositOverLimit() public {
        //TODO: testDepositOverLimit
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
        //TODO: testWithdrawTransfersTokens
    }
    
    // Test that withdraw emits Withdraw event
    function testWithdrawEmitsEvent() public {
        //TODO: testWithdrawEmitsEvent
    }
    
    // Test that withdraw behaves correctly when balance too low 
    function testWithdrawOverLimit() public {
        //TODO: testWithdrawOverLimit
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
    //TODO: finish testDistributeRewards 
    function testDistributeRewards() public {
        uint256 depositLootAmount1 = 1000;
        uint256 depositLootAmount2 = 1100;
        uint256 depositLootAmount3 = 1200;
        uint256 depositLootTotal = depositLootAmount1+depositLootAmount2+depositLootAmount3;
        uint256 depositEthAmount1 = 3000;
        uint256 depositEthAmount2 = 2100;
        uint256 depositEthAmount3 = 4200;
        uint256 depositEthTotal = depositEthAmount1+depositEthAmount2+depositEthAmount3;

        //deposit loot
        deposit(depositor1, IERC20(loot), depositLootAmount1);
        deposit(depositor1, IERC20(loot), depositLootAmount2);
        deposit(depositor2, IERC20(loot), depositLootAmount3);

        //deposit eth
        deposit(depositor1, IERC20(address(0)), depositLootAmount1);
        deposit(depositor1, IERC20(address(0)), depositLootAmount2);
        deposit(depositor2, IERC20(address(0)), depositLootAmount3);

        //prepare to distribute 
        recipients.push(recipient1);
        recipients.push(recipient2);
        recipients.push(recipient3);

        //prepare loot amounts to distribute 
        uint256 distributeLootAmount1 = (depositLootTotal/3)-1;
        uint256 distributeLootAmount2 = (depositLootTotal/3)-2;
        uint256 distributeLootAmount3 = (depositLootTotal/3)-3;

        //prepare eth amounts to distribute 
        uint256 distributeEthAmount1 = (depositEthTotal/3)-1;
        uint256 distributeEthAmount2 = (depositEthTotal/3)-2;
        uint256 distributeEthAmount3 = (depositEthTotal/3)-3;

        amounts.push(distributeLootAmount1);
        amounts.push(distributeLootAmount2);
        amounts.push(distributeLootAmount3);

        //distribute loot 
        vm.prank(admin);
        vault.distribute(address(loot), recipients, amounts);

        amounts[0] = distributeEthAmount1;
        amounts[1] = distributeEthAmount2;
        amounts[2] = distributeEthAmount3;

        //distribute eth 
        vm.prank(admin);
        vault.distribute(address(0), recipients, amounts);
    }
    
    // Test that distribute handles insufficient balances correctly
    function testDistributeInsufficientBalance() public {
        //TODO: testDistributeInsufficientBalance
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
            ISecurityContext(hatsCtx), address(testToken)
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
        if (address(token) != address(0)) {
            token.approve(address(vault), amount); 
            vault.deposit(address(token), amount);
        }
        else {
            address(vault).call{value: amount}(
                abi.encodeWithSignature("deposit((address,uint256))", address(token), amount)
            );
        }

        vm.stopPrank();
    }
}
