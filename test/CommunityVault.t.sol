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
 * @notice This test suite tests that the CommunityVault 
 */
contract TestCommunityVault is DeploymentSetup {
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

    // Test that getBalance gets the right balance 
    // Test that deposit  ...
    // ... emits the Deposit event
    // ... Incorrect ETH amount error
    // ... transfers token in the correct way
    // ... behaves correctly when balance too low 
    // Test that withdraw ...
    // ... Insufficient Balance error 
    // ... transfers token correctly
    // ... emits Withdraw event
    // ... behaves correctly when balance too low 
    // ... is only callable if authorized
    // Test that distribute ... 
    // ... is only callable if authorized
    // ... "Mismatched arrays" error 
    // ... adjusts balances & distributes token correctly 
    // ... handles insufficient balances correctly
    // ... emits Distribute event 
    // Test that setGovernanceVault can be only called by admin
    // Test that setGovernanceVault sets the GovernanceVault
    // Test that setPurchaseTracker can be only called by admin
    // Test that setPurchaseTracker sets the PurchaseTracker
}
