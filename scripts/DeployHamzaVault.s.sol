// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./HatsDeployment.s.sol";

import "@baal/Baal.sol";
import "@baal/BaalSummoner.sol";

import "../src/CommunityVault.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/GovernanceVault.sol";


import "../src/HamzaGovernor.sol";
import { HamzaGovernor } from "../src/HamzaGovernor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DeployHamzaVault
 * @notice Runs the HatsDeployment script first, then uses the
 *         returned Safe address to deploy and configure the Baal DAO.
 */
contract DeployHamzaVault is Script {
    // (A) Deployed BaalSummoner on Sepolia
    address constant BAAL_SUMMONER = 0x33267E2d3decebCae26FA8D837Ef3F7608367ab2; 

    // addresses for loot recipients, etc.

    address public constant OWNER_ONE = 0x1310cEdD03Cc8F6aE50F2Fb93848070FACB042b8;
    address constant OWNER_TWO = 0x1542612fee591eD35C05A3E980bAB325265c06a3;

    uint256 internal deployerPk;

    uint256 public adminHatId;

    address public hamzaToken;

    function run() external 
    returns (
        address hamzaBaal,
        address payable communityVault,
        address governanceToken,
        address governanceVault,
        address safeAddress,
        address hatsSecurityContext
      ) 
    {

        // 1) Deploy all hats + new Gnosis Safe
        HatsDeployment hatsDeployment = new HatsDeployment();
        (
            address safeAddr,
            address hats,
            address eligibilityModule,
            address toggleModule,
            address hatsSecurityContextAddr,
            uint256 _adminHatId,
            uint256 arbiterHatId,
            uint256 daoHatId,
            uint256 systemHatId,
            uint256 pauserHatId
        ) = hatsDeployment.run();

        adminHatId = _adminHatId;
    

        console2.log("Using Safe from HatsDeployment at:", safeAddr);

        deployerPk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPk);


        // 2) Deploy the Community Vault
        CommunityVault vault = new CommunityVault(hatsSecurityContextAddr);

        console2.log("CommunityVault deployed at:", address(vault));
        
        // 3) Summon the Baal DAO
        BaalSummoner summoner = BaalSummoner(BAAL_SUMMONER);
        console2.log("BaalSummoner at:", address(summoner));

        // Prepare initialization params for Baal
        string memory name       = "Hamza Shares";   
        string memory symbol     = "HS";
        address _forwarder       = address(0);
        address _lootToken       = address(0);
        address _sharesToken     = address(0);
        address _communityVault  = address(vault);

        // These params are for the custom Baal
        bytes memory initParams = abi.encode(
            name,
            symbol,
            address(0), //setups safe 
            _forwarder,
            _lootToken,
            _sharesToken,
            _communityVault
        );

        // 4) define the initActions for Baal

        // (A) Mint 1 share to the Safe (admin multisig)
        bytes memory mintSharesCall = abi.encodeWithSelector(
            Baal.mintShares.selector,
            _singleAddressArray(safeAddr),
            _singleUint256Array(1)
        );

        // (B) Unpause loot token transfers, keep shares paused
        bytes memory unpauseLootCall = abi.encodeWithSelector(
            Baal.setAdminConfig.selector,
            true,   // pauseShares = true
            false   // pauseLoot   = false
        );

        // (C) Lock the manager role
        bytes memory lockManagerCall = abi.encodeWithSelector(
            Baal.lockManager.selector
        );

        // (D) Mint 100 loot tokens (50 to OWNER_ONE, 50 to the vault)
        address[] memory recipients = new address[](2);
        recipients[0] = OWNER_ONE;
        recipients[1] = address(vault);

        uint256[] memory lootAmounts = new uint256[](2);
        lootAmounts[0] = 50;
        lootAmounts[1] = 50;

        bytes memory mintLootCall = abi.encodeWithSelector(
            Baal.mintLoot.selector,
            recipients,
            lootAmounts
        );

        bytes[] memory initActions = new bytes[](4);
        initActions[0] = mintSharesCall;
        initActions[1] = unpauseLootCall;
        initActions[2] = lockManagerCall;
        initActions[3] = mintLootCall;

        // 5) Summon Baal
        address newBaalAddr = summoner.summonBaal(initParams, initActions, 9);
        console2.log("Baal (Hamza Vault) deployed at:", newBaalAddr);

        // fetch loot token address 
        address lootTokenAddr = address(Baal(newBaalAddr).lootToken());

        hamzaToken = lootTokenAddr;

        console2.log("Loot token address:", lootTokenAddr);

        // deploy governance token
        GovernanceToken govToken = new GovernanceToken(
            IERC20(lootTokenAddr),
            "HamGov",
            "HAM"
        );

        console2.log("GovernanceToken deployed at:", address(govToken));

        // deploy governance vault
        GovernanceVault govVault = new GovernanceVault(
            lootTokenAddr,
            GovernanceToken(address(govToken)),
            30
        );

        CommunityVault(vault).setGovernanceVault(address(govVault), lootTokenAddr);

        govVault.setCommunityVault(address(vault));

        console2.log("GovernanceVault deployed at:", address(govVault));

        address[] memory empty;

        TimelockController timelock = new TimelockController(1, empty, empty, OWNER_ONE);

        HamzaGovernor governor = new HamzaGovernor(govToken, timelock);

        timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));

        console2.log("Governor deployed at:", address(governor));

        vm.stopBroadcast();

        return (
            newBaalAddr,        // hamzaBaal
            payable(address(vault)),     // communityVault
            address(govToken),  // governanceToken
            address(govVault),  // governanceVault
            safeAddr,           // safeAddress
            hatsSecurityContextAddr // hatsSecurityContext
        );
    }

    // Helper Functions
    function _singleAddressArray(address _addr) private pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = _addr;
        return arr;
    }

    function _singleUint256Array(uint256 _val) private pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = _val;
        return arr;
    }
}
