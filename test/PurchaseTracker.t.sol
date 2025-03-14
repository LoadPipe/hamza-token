// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./DeploymentSetup.t.sol";
import "../src/PurchaseTracker.sol";
import "@hamza-escrow/PaymentEscrow.sol" as EscrowLib;
import "@hamza-escrow/security/Roles.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@hamza-escrow/ISystemSettings.sol";
import { TestToken as HamzaTestToken } from "@hamza-escrow/TestToken.sol";

/**
 * @notice This test suite verifies that the PurchaseTracker is correctly updated
 *         upon successful escrow releases from PaymentEscrow.
 */
contract TestPaymentAndTracker is DeploymentSetup {
    PaymentEscrow internal payEscrow;
    PurchaseTracker internal tracker;
    ISystemSettings internal systemSettings1;
    ISecurityContext internal securityContext;

    address internal payer;
    address internal seller;
    address internal arbiter;

    address internal payer1;
    address internal seller1;

    address internal payer2;
    address internal seller2;

    address internal payer3;
    address internal seller3;

    uint256 internal constant INITIAL_USER_BALANCE = 10_000 ether;
    IERC20 internal loot;

    function setUp() public virtual override {
        super.setUp();

        // Cast addresses into actual contract instances
        tracker = PurchaseTracker(purchaseTracker);
        loot = IERC20(lootToken);
        systemSettings1 = ISystemSettings(systemSettings);
        payEscrow = PaymentEscrow(payable(escrow));

        // Define test addresses
        payer1 = makeAddr("payer1");
        seller1 = makeAddr("seller1");
        arbiter = makeAddr("arbiter");

        payer2 = makeAddr("payer2");
        seller2 = makeAddr("seller2");

        payer3 = makeAddr("payer3");
        seller3 = makeAddr("seller3");

        payer = payer1;
        seller = seller1;

        // Fund the payer with both ETH and ERC20 tokens
        vm.deal(payer, INITIAL_USER_BALANCE);
        deal(address(loot), payer1, INITIAL_USER_BALANCE);
        deal(address(loot), payer2, INITIAL_USER_BALANCE);
        deal(address(loot), payer3, INITIAL_USER_BALANCE);

        // Ensure the PaymentEscrow contract is authorized in the tracker
        vm.prank(admin);
        tracker.authorizeEscrow(escrow);
    }

    function testFullReleaseRecordsPurchase() public {
        // 1. Setup data
        bytes32 paymentId = keccak256("payment-test-1");
        uint256 payAmount = 1000;

        // 2. Place the payment & fetch payment details
        EscrowLib.Payment memory storedPayment = placePayment(
            payEscrow, paymentId, payer, seller, address(loot), payAmount
        );

        // Validate initial state
        assertEq(storedPayment.amount, payAmount, "Incorrect escrowed amount");
        assertEq(storedPayment.payer, payer, "Incorrect payer");
        assertEq(storedPayment.receiver, seller, "Incorrect seller");
        assertFalse(storedPayment.released, "Payment should not be released yet");

        // 3. Release from payer side
        releaseEscrow(payEscrow, paymentId);

        // 4. Validate PurchaseTracker recorded net amount
        uint256 feeBps = payEscrowSettingsFee();
        uint256 expectedFee = (payAmount * feeBps) / 10000;
        uint256 netAmount = payAmount - expectedFee;

        // Buyer checks
        assertEq(tracker.totalPurchaseCount(payer), 1, "Buyer purchase count mismatch");
        assertEq(tracker.totalPurchaseAmount(payer), netAmount, "Buyer purchase amount mismatch");

        // Seller checks
        assertEq(tracker.totalSalesCount(seller), 1, "Seller sales count mismatch");
        assertEq(tracker.totalSalesAmount(seller), netAmount, "Seller sales amount mismatch");
    }

    function testFullReleaseRecordsPurchaseMultiplePayments() public {
        // 1. Setup data
        bytes32 paymentId1 = keccak256("payment-test-1");
        bytes32 paymentId2 = keccak256("payment-test-2");
        bytes32 paymentId3 = keccak256("payment-test-3");
        uint256 payAmount1 = 1200;
        uint256 payAmount2 = 2020;
        uint256 payAmount3 = 3001;

        // 2. Place the payments
        EscrowLib.Payment memory payment1 = placePayment(
            payEscrow, paymentId1, payer1, seller1, address(loot), payAmount1
        );
        EscrowLib.Payment memory payment2 = placePayment(
            payEscrow, paymentId2, payer1, seller2, address(loot), payAmount2
        );
        EscrowLib.Payment memory payment3 = placePayment(
            payEscrow, paymentId3, payer2, seller2, address(loot), payAmount3
        );

        //3. Release escrows 
        releaseEscrow(payEscrow, paymentId1);
        releaseEscrow(payEscrow, paymentId2);
        releaseEscrow(payEscrow, paymentId3);

        //4. Verify released
        payment1 = payEscrow.getPayment(paymentId1);
        payment2 = payEscrow.getPayment(paymentId2);
        payment3 = payEscrow.getPayment(paymentId3);

        assertTrue(payment1.released, "Payment 1 should be fully released now");
        assertTrue(payment2.released, "Payment 2 should be fully released now");
        assertTrue(payment3.released, "Payment 3 should be fully released now");

        // 5. Validate PurchaseTracker recorded net amount
        uint256 feeBps = payEscrowSettingsFee();
        uint256 expectedFee1 = (payAmount1 * feeBps) / 10000;
        uint256 netAmount1 = payAmount1 - expectedFee1;
        uint256 expectedFee2 = (payAmount2 * feeBps) / 10000;
        uint256 netAmount2 = payAmount2 - expectedFee2;
        uint256 expectedFee3 = (payAmount3 * feeBps) / 10000;
        uint256 netAmount3 = payAmount3 - expectedFee3;

        // Buyer checks
        assertEq(tracker.totalPurchaseCount(payer1), 2, "Buyer 1 purchase count mismatch");
        assertEq(tracker.totalPurchaseAmount(payer1), netAmount1  + netAmount2, "Buyer 1 purchase amount mismatch");
        assertEq(tracker.totalPurchaseCount(payer2), 1, "Buyer 2 purchase count mismatch");
        assertEq(tracker.totalPurchaseAmount(payer2), netAmount3, "Buyer 2 purchase amount mismatch");

        // Seller checks
        assertEq(tracker.totalSalesCount(seller1), 1, "Seller 1 sales count mismatch");
        assertEq(tracker.totalSalesAmount(seller1), netAmount1, "Seller 1 sales amount mismatch");
        assertEq(tracker.totalSalesCount(seller2), 2, "Seller 2 sales count mismatch");
        assertEq(tracker.totalSalesAmount(seller2), netAmount2 + netAmount3, "Seller 2 sales amount mismatch");
    }

    function testFullReleaseRecordsPurchaseMultipleEscrows() public {
        // additional escrows
        PaymentEscrow payEscrow1 = payEscrow;
        PaymentEscrow payEscrow2 = new PaymentEscrow(payEscrow.securityContext(), systemSettings1, autoRelease, IPurchaseTracker(purchaseTracker));
        PaymentEscrow payEscrow3 = new PaymentEscrow(payEscrow.securityContext(), systemSettings1, autoRelease, IPurchaseTracker(purchaseTracker));

        //authorize the extra escrows
        vm.startPrank(admin);
        tracker.authorizeEscrow(address(payEscrow2));
        tracker.authorizeEscrow(address(payEscrow3));
        vm.stopPrank();
        
        // 1. Setup data
        bytes32 paymentId1 = keccak256("payment-test-1");
        bytes32 paymentId2 = keccak256("payment-test-2");
        bytes32 paymentId3 = keccak256("payment-test-3");
        uint256 payAmount1 = 1200;
        uint256 payAmount2 = 2020;
        uint256 payAmount3 = 3001;

        // 2. Place the payments
        EscrowLib.Payment memory payment1 = placePayment(
            payEscrow1, paymentId1, payer1, seller1, address(loot), payAmount1
        );
        EscrowLib.Payment memory payment2 = placePayment(
            payEscrow2, paymentId2, payer1, seller2, address(loot), payAmount2
        );
        EscrowLib.Payment memory payment3 = placePayment(
            payEscrow3, paymentId3, payer2, seller2, address(loot), payAmount3
        );

        //3. Release escrows 
        releaseEscrow(payEscrow1, paymentId1);
        releaseEscrow(payEscrow2, paymentId2);
        releaseEscrow(payEscrow3, paymentId3);

        //4. Verify released
        payment1 = payEscrow1.getPayment(paymentId1);
        payment2 = payEscrow2.getPayment(paymentId2);
        payment3 = payEscrow3.getPayment(paymentId3);

        assertTrue(payment1.released, "Payment 1 should be fully released now");
        assertTrue(payment2.released, "Payment 2 should be fully released now");
        assertTrue(payment3.released, "Payment 3 should be fully released now");

        // 5. Validate PurchaseTracker recorded net amount
        uint256 feeBps = payEscrowSettingsFee();
        uint256 expectedFee1 = (payAmount1 * feeBps) / 10000;
        uint256 netAmount1 = payAmount1 - expectedFee1;
        uint256 expectedFee2 = (payAmount2 * feeBps) / 10000;
        uint256 netAmount2 = payAmount2 - expectedFee2;
        uint256 expectedFee3 = (payAmount3 * feeBps) / 10000;
        uint256 netAmount3 = payAmount3 - expectedFee3;

        // Buyer checks
        assertEq(tracker.totalPurchaseCount(payer1), 2, "Buyer 1 purchase count mismatch");
        assertEq(tracker.totalPurchaseAmount(payer1), netAmount1  + netAmount2, "Buyer 1 purchase amount mismatch");
        assertEq(tracker.totalPurchaseCount(payer2), 1, "Buyer 2 purchase count mismatch");
        assertEq(tracker.totalPurchaseAmount(payer2), netAmount3, "Buyer 2 purchase amount mismatch");

        // Seller checks
        assertEq(tracker.totalSalesCount(seller1), 1, "Seller 1 sales count mismatch");
        assertEq(tracker.totalSalesAmount(seller1), netAmount1, "Seller 1 sales amount mismatch");
        assertEq(tracker.totalSalesCount(seller2), 2, "Seller 2 sales count mismatch");
        assertEq(tracker.totalSalesAmount(seller2), netAmount2 + netAmount3, "Seller 2 sales amount mismatch");
    }

    function testUnauthorizedEscrow() public {
        //create an unauthorized escrow
        PaymentEscrow payEscrow2 = new PaymentEscrow(payEscrow.securityContext(), systemSettings1, autoRelease, IPurchaseTracker(purchaseTracker));

        // 1. Setup data
        bytes32 paymentId = keccak256("payment-test-1");
        uint256 payAmount = 1000;

        // 2. Place the payment with an unauthorized escrow
        placePayment(
            payEscrow2, paymentId, payer, seller, address(loot), payAmount
        );

        vm.prank(payer);
        vm.expectRevert("PurchaseTracker: Not authorized");
        payEscrow2.releaseEscrow(paymentId);
    }

    function testTestAbilityToAuthorizeEscrow() public {
        //create an unauthorized escrow
        PaymentEscrow payEscrow2 = new PaymentEscrow(payEscrow.securityContext(), systemSettings1, autoRelease, IPurchaseTracker(purchaseTracker));

        //non-admin can't do it
        vm.expectRevert();
        tracker.authorizeEscrow(address(payEscrow2));
        assertFalse(tracker.authorizedEscrows(address(payEscrow2)));

        //admin can do it
        vm.prank(admin);
        tracker.authorizeEscrow(address(payEscrow2));
        assertTrue(tracker.authorizedEscrows(address(payEscrow2)));
    }

    function testTestAbilityToDeauthorizeEscrow() public {
        assertTrue(tracker.authorizedEscrows(address(payEscrow)));

        //non-admin can't do it
        vm.expectRevert();
        tracker.deauthorizeEscrow(address(payEscrow));
        assertTrue(tracker.authorizedEscrows(address(payEscrow)));

        //admin can do it
        vm.prank(admin);
        tracker.deauthorizeEscrow(address(payEscrow));
        assertFalse(tracker.authorizedEscrows(address(payEscrow)));
    }

    function testPartialRefundThenRelease() public {
        // 1. Setup data
        bytes32 paymentId = keccak256("payment-test-2");
        uint256 payAmount = 2000;
        uint256 refundAmount = 500;

        // 2. Place payment
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

        // 3. Refund part of the payment (by seller or arbiter)
        vm.prank(seller);
        payEscrow.refundPayment(paymentId, refundAmount);

        // 4. Both parties release the escrow
        vm.prank(payer);
        payEscrow.releaseEscrow(paymentId);

        if (!autoRelease) {
            vm.prank(seller);
            payEscrow.releaseEscrow(paymentId);
        }

        // Check final state
        EscrowLib.Payment memory storedPayment = payEscrow.getPayment(paymentId);
        assertTrue(storedPayment.released, "Payment should be fully released now");
        assertEq(storedPayment.amountRefunded, refundAmount, "Refund amount not updated correctly");

        // 5. Confirm net purchase tracked
        uint256 amountAfterRefund = payAmount - refundAmount;
        uint256 feeBps = payEscrowSettingsFee();
        uint256 expectedFee = (amountAfterRefund * feeBps) / 10000;
        uint256 netAmount = amountAfterRefund - expectedFee;

        // Buyer checks
        assertEq(tracker.totalPurchaseCount(payer), 1, "Buyer purchase count mismatch");
        assertEq(tracker.totalPurchaseAmount(payer), netAmount, "Buyer purchase total mismatch");

        // Seller checks
        assertEq(tracker.totalSalesCount(seller), 1, "Seller sales count mismatch");
        assertEq(tracker.totalSalesAmount(seller), netAmount, "Seller sales total mismatch");
    }

    //TODO: TEST: test that PurchaseRecorded event is emitted
    //TODO: TEST: test 'PurchaseTracker: Purchase already recorded' error 

    /**
     * @notice Tests the currency-specific tracking functionality added to PurchaseTracker
     */
    function testCurrencyBasedTracking() public {
        // Create a second test token to test multiple currencies
        HamzaTestToken secondToken = new HamzaTestToken("Second Test Token", "STT");
        secondToken.mint(address(this), 1_000_000 ether);
        secondToken.mint(payer, 10_000 ether);
        secondToken.mint(payer1, 10_000 ether);
        secondToken.mint(payer2, 10_000 ether);
        
        // Setup payment IDs and amounts
        bytes32 paymentId1 = keccak256("currency-test-1");
        bytes32 paymentId2 = keccak256("currency-test-2");
        uint256 payAmount1 = 1000;
        uint256 payAmount2 = 2000;
        
        // Place a payment using loot token
        placePayment(
            payEscrow, paymentId1, payer, seller, address(loot), payAmount1
        );
        
        // Place a payment using the second token
        vm.startPrank(payer);
        secondToken.approve(address(payEscrow), payAmount2);
        vm.stopPrank();
        
        // Place payment with the second token
        vm.startPrank(payer);
        PaymentInput memory input = PaymentInput({
            id: paymentId2,
            payer: payer,
            receiver: seller,
            currency: address(secondToken),
            amount: payAmount2
        });
        payEscrow.placePayment(input);
        vm.stopPrank();
        
        // Release both escrows
        releaseEscrow(payEscrow, paymentId1);
        releaseEscrow(payEscrow, paymentId2);
        
        // Calculate expected net amounts after fees
        uint256 feeBps = payEscrowSettingsFee();
        uint256 expectedFee1 = (payAmount1 * feeBps) / 10000;
        uint256 netAmount1 = payAmount1 - expectedFee1;
        uint256 expectedFee2 = (payAmount2 * feeBps) / 10000;
        uint256 netAmount2 = payAmount2 - expectedFee2;
        
        // Test total amounts
        assertEq(tracker.totalPurchaseAmount(payer), netAmount1 + netAmount2, "Total purchase amount mismatch");
        assertEq(tracker.totalSalesAmount(seller), netAmount1 + netAmount2, "Total sales amount mismatch");
        
        // Test currency-specific amounts
        assertEq(tracker.getPurchaseAmountByCurrency(payer, address(loot)), netAmount1, "Loot token purchase amount mismatch");
        assertEq(tracker.getPurchaseAmountByCurrency(payer, address(secondToken)), netAmount2, "Second token purchase amount mismatch");
        
        assertEq(tracker.getSalesAmountByCurrency(seller, address(loot)), netAmount1, "Loot token sales amount mismatch");
        assertEq(tracker.getSalesAmountByCurrency(seller, address(secondToken)), netAmount2, "Second token sales amount mismatch");
        
        // Test with address with no purchases/sales in a specific currency
        assertEq(tracker.getPurchaseAmountByCurrency(seller, address(loot)), 0, "Seller shouldn't have purchases");
        assertEq(tracker.getSalesAmountByCurrency(payer, address(loot)), 0, "Payer shouldn't have sales");
    }
    
    /**
     * @notice Tests recording purchases in multiple currencies with the same user and verifies
     * that both per-currency and total amounts are tracked correctly
     */
    function testMultipleCurrencyTracking() public {
        // Create three test tokens
        HamzaTestToken token1 = new HamzaTestToken("Token One", "TK1");
        HamzaTestToken token2 = new HamzaTestToken("Token Two", "TK2");
        HamzaTestToken token3 = new HamzaTestToken("Token Three", "TK3");
        
        // Mint tokens to test addresses
        token1.mint(payer, 10_000 ether);
        token2.mint(payer, 10_000 ether);
        token3.mint(payer, 10_000 ether);
        
        // Setup payment data
        bytes32[] memory paymentIds = new bytes32[](3);
        paymentIds[0] = keccak256("multi-currency-1");
        paymentIds[1] = keccak256("multi-currency-2");
        paymentIds[2] = keccak256("multi-currency-3");
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1000;
        amounts[1] = 2000;
        amounts[2] = 3000;
        
        address[] memory currencies = new address[](3);
        currencies[0] = address(token1);
        currencies[1] = address(token2);
        currencies[2] = address(token3);
        
        // Place payments with different currencies
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(payer);
            IERC20(currencies[i]).approve(address(payEscrow), amounts[i]);
            
            PaymentInput memory input = PaymentInput({
                id: paymentIds[i],
                payer: payer,
                receiver: seller,
                currency: currencies[i],
                amount: amounts[i]
            });
            payEscrow.placePayment(input);
            vm.stopPrank();
            
            // Release escrow
            releaseEscrow(payEscrow, paymentIds[i]);
        }
        
        // Calculate expected net amounts after fees
        uint256 feeBps = payEscrowSettingsFee();
        uint256[] memory netAmounts = new uint256[](3);
        uint256 totalNet = 0;
        
        for (uint i = 0; i < 3; i++) {
            uint256 fee = (amounts[i] * feeBps) / 10000;
            netAmounts[i] = amounts[i] - fee;
            totalNet += netAmounts[i];
        }
        
        // Check total amounts
        assertEq(tracker.totalPurchaseAmount(payer), totalNet, "Total purchase amount mismatch");
        assertEq(tracker.totalSalesAmount(seller), totalNet, "Total sales amount mismatch");
        
        // Check currency-specific amounts
        for (uint i = 0; i < 3; i++) {
            assertEq(
                tracker.getPurchaseAmountByCurrency(payer, currencies[i]), 
                netAmounts[i], 
                string.concat("Currency ", Strings.toString(i), " purchase amount mismatch")
            );
            
            assertEq(
                tracker.getSalesAmountByCurrency(seller, currencies[i]), 
                netAmounts[i], 
                string.concat("Currency ", Strings.toString(i), " sales amount mismatch")
            );
        }
    }
    
    /**
     * @notice Tests recording native currency (ETH) purchases correctly
     */
    function testNativeCurrencyTracking() public {
        // Setup payment with native currency (address(0))
        bytes32 paymentId = keccak256("native-currency-test");
        uint256 payAmount = 1 ether;
        
        // Ensure payer has enough ETH
        vm.deal(payer, 10 ether);
        
        // Place payment with native currency
        vm.startPrank(payer);
        PaymentInput memory input = PaymentInput({
            id: paymentId,
            payer: payer,
            receiver: seller,
            currency: address(0), // Native currency
            amount: payAmount
        });
        payEscrow.placePayment{value: payAmount}(input);
        vm.stopPrank();
        
        // Release escrow
        releaseEscrow(payEscrow, paymentId);
        
        // Calculate expected net amount after fees
        uint256 feeBps = payEscrowSettingsFee();
        uint256 expectedFee = (payAmount * feeBps) / 10000;
        uint256 netAmount = payAmount - expectedFee;
        
        // Check total amounts
        assertEq(tracker.totalPurchaseAmount(payer), netAmount, "Total purchase amount mismatch");
        assertEq(tracker.totalSalesAmount(seller), netAmount, "Total sales amount mismatch");
        
        // Check native currency-specific amounts
        assertEq(
            tracker.getPurchaseAmountByCurrency(payer, address(0)), 
            netAmount, 
            "Native currency purchase amount mismatch"
        );
        
        assertEq(
            tracker.getSalesAmountByCurrency(seller, address(0)), 
            netAmount, 
            "Native currency sales amount mismatch"
        );
    }

    function payEscrowSettingsFee() internal view returns (uint256) {
        return systemSettings1.feeBps();
    }

    function placePayment(
        PaymentEscrow _escrow, 
        bytes32 paymentId, 
        address _payer,
        address _seller, 
        address currency, 
        uint256 amount
    ) private returns(EscrowLib.Payment memory) {
        vm.startPrank(payer);
        
        // Use the appropriate token for approval
        if (currency == address(0)) {
            // Native ETH - no approval needed
        } else if (currency == address(loot)) {
            loot.approve(address(_escrow), amount);
        } else {
            IERC20(currency).approve(address(_escrow), amount);
        }

        PaymentInput memory input = PaymentInput({
            id: paymentId,
            payer: _payer,
            receiver: _seller,
            currency: currency,
            amount: amount
        });
        
        if (currency == address(0)) {
            _escrow.placePayment{value: amount}(input);
        } else {
            _escrow.placePayment(input);
        }
        
        vm.stopPrank();

        // 3. Fetch payment details
        EscrowLib.Payment memory storedPayment = _escrow.getPayment(paymentId);
        return storedPayment;
    }

    function releaseEscrow(PaymentEscrow _escrow, bytes32 paymentId) private {
        EscrowLib.Payment memory payment = _escrow.getPayment(paymentId);

        //payer release
        vm.prank(payment.payer);
        _escrow.releaseEscrow(paymentId);

        // Check updated state if autoRelease is enabled
        if (!autoRelease) {
            assertFalse(payment.released, "Should still require seller's release if autoReleaseFlag is false");

            // 5. Release from seller side
            vm.prank(payment.receiver);
            _escrow.releaseEscrow(paymentId);
        }
    }
}
