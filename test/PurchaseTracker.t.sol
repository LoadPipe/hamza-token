// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "./DeploymentSetup.t.sol";
import "../src/PurchaseTracker.sol";
import "@hamza-escrow/PaymentEscrow.sol" as EscrowLib;
import "@hamza-escrow/security/Roles.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@hamza-escrow/ISystemSettings.sol";

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

    function testDistributeRewardsForBuyer() public {
        bytes32 paymentId = keccak256("payment-reward-test-1");
        uint256 payAmount = 500;

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
        assertEq(tracker.totalPurchaseCount(payer), 1, "Incorrect purchase count");
        assertEq(tracker.totalSalesCount(seller), 1, "Incorrect sales count");

        // Check initial reward balance
        uint256 initialBuyerBalance = loot.balanceOf(payer);
        uint256 rewardsToDistribute = tracker.totalPurchaseCount(payer);

        // Distribute reward
        vm.prank(payer);
        tracker.distributeReward(payer);

        // Verify rewards were distributed
        assertEq(loot.balanceOf(payer), initialBuyerBalance + rewardsToDistribute, "Incorrect reward distribution");
        assertEq(tracker.rewardsDistributed(payer), rewardsToDistribute, "Incorrect rewards tracked");
    }

    function testDistributeRewardsForSeller() public {
        bytes32 paymentId = keccak256("payment-reward-test-2");
        uint256 payAmount = 750;

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

        // Distribute reward
        vm.prank(seller);
        tracker.distributeReward(seller);

        // Verify rewards were distributed
        assertEq(loot.balanceOf(seller), initialSellerBalance + rewardsToDistribute, "Incorrect reward distribution");
        assertEq(tracker.rewardsDistributed(seller), rewardsToDistribute, "Incorrect rewards tracked");
    }

    function testDistributeRewardsFailsIfNoPurchasesOrSales() public {
        // Check initial reward distribution
        assertEq(tracker.rewardsDistributed(arbiter), 0, "Arbiter should have no rewards");

        // Expect revert due to no rewards available
        vm.expectRevert("PurchaseTracker: No rewards to distribute");
        vm.prank(arbiter);
        tracker.distributeReward(arbiter);
    }

    //TODO: TEST: test that PurchaseRecorded event is emitted
    //TODO: TEST: test 'PurchaseTracker: Purchase already recorded' error 


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
        loot.approve(address(_escrow), amount);

        PaymentInput memory input = PaymentInput({
            id: paymentId,
            payer: _payer,
            receiver: _seller,
            currency: currency,
            amount: amount
        });
        _escrow.placePayment(input);
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
