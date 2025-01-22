// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/security/SecurityContext.sol";
import "../src/GovernanceVault.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/utils/TestToken.sol";

contract GovernanceVaultTest is Test {
    SecurityContext securityContext;
    GovernanceVault vault;
    GovernanceToken govToken;
    TestToken lootToken;

    address admin;
    address account1;
    address account2;
    address account3;

    //bytes32 constant BURNER_ROLE = 0x0;
    //bytes32 constant MINTER_ROLE = 0x1;

    function setUp() public {
        admin = address(0x12);
        account1 = address(0x13);
        account2 = address(0x14);
        account3 = address(0x15);

        vm.deal(admin, 1 ether);
        vm.deal(account1, 1 ether);
        vm.deal(account2, 1 ether);
        vm.deal(account3, 1 ether);

        vm.startPrank(admin);
        securityContext = new SecurityContext(admin);
        lootToken = new TestToken("LOOT", "LOOT");
        govToken = new GovernanceToken(lootToken, "GOV", "GOV");
        vault = new GovernanceVault(lootToken, govToken, 0);

        //securityContext.grantRole(BURNER_ROLE,  _vault);
        //securityContext.grantRole(MINTER_ROLE, _vault);

        lootToken.mint(account1, 10000000000);
        lootToken.mint(account2, 10000000000);
        lootToken.mint(account3, 10000000000);
        vm.stopPrank();
    }

    function testHappyDeposit() public {
        uint256 amount = 100;

        uint256 initialLootBalance = lootToken.balanceOf(account1);
        assertEq(lootToken.balanceOf(address(vault)), 0);

        //deposit/stake
        vm.startPrank(account1);
        lootToken.approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();

        assertEq(govToken.balanceOf(account1), amount);
        assertEq(lootToken.balanceOf(account1), initialLootBalance - amount);
        assertEq(lootToken.balanceOf(address(vault)), amount);
    }

    function testHappyDepositAndBurn() public {
        uint256 amount = 100;

        uint256 initialLootBalance = lootToken.balanceOf(account1);
        assertEq(lootToken.balanceOf(address(vault)), 0);

        //deposit/stake
        vm.startPrank(account1);
        lootToken.approve(address(vault), amount);
        vault.stake(amount);

        //burn the same amount 
        assertEq(govToken.balanceOf(account1), amount);
        vm.startPrank(account1);
        vault.burn(amount);
        vm.stopPrank();

        assertEq(govToken.balanceOf(account1), 0);
        assertEq(lootToken.balanceOf(account1), initialLootBalance);
        assertEq(lootToken.balanceOf(address(vault)), 0);
    }

    function testMultiDeposit() public {
        uint256 amount1 = 100;
        uint256 amount2 = 100;
        uint256 sum = amount1 + amount2;

        uint256 initialLootBalance = lootToken.balanceOf(account1);
        assertEq(lootToken.balanceOf(address(vault)), 0);

        //deposit/stake
        vm.startPrank(account1);
        lootToken.approve(address(vault), sum);
        vault.stake(amount1);
        vault.stake(amount2);
        vm.stopPrank();

        assertEq(govToken.balanceOf(account1), sum);
        assertEq(lootToken.balanceOf(account1), initialLootBalance - sum);
        assertEq(lootToken.balanceOf(address(vault)), sum);
    }

    function testMultiDepositAndBurnExact() public {
        uint256 amount1 = 100;
        uint256 amount2 = 100;
        uint256 sum = amount1 + amount2;

        uint256 initialLootBalance = lootToken.balanceOf(account1);
        assertEq(lootToken.balanceOf(address(vault)), 0);

        //deposit/stake
        vm.startPrank(account1);
        lootToken.approve(address(vault), sum);
        vault.stake(amount1);
        vault.stake(amount2);

        //burn the same amount 
        assertEq(govToken.balanceOf(account1), sum);
        vm.startPrank(account1);
        vault.burn(sum);
        vm.stopPrank();

        assertEq(govToken.balanceOf(account1), 0);
        assertEq(lootToken.balanceOf(account1), initialLootBalance);
        assertEq(lootToken.balanceOf(address(vault)), 0);
    }

    function testMultiDepositAndBurnUneven() public {
        uint256 amount1 = 100;
        uint256 amount2 = 100;
        uint256 sum = amount1 + amount2;

        uint256 initialLootBalance = lootToken.balanceOf(account1);
        assertEq(lootToken.balanceOf(address(vault)), 0);

        //deposit/stake
        vm.startPrank(account1);
        lootToken.approve(address(vault), sum);
        vault.stake(amount1);
        vault.stake(amount2);

        //burn the same amount 
        assertEq(govToken.balanceOf(account1), sum);
        vm.startPrank(account1);
        vault.burn(sum-1);
        vm.stopPrank();

        assertEq(govToken.balanceOf(account1), 1);
        assertEq(lootToken.balanceOf(account1), initialLootBalance - 1);
        assertEq(lootToken.balanceOf(address(vault)), 1);
    }
}

