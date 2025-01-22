// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/security/SecurityContext.sol";
import "../src/GovernanceVault.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/utils/TestToken.sol";

contract GovernanceVaultTest is Test {
    SecurityContext _securityContext;
    GovernanceVault _vault;
    GovernanceToken _govToken;
    TestToken _lootToken;

    address _admin;
    address _account1;
    address _account2;
    address _account3;

    //bytes32 constant BURNER_ROLE = 0x0;
    //bytes32 constant MINTER_ROLE = 0x1;

    function setUp() public {
        _admin = address(0x12);
        _account1 = address(0x13);
        _account2 = address(0x14);
        _account3 = address(0x15);

        vm.deal(_admin, 1 ether);
        vm.deal(_account1, 1 ether);
        vm.deal(_account2, 1 ether);
        vm.deal(_account3, 1 ether);

        vm.startPrank(_admin);
        _securityContext = new SecurityContext(_admin);
        _lootToken = new TestToken("LOOT", "LOOT");
        _govToken = new GovernanceToken("GOV", "GOV");
        _vault = new GovernanceVault(_lootToken, _govToken, 0);

        //securityContext.grantRole(BURNER_ROLE,  _vault);
        //securityContext.grantRole(MINTER_ROLE, _vault);

        _lootToken.mint(_account1, 10000000000);
        _lootToken.mint(_account2, 10000000000);
        _lootToken.mint(_account3, 10000000000);
        vm.stopPrank();
    }

    function testHappyDeposit() public {
        uint256 amount = 100;

        uint256 initialLootBalance = _lootToken.balanceOf(_account1);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);

        //deposit/stake
        vm.startPrank(_account1);
        _lootToken.approve(address(_vault), amount);
        _vault.stake(amount);
        vm.stopPrank();

        assertEq(_govToken.balanceOf(_account1), amount);
        assertEq(_lootToken.balanceOf(_account1), initialLootBalance - amount);
        assertEq(_lootToken.balanceOf(address(_vault)), amount);
    }

    function testHappyDepositAndBurn() public {
        uint256 amount = 100;

        uint256 initialLootBalance = _lootToken.balanceOf(_account1);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);

        //deposit/stake
        vm.startPrank(_account1);
        _lootToken.approve(address(_vault), amount);
        _vault.stake(amount);

        //burn the same amount 
        assertEq(_govToken.balanceOf(_account1), amount);
        vm.startPrank(_account1);
        _vault.burn(amount);
        vm.stopPrank();

        assertEq(_govToken.balanceOf(_account1), 0);
        assertEq(_lootToken.balanceOf(_account1), initialLootBalance);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);
    }

    function testMultiDeposit() public {
        uint256 amount1 = 100;
        uint256 amount2 = 100;
        uint256 sum = amount1 + amount2;

        uint256 initialLootBalance = _lootToken.balanceOf(_account1);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);

        //deposit/stake
        vm.startPrank(_account1);
        _lootToken.approve(address(_vault), sum);
        _vault.stake(amount1);
        _vault.stake(amount2);
        vm.stopPrank();

        assertEq(_govToken.balanceOf(_account1), sum);
        assertEq(_lootToken.balanceOf(_account1), initialLootBalance - sum);
        assertEq(_lootToken.balanceOf(address(_vault)), sum);
    }

    function testMultiDepositAndBurnExact() public {
        uint256 amount1 = 100;
        uint256 amount2 = 100;
        uint256 sum = amount1 + amount2;

        uint256 initialLootBalance = _lootToken.balanceOf(_account1);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);

        //deposit/stake
        vm.startPrank(_account1);
        _lootToken.approve(address(_vault), sum);
        _vault.stake(amount1);
        _vault.stake(amount2);

        //burn the same amount 
        assertEq(_govToken.balanceOf(_account1), sum);
        vm.startPrank(_account1);
        _vault.burn(sum);
        vm.stopPrank();

        assertEq(_govToken.balanceOf(_account1), 0);
        assertEq(_lootToken.balanceOf(_account1), initialLootBalance);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);
    }

    function testMultiDepositAndBurnUneven() public {
        uint256 amount1 = 100;
        uint256 amount2 = 100;
        uint256 sum = amount1 + amount2;

        uint256 initialLootBalance = _lootToken.balanceOf(_account1);
        assertEq(_lootToken.balanceOf(address(_vault)), 0);

        //deposit/stake
        vm.startPrank(_account1);
        _lootToken.approve(address(_vault), sum);
        _vault.stake(amount1);
        _vault.stake(amount2);

        //burn the same amount 
        assertEq(_govToken.balanceOf(_account1), sum);
        vm.startPrank(_account1);
        _vault.burn(sum-1);
        vm.stopPrank();

        assertEq(_govToken.balanceOf(_account1), 1);
        assertEq(_lootToken.balanceOf(_account1), initialLootBalance - 1);
        assertEq(_lootToken.balanceOf(address(_vault)), 1);
    }
}

