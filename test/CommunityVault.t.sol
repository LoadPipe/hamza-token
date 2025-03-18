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

    uint256 internal constant INITIAL_USER_BALANCE = 100_000_000_000 ether;
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
        uint256 initialLootVaultBalance = IERC20(loot).balanceOf(address(vault));
        uint256 initialTestVaultBalance = IERC20(testToken).balanceOf(address(vault));

        deposit(depositor1, IERC20(loot), depositAmount1);
        assertEq(vault.getBalance(address(loot)), initialLootVaultBalance + depositAmount1);

        deposit(depositor2, IERC20(loot), depositAmount2);
        assertEq(vault.getBalance(address(loot)), initialLootVaultBalance + depositAmount1 + depositAmount2);

        deposit(depositor3, IERC20(testToken), depositAmount3);
        assertEq(vault.getBalance(address(loot)), initialLootVaultBalance + depositAmount1 + depositAmount2);
        assertEq(vault.getBalance(address(testToken)), initialTestVaultBalance + depositAmount3);

        vm.prank(admin);
        vault.withdraw(address(loot), recipient1, withdrawAmount1);
        assertEq(vault.getBalance(address(loot)), initialLootVaultBalance + depositAmount1 + depositAmount2 - withdrawAmount1);
        assertEq(vault.getBalance(address(testToken)), initialTestVaultBalance + depositAmount3);

        vm.prank(admin);
        vault.withdraw(address(loot), recipient1, withdrawAmount2);
        assertEq(vault.getBalance(address(loot)), initialLootVaultBalance + depositAmount1 + depositAmount2 - withdrawAmount1 - withdrawAmount2);
        assertEq(vault.getBalance(address(testToken)), initialTestVaultBalance + depositAmount3);

        vm.prank(admin);
        vault.withdraw(address(testToken), recipient1, withdrawAmount3);
        assertEq(vault.getBalance(address(loot)), initialLootVaultBalance + depositAmount1 + depositAmount2 - withdrawAmount1 - withdrawAmount2);
        assertEq(vault.getBalance(address(testToken)), initialTestVaultBalance + depositAmount3 - withdrawAmount3);
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
        uint256 initialLootVaultBalance = IERC20(loot).balanceOf(address(vault));

        deposit(depositor1, IERC20(loot), depositAmount);

        vm.startPrank(admin);
        vm.expectRevert();
        vault.withdraw(address(loot), recipient1, initialLootVaultBalance + depositAmount + 1);
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

        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = recipient;
        amounts[0] = 50;

        vm.expectRevert();
        vault.distribute(address(loot), recipients, amounts);
    }
    
    // Test that distribute "Mismatched arrays" error 
    function testDistributeMismatchedArraysError() public {
        uint256 depositAmount = 100;
        deposit(depositor1, IERC20(loot), depositAmount);

        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](2);
        recipients[0] = recipient1;
        amounts[0] = 50;
        amounts[1] = 10;

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
        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;

        //prepare loot amounts to distribute 
        uint256 distributeLootAmount1 = (depositLootTotal/3)-1;
        uint256 distributeLootAmount2 = (depositLootTotal/3)-2;
        uint256 distributeLootAmount3 = (depositLootTotal/3)-3;

        //prepare eth amounts to distribute 
        uint256 distributeEthAmount1 = (depositEthTotal/10);
        uint256 distributeEthAmount2 = (depositEthTotal/10);
        uint256 distributeEthAmount3 = (depositEthTotal/10);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = distributeLootAmount1;
        amounts[1] = distributeLootAmount2;
        amounts[2] = distributeLootAmount3;

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
        
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        recipients[0] = recipient1;
        amounts[0] = 50;

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
        vault.setPurchaseTracker(purchaseTracker);
    }
    
    // Test that setCommunityRewardsCalculator sets the CommunityRewardsCalculator
    function testSetCommunityRewardsCalculator() public {
        CommunityRewardsCalculator newCalc = new CommunityRewardsCalculator();

        vm.prank(admin);
        vault.setCommunityRewardsCalculator(ICommunityRewardsCalculator(newCalc));

        assertEq(address(vault.rewardsCalculator()), address(newCalc));
    }
    
    // Test that setPurchaseTracker can be only called by admin
    function testSetCommunityRewardsCalculatorRestricted() public {
        CommunityRewardsCalculator calc = new CommunityRewardsCalculator();
        vm.expectRevert();
        vault.setCommunityRewardsCalculator(calc);
    }
    
    // Test that setPurchaseTracker sets the PurchaseTracker
    function testSetPurchaseTracker() public {
        PurchaseTracker newTracker = new PurchaseTracker(
            ISecurityContext(hatsCtx), address(testToken)
        );

        vm.prank(admin);
        vault.setPurchaseTracker(address(newTracker));

        assertEq(address(vault.purchaseTracker()), address(newTracker));
    }
    
    // Test that setPurchaseTracker validates address arguments
    function testSetPurchaseTrackerAddressZero() public {
        vm.startPrank(admin);

        //invalid purchase tracker
        vm.expectRevert("Invalid purchase tracker address");
        vault.setPurchaseTracker(address(0));

        vm.stopPrank();
    }

    // Test that rewards are distributed through the PurchaseTracker and CommunityRewardsCalculator to buyers
    function testDistributeRewardsForBuyer() public {
        bytes32 paymentId = keccak256("payment-reward-test-1");
        uint256 payAmount = 500;

        address payer = depositor1;
        address seller = recipient1;

        PaymentEscrow payEscrow = PaymentEscrow(payable(escrow));

        //make sure there's enough in the vault to distribute
        deposit(depositor2, loot, 100_000);

        // Buyer makes a purchase
        vm.startPrank(payer);
        loot.approve(address(payEscrow), payAmount);

        PaymentInput memory input = PaymentInput({
            id: paymentId,
            payer: payer,
            receiver: seller,
            currency: address(loot),
            amount: payAmount
        });
        payEscrow.placePayment(input);
        vm.stopPrank();

        // Buyer and seller release escrow
        vm.prank(depositor1);
        payEscrow.releaseEscrow(paymentId);

        if (!autoRelease) {
            vm.prank(seller);
            payEscrow.releaseEscrow(paymentId);
        }

        // Validate purchase tracking
        assertEq(tracker.totalPurchaseCount(payer), 1, "Incorrect purchase count");
        assertEq(tracker.totalSalesCount(seller), 1, "Incorrect sales count");

        // Check initial reward balance
        uint256 initialBuyerBalance = loot.balanceOf(payer);
        uint256 rewardsToDistribute = tracker.totalPurchaseCount(payer);

        // Distribute reward
        address[] memory recipients = new address[](1);
        recipients[0] = payer;

        vm.prank(admin);
        CommunityVault(communityVault).distributeRewards(address(loot), recipients);

        // Verify rewards were distributed
        assertEq(loot.balanceOf(payer), initialBuyerBalance + rewardsToDistribute, "Incorrect reward distribution");
        assertEq(vault.rewardsDistributed(address(loot), payer), rewardsToDistribute, "Incorrect rewards tracked");
    }

    // Test that rewards are distributed through the PurchaseTracker and CommunityRewardsCalculator to sellers
    function testDistributeRewardsForSeller() public {
        bytes32 paymentId = keccak256("payment-reward-test-2");
        uint256 payAmount = 750_000_000_000_000;

        address payer = depositor1;
        address seller = recipient1;

        PaymentEscrow payEscrow = PaymentEscrow(payable(escrow));

        //make sure there's enough in the vault to distribute
        deposit(depositor2, loot, 100_000);

        // Buyer makes a purchase
        vm.startPrank(payer);
        loot.approve(address(payEscrow), payAmount);

        PaymentInput memory input = PaymentInput({
            id: paymentId,
            payer: payer,
            receiver: seller,
            currency: address(loot),
            amount: payAmount
        });
        payEscrow.placePayment(input);
        vm.stopPrank();

        // Buyer and seller release escrow
        vm.prank(payer);
        payEscrow.releaseEscrow(paymentId);

        if (!autoRelease) {
            vm.prank(seller);
            payEscrow.releaseEscrow(paymentId);
        }

        // Validate purchase tracking
        assertEq(tracker.totalSalesCount(seller), 1, "Incorrect sales count");

        // Check initial reward balance
        uint256 initialSellerBalance = loot.balanceOf(seller);
        uint256 rewardsToDistribute = tracker.totalSalesCount(seller);

        assertEq(rewardsToDistribute, 1);

        // Distribute rewards
        address[] memory recipients = new address[](1);
        recipients[0] = seller;

        vm.prank(admin);
        CommunityVault(communityVault).distributeRewards(address(loot), recipients);

        // Verify rewards were distributed
        assertEq(loot.balanceOf(seller), initialSellerBalance + rewardsToDistribute, "Incorrect reward distribution");
        assertEq(vault.rewardsDistributed(address(loot), seller), rewardsToDistribute, "Incorrect rewards tracked");
    }

    function testClaimMultipleRewards() public {
        bytes32 paymentId1 = keccak256("payment-reward-test-multiple-1");
        uint256 payAmount = 500;

        address buyer = depositor1;
        address seller = recipient1;

        PaymentEscrow payEscrow = PaymentEscrow(payable(escrow));

        // Fund the vault with multiple token types for rewards
        deposit(depositor2, loot, 100_000);
        deposit(depositor3, IERC20(address(0)), 100_000);
        deposit(depositor2, testToken, 100_000);

        // Buyer makes a purchase with LOOT token
        vm.startPrank(buyer);
        loot.approve(address(payEscrow), payAmount);

        PaymentInput memory input1 = PaymentInput({
            id: paymentId1,
            payer: buyer,
            receiver: seller,
            currency: address(loot),
            amount: payAmount
        });
        payEscrow.placePayment(input1);
        vm.stopPrank();

        // Buyer and seller release escrow
        vm.prank(buyer);
        payEscrow.releaseEscrow(paymentId1);

        if (!autoRelease) {
            vm.prank(seller);
            payEscrow.releaseEscrow(paymentId1);
        }

        // Validate purchase tracking
        assertEq(tracker.totalPurchaseCount(buyer), 1, "Incorrect purchase count");
        assertEq(tracker.totalSalesCount(seller), 1, "Incorrect sales count");

        // Check initial reward balances
        uint256 initialBuyerLootBalance = loot.balanceOf(buyer);
        uint256 initialBuyerTestTokenBalance = testToken.balanceOf(buyer);
        uint256 initialBuyerEthBalance = buyer.balance;
        
        uint256 expectedLootRewards = tracker.totalPurchaseCount(buyer);
        
        // First claim: Buyer claims LOOT rewards
        vm.prank(buyer);
        vault.claimRewards(address(loot));
        
        // Verify LOOT rewards were distributed
        uint256 afterFirstClaimLootBalance = loot.balanceOf(buyer);
        assertEq(afterFirstClaimLootBalance, initialBuyerLootBalance + expectedLootRewards, "Incorrect LOOT reward distribution");
        assertEq(vault.rewardsDistributed(address(loot), buyer), expectedLootRewards, "Incorrect LOOT rewards tracked");
        
        // Second claim: Buyer claims LOOT rewards again (should not receive additional rewards)
        vm.prank(buyer);
        vault.claimRewards(address(loot));
        
        // Verify no additional LOOT rewards were distributed
        assertEq(loot.balanceOf(buyer), afterFirstClaimLootBalance, "Additional LOOT rewards incorrectly distributed");
        assertEq(vault.rewardsDistributed(address(loot), buyer), expectedLootRewards, "Incorrect LOOT rewards tracking after second claim");
        
        // First claim: Buyer claims test token rewards
        vm.prank(buyer);
        vault.claimRewards(address(testToken));
        
        // Verify test token rewards were distributed
        uint256 afterFirstClaimTestTokenBalance = testToken.balanceOf(buyer);
        assertEq(afterFirstClaimTestTokenBalance, initialBuyerTestTokenBalance + expectedLootRewards, "Incorrect test token reward distribution");
        assertEq(vault.rewardsDistributed(address(testToken), buyer), expectedLootRewards, "Incorrect test token rewards tracked");
        
        // Second claim: Buyer claims test token rewards again (should not receive additional rewards)
        vm.prank(buyer);
        vault.claimRewards(address(testToken));
        
        // Verify no additional test token rewards were distributed
        assertEq(testToken.balanceOf(buyer), afterFirstClaimTestTokenBalance, "Additional test token rewards incorrectly distributed");
        assertEq(vault.rewardsDistributed(address(testToken), buyer), expectedLootRewards, "Incorrect test token rewards tracking after second claim");
        
        // First claim: Buyer claims ETH rewards
        vm.prank(buyer);
        vault.claimRewards(address(0));
        
        // Verify ETH rewards were distributed
        uint256 afterFirstClaimEthBalance = buyer.balance;
        assertEq(afterFirstClaimEthBalance, initialBuyerEthBalance + expectedLootRewards, "Incorrect ETH reward distribution");
        assertEq(vault.rewardsDistributed(address(0), buyer), expectedLootRewards, "Incorrect ETH rewards tracked");
        
        // Second claim: Buyer claims ETH rewards again (should not receive additional rewards)
        vm.prank(buyer);
        vault.claimRewards(address(0));
        
        // Verify no additional ETH rewards were distributed
        assertEq(buyer.balance, afterFirstClaimEthBalance, "Additional ETH rewards incorrectly distributed");
        assertEq(vault.rewardsDistributed(address(0), buyer), expectedLootRewards, "Incorrect ETH rewards tracking after second claim");
        
        // Repeat the same test for the seller
        uint256 initialSellerLootBalance = loot.balanceOf(seller);
        uint256 expectedSellerRewards = tracker.totalSalesCount(seller);
        
        // First claim: Seller claims LOOT rewards
        vm.prank(seller);
        vault.claimRewards(address(loot));
        
        // Verify LOOT rewards were distributed to seller
        uint256 afterFirstClaimSellerLootBalance = loot.balanceOf(seller);
        assertEq(afterFirstClaimSellerLootBalance, initialSellerLootBalance + expectedSellerRewards, "Incorrect seller LOOT reward distribution");
        assertEq(vault.rewardsDistributed(address(loot), seller), expectedSellerRewards, "Incorrect seller LOOT rewards tracked");
        
        // Second claim: Seller claims LOOT rewards again (should not receive additional rewards)
        vm.prank(seller);
        vault.claimRewards(address(loot));
        
        // Verify no additional LOOT rewards were distributed to seller
        assertEq(loot.balanceOf(seller), afterFirstClaimSellerLootBalance, "Additional seller LOOT rewards incorrectly distributed");
        assertEq(vault.rewardsDistributed(address(loot), seller), expectedSellerRewards, "Incorrect seller LOOT rewards tracking after second claim");
        
        // Try claiming multiple tokens in sequence
        // Third claim (LOOT): Should not receive any additional rewards
        vm.prank(buyer);
        vault.claimRewards(address(loot));
        assertEq(loot.balanceOf(buyer), afterFirstClaimLootBalance, "Additional LOOT rewards incorrectly distributed on third claim");
        
        // Third claim (Test Token): Should not receive any additional rewards
        vm.prank(buyer);
        vault.claimRewards(address(testToken));
        assertEq(testToken.balanceOf(buyer), afterFirstClaimTestTokenBalance, "Additional test token rewards incorrectly distributed on third claim");
        
        // Third claim (ETH): Should not receive any additional rewards
        vm.prank(buyer);
        vault.claimRewards(address(0));
        assertEq(buyer.balance, afterFirstClaimEthBalance, "Additional ETH rewards incorrectly distributed on third claim");
    }

    function testDoubleClaimBugDetection() public {
        bytes32 paymentId1 = keccak256("payment-double-claim-test");
        uint256 payAmount = 500;

        address buyer = depositor1;
        address seller = recipient1;

        PaymentEscrow payEscrow = PaymentEscrow(payable(escrow));

        // Fund the vault with tokens for rewards
        deposit(depositor2, loot, 100_000);

        // Check initial reward tracker states
        uint256 initialBuyerRewardTracker = vault.rewardsDistributed(address(loot), buyer);
        
        // Make a purchase
        vm.startPrank(buyer);
        loot.approve(address(payEscrow), payAmount);
        PaymentInput memory input = PaymentInput({
            id: paymentId1,
            payer: buyer,
            receiver: seller,
            currency: address(loot),
            amount: payAmount
        });
        payEscrow.placePayment(input);
        vm.stopPrank();

        // Complete the transaction
        vm.prank(buyer);
        payEscrow.releaseEscrow(paymentId1);
        if (!autoRelease) {
            vm.prank(seller);
            payEscrow.releaseEscrow(paymentId1);
        }

        // Check purchase tracking
        assertEq(tracker.totalPurchaseCount(buyer), 1, "Incorrect purchase count");
        
        // Get initial balances
        uint256 initialBuyerLootBalance = loot.balanceOf(buyer);
        
        // DEBUG: Log the inputs to getRewardsToDistribute before first claim
        address[] memory recipients = new address[](1);
        recipients[0] = buyer;
        uint256[] memory claimedRewards = new uint256[](1);
        claimedRewards[0] = vault.rewardsDistributed(address(loot), buyer);
        
        console.log("Before first claim - Buyer address:", buyer);
        console.log("Before first claim - Total purchases:", tracker.totalPurchaseCount(buyer));
        console.log("Before first claim - Previously claimed rewards:", claimedRewards[0]);
        
        // First claim
        vm.prank(buyer);
        vault.claimRewards(address(loot));
        
        // Check balances after first claim
        uint256 afterFirstClaimLootBalance = loot.balanceOf(buyer);
        uint256 firstClaimAmount = afterFirstClaimLootBalance - initialBuyerLootBalance;
        uint256 afterFirstClaimRewardTracker = vault.rewardsDistributed(address(loot), buyer);
        
        console.log("After first claim - Rewards distributed:", afterFirstClaimRewardTracker - initialBuyerRewardTracker);
        console.log("After first claim - Balance change:", firstClaimAmount);
        
        // Verify first claim worked correctly
        assertGt(firstClaimAmount, 0, "First claim should give rewards");
        assertEq(afterFirstClaimRewardTracker, initialBuyerRewardTracker + firstClaimAmount, "Rewards tracker should increase by claimed amount");
        
        // DEBUG: Log the inputs to getRewardsToDistribute before second claim 
        claimedRewards[0] = vault.rewardsDistributed(address(loot), buyer);
        console.log("Before second claim - Previously claimed rewards:", claimedRewards[0]);
        
        // Simulate block advancement (which might trigger reward recalculation)
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 3600); // Advance 1 hour
        
        // Second claim attempt - in the real world this seems to be paying out again
        vm.prank(buyer);
        vault.claimRewards(address(loot));
        
        // Check balances after second claim
        uint256 afterSecondClaimLootBalance = loot.balanceOf(buyer);
        uint256 secondClaimAmount = afterSecondClaimLootBalance - afterFirstClaimLootBalance;
        uint256 afterSecondClaimRewardTracker = vault.rewardsDistributed(address(loot), buyer);
        
        console.log("After second claim - Rewards distributed:", afterSecondClaimRewardTracker - afterFirstClaimRewardTracker);
        console.log("After second claim - Balance change:", secondClaimAmount);
        
        // This assertion is what we expect - but it might be failing in production
        assertEq(secondClaimAmount, 0, "Second claim should NOT give additional rewards");
        assertEq(afterSecondClaimRewardTracker, afterFirstClaimRewardTracker, "Rewards tracker should not increase after second claim");
        
        // DEBUGGING: Check what the rewards calculator is returning for the second claim
        claimedRewards[0] = vault.rewardsDistributed(address(loot), buyer);
        
        // Debugging helper - directly inspect the rewards calculator if possible (requires additional helper function)
        // This will simulate what happens when the second claim is processed
        vm.prank(admin);
        address[] memory debugRecipients = new address[](1);
        debugRecipients[0] = buyer;
        
        // Call distributeRewards which will give us the debug logs
        vault.distributeRewards(address(loot), debugRecipients);
        
        // Verify final state
        uint256 finalLootBalance = loot.balanceOf(buyer);
        uint256 finalRewardTracker = vault.rewardsDistributed(address(loot), buyer);
        
        console.log("Final reward tracker value:", finalRewardTracker);
        console.log("Total balance change:", finalLootBalance - initialBuyerLootBalance);
        
        // This should still be true - buyer should only receive rewards once
        assertEq(finalLootBalance, afterFirstClaimLootBalance, "No additional rewards should be given with debug distribution");
    }
    
    function testClaimMultipleSamePerson() public {
        bytes32 paymentId1 = keccak256("payment-self-transaction");
        uint256 payAmount = 500;

        // Same person is both buyer and seller
        address buyerAndSeller = depositor1;

        PaymentEscrow payEscrow = PaymentEscrow(payable(escrow));

        // Fund the vault with multiple token types for rewards
        deposit(depositor2, loot, 100_000);
        deposit(depositor3, IERC20(address(0)), 100_000);
        deposit(depositor2, testToken, 100_000);

        // Person makes a purchase to themselves
        vm.startPrank(buyerAndSeller);
        loot.approve(address(payEscrow), payAmount);

        PaymentInput memory input1 = PaymentInput({
            id: paymentId1,
            payer: buyerAndSeller,
            receiver: buyerAndSeller, // Same address as buyer
            currency: address(loot),
            amount: payAmount
        });
        payEscrow.placePayment(input1);
        vm.stopPrank();

        // Complete the transaction (only needs to release once if autoRelease is true)
        vm.prank(buyerAndSeller);
        payEscrow.releaseEscrow(paymentId1);

        if (!autoRelease) {
            vm.prank(buyerAndSeller);
            payEscrow.releaseEscrow(paymentId1);
        }

        // Validate purchase tracking - should increment both buyer and seller counts
        assertEq(tracker.totalPurchaseCount(buyerAndSeller), 1, "Incorrect purchase count");
        assertEq(tracker.totalSalesCount(buyerAndSeller), 1, "Incorrect sales count");

        // Log debugging info
        console.log("Self-transaction - Address:", buyerAndSeller);
        console.log("Self-transaction - Total purchases:", tracker.totalPurchaseCount(buyerAndSeller));
        console.log("Self-transaction - Total sales:", tracker.totalSalesCount(buyerAndSeller));
        console.log("Self-transaction - Previously claimed rewards:", vault.rewardsDistributed(address(loot), buyerAndSeller));

        // Check initial balance
        uint256 initialBalance = loot.balanceOf(buyerAndSeller);
        
        // First claim: Should receive rewards for both buying and selling
        vm.prank(buyerAndSeller);
        vault.claimRewards(address(loot));
        
        // Verify first claim results
        uint256 afterFirstClaimBalance = loot.balanceOf(buyerAndSeller);
        uint256 firstClaimAmount = afterFirstClaimBalance - initialBalance;
        
        console.log("After first claim - Balance change:", firstClaimAmount);
        console.log("After first claim - Rewards tracker:", vault.rewardsDistributed(address(loot), buyerAndSeller));
        
        // The person should get rewards for both buying and selling (total of 2)
        // This is the expected behavior, but may be where the bug is happening
        assertEq(firstClaimAmount, 2, "Should receive rewards for both buying and selling roles");
        
        // Second claim: attempt to claim again
        vm.roll(block.number + 10);  // Advance blocks to simulate real conditions
        vm.warp(block.timestamp + 3600);  // Advance time
        
        vm.prank(buyerAndSeller);
        vault.claimRewards(address(loot));
        
        // Verify second claim results
        uint256 afterSecondClaimBalance = loot.balanceOf(buyerAndSeller);
        uint256 secondClaimAmount = afterSecondClaimBalance - afterFirstClaimBalance;
        
        console.log("After second claim - Balance change:", secondClaimAmount);
        console.log("After second claim - Rewards tracker:", vault.rewardsDistributed(address(loot), buyerAndSeller));
        
        // Should not receive additional rewards
        assertEq(secondClaimAmount, 0, "Should not receive additional rewards on second claim");
        
        // Third claim: attempt to claim once more
        vm.roll(block.number + 20);  // Advance more blocks
        vm.warp(block.timestamp + 7200);  // Advance more time
        
        vm.prank(buyerAndSeller);
        vault.claimRewards(address(loot));
        
        // Verify third claim results
        uint256 afterThirdClaimBalance = loot.balanceOf(buyerAndSeller);
        uint256 thirdClaimAmount = afterThirdClaimBalance - afterSecondClaimBalance;
        
        console.log("After third claim - Balance change:", thirdClaimAmount);
        console.log("After third claim - Rewards tracker:", vault.rewardsDistributed(address(loot), buyerAndSeller));
        
        // Should not receive additional rewards
        assertEq(thirdClaimAmount, 0, "Should not receive additional rewards on third claim");
        
        // Verify final state
        assertEq(vault.rewardsDistributed(address(loot), buyerAndSeller), 2, "Total rewards distributed should be 2");
    }

    function deposit(address _depositor, IERC20 token, uint256 amount) private {
        vm.startPrank(_depositor); 
        if (address(token) != address(0)) {
            token.approve(address(vault), amount); 
            vault.deposit(address(token), amount);
        }
        else {
            (bool success,) = address(vault).call{value: amount}(
                abi.encodeWithSignature("deposit(address,uint256)", address(token), amount)
            );
            assertTrue(success);
        }

        vm.stopPrank();
    }
}
