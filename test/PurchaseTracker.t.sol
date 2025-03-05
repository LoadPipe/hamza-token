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

    address internal payer;
    address internal seller;
    address internal arbiter;

    uint256 internal constant INITIAL_USER_BALANCE = 10_000 ether;
    IERC20 internal loot;

    function setUp() public virtual override {
        super.setUp();

        // Cast addresses into actual contract instances
        payEscrow = PaymentEscrow(payable(escrow));
        tracker = PurchaseTracker(purchaseTracker);
        loot = IERC20(lootToken);
        systemSettings1 = ISystemSettings(systemSettings);

        // Define test addresses
        payer = makeAddr("payer");
        seller = makeAddr("seller");
        arbiter = makeAddr("arbiter");

        // Fund the payer with both ETH and ERC20 tokens
        vm.deal(payer, INITIAL_USER_BALANCE);
        deal(address(loot), payer, INITIAL_USER_BALANCE);

        // Ensure the PaymentEscrow contract is authorized in the tracker
        vm.prank(admin);
        tracker.authorizeEscrow(escrow);
    }

    function testFullReleaseRecordsPurchase() public {
        // 1. Setup data
        bytes32 paymentId = keccak256("payment-test-1");
        uint256 payAmount = 1000;

        // 2. Place the payment
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

        // 3. Fetch payment details
        EscrowLib.Payment memory storedPayment = payEscrow.getPayment(paymentId);

        // Validate initial state
        assertEq(storedPayment.amount, payAmount, "Incorrect escrowed amount");
        assertEq(storedPayment.payer, payer, "Incorrect payer");
        assertEq(storedPayment.receiver, seller, "Incorrect seller");
        assertFalse(storedPayment.released, "Payment should not be released yet");

        // 4. Release from payer side
        vm.prank(payer);
        payEscrow.releaseEscrow(paymentId);

        // Check updated state if autoRelease is enabled
        if (!autoRelease) {
            storedPayment = payEscrow.getPayment(paymentId);
            assertFalse(storedPayment.released, "Should still require seller's release if autoReleaseFlag is false");

            // 5. Release from seller side
            vm.prank(seller);
            payEscrow.releaseEscrow(paymentId);
        }

        storedPayment = payEscrow.getPayment(paymentId);
        assertTrue(storedPayment.released, "Payment should be fully released now");

        // 6. Validate PurchaseTracker recorded net amount
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


    function payEscrowSettingsFee() internal view returns (uint256) {
        return systemSettings1.feeBps();
    }
}
