// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./HatsDeployment.s.sol";

import "@baal/Baal.sol";
import "@baal/BaalSummoner.sol";

import "../src/CommunityVault.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/GovernanceVault.sol";

import "@hamza-escrow/SystemSettings.sol";
import "@hamza-escrow/PaymentEscrow.sol";
import "@hamza-escrow/EscrowMulticall.sol";

import "../src/HamzaGovernor.sol";
import { HamzaGovernor } from "../src/HamzaGovernor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import "../src/PurchaseTracker.sol";
import "@hamza-escrow/IPurchaseTracker.sol";

import { SafeTransactionHelper } from "./utils/SafeTransactionHelper.s.sol";

/**
 * @title DeployHamzaVault
 * @notice Runs the HatsDeployment script first, then uses the
 *         returned Safe address to deploy and configure the Baal DAO,
 *         the community vault, governance token, governance vault, etc.
 */
contract DeployHamzaVault is Script {
    using stdJson for string;
    
    // (A) Deployed BaalSummoner on Sepolia
    address constant BAAL_SUMMONER = 0x72DdD6F967ecb17f6f8eCaebd8B6FdA6Cc91Cff0; 

    // Key addresses & params
    address public OWNER_ONE;
    address public OWNER_TWO;  // read from config

    uint256 internal deployerPk;

    uint256 public adminHatId; // from HatsDeployment

    address public hamzaToken; // the BAAL's loot token
    address payable public governorAddr;

    address public systemSettingsAddr;

    address public purchaseTrackerAddr;

    address public escrowAddr;
    
    // Store these values to avoid stack depth issues
    address public safeAddr;
    address public hats;
    address public hatsSecurityContextAddr;
    uint256 public daoHatId;
    string public config;

    function run()
        external
        returns (
            address hamzaBaal,
            address payable communityVault,
            address governanceToken,
            address governanceVault,
            address _safeAddress,
            address _hatsSecurityContext
        )
    {
        // 1) Read config file
        config = vm.readFile("./config.json");

        // read mode from config
        string memory mode = config.readString(".mode");

        // 2) Set up owners
        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("Deploy"))) {
            // 2) load deployer private key
            deployerPk = vm.envUint("PRIVATE_KEY");
            OWNER_ONE = vm.addr(deployerPk);
        }
        else {
            // 2) admin not from deployer private key
            deployerPk = uint256(0x123456789abcdef);
            OWNER_ONE = vm.addr(deployerPk);
        }

        // Read the second owner from config
        OWNER_TWO = config.readAddress(".owners.ownerTwo");

        // 3) Deploy all hats + new Gnosis Safe
        (
            address _safeAddr,
            address _hats,
            uint256 _adminHatId,
            uint256 _daoHatId,
            address _hatsSecurityContextAddr
        ) = deployHats();
        
        // Store values in contract storage to avoid stack depth issues
        safeAddr = _safeAddr;
        hats = _hats;
        adminHatId = _adminHatId;
        daoHatId = _daoHatId;
        hatsSecurityContextAddr = _hatsSecurityContextAddr;

        // 4) Start broadcast for subsequent deployments
        vm.startBroadcast(deployerPk);

        // 5-8) Deploy Community Vault and Baal DAO
        (address newBaalAddr, address payable vault, address lootTokenAddr) = deployBaalAndCommunityVault();
        
        // 9-10) Deploy governance token and vault
        (address govTokenAddr, address govVaultAddr) = deployGovernanceContracts(
            ISecurityContext(hatsSecurityContextAddr), 
            lootTokenAddr, 
            vault
        );
        
        // 11-14) Deploy Timelock and Governor
        address timelockAddr = deployGovernorAndTimelock(govTokenAddr);
        
        // 15-16) Deploy PurchaseTracker, PaymentEscrow, and EscrowMulticall
        deployEscrowContracts(vault, lootTokenAddr);
        
        vm.stopBroadcast();

        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("Deploy"))) {
            logDeployedAddresses(
                newBaalAddr,
                vault,
                govTokenAddr,
                govVaultAddr,
                timelockAddr
            );
        }

        // Return addresses
        return (
            newBaalAddr,             // hamzaBaal
            payable(vault),          // communityVault
            govTokenAddr,            // governanceToken
            govVaultAddr,            // governanceVault
            safeAddr,                // safeAddress
            hatsSecurityContextAddr  // hatsSecurityContext
        );
    }
    
    function deployHats() internal returns (
        address _safeAddr,
        address _hats,
        uint256 _adminHatId,
        uint256 _daoHatId,
        address _hatsSecurityContextAddr
    ) {
        HatsDeployment hatsDeployment = new HatsDeployment();
        
        address eligibilityModule;
        address toggleModule;
        uint256 arbiterHatId;
        uint256 systemHatId;
        uint256 pauserHatId;
        
        (
            _safeAddr,
            _hats,
            eligibilityModule,
            toggleModule,
            _hatsSecurityContextAddr,
            _adminHatId,
            arbiterHatId,
            _daoHatId,
            systemHatId,
            pauserHatId
        ) = hatsDeployment.run();
        
        return (
            _safeAddr,
            _hats,
            _adminHatId,
            _daoHatId,
            _hatsSecurityContextAddr
        );
    }
    
    function deployBaalAndCommunityVault() internal returns (
        address newBaalAddr,
        address payable vault,
        address lootTokenAddr
    ) {
        // 5) Deploy the Community Vault
        CommunityVault communityVault = new CommunityVault(hatsSecurityContextAddr);
        vault = payable(address(communityVault));

        // 6) Summon the Baal DAO
        BaalSummoner summoner = BaalSummoner(BAAL_SUMMONER);

        // read BAAL parameters from config
        string memory sharesName       = config.readString(".baal.sharesName");
        string memory sharesSymbol     = config.readString(".baal.sharesSymbol");
        bool pauseSharesOnInit         = config.readBool(".baal.pauseSharesOnInit");
        bool pauseLootOnInit           = config.readBool(".baal.pauseLootOnInit");
        uint256 sharesToMintForSafe    = config.readUint(".baal.safeSharesToMint");

        // pass these into the Baal initialization
        address _forwarder       = address(0);
        address _lootToken       = address(0);
        address _sharesToken     = address(0);
        address _communityVault  = address(vault);

        // Build the initParams for Baal
        bytes memory initParams = abi.encode(
            sharesName,
            sharesSymbol,
            address(0), // setUp safe 
            _forwarder,
            _lootToken,
            _sharesToken,
            _communityVault
        );

        // 7) Prepare Baal initialization actions
        bytes[] memory initActions = prepareBaalInitActions(pauseSharesOnInit, pauseLootOnInit, sharesToMintForSafe, vault);

        // 8) Summon Baal
        newBaalAddr = summoner.summonBaal(initParams, initActions, uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % 100);

        // fetch loot token address (Baal's "loot token")
        lootTokenAddr = address(Baal(newBaalAddr).lootToken());
        hamzaToken = lootTokenAddr;
        
        return (newBaalAddr, vault, lootTokenAddr);
    }
    
    function prepareBaalInitActions(
        bool pauseSharesOnInit,
        bool pauseLootOnInit,
        uint256 sharesToMintForSafe,
        address vault
    ) internal view returns (bytes[] memory initActions) {
        // (A) Mint shares to the Safe
        console2.log("safeAddr", safeAddr);
        bytes memory mintSharesCall = abi.encodeWithSelector(
            Baal.mintShares.selector,
            _singleAddressArray(safeAddr),
            _singleUint256Array(sharesToMintForSafe) // from config
        );

        // (B) Set the initial pause states (loot is unpaused, shares can be paused, etc.)
        bytes memory setAdminConfigCall = abi.encodeWithSelector(
            Baal.setAdminConfig.selector,
            pauseSharesOnInit, // pauseShares
            pauseLootOnInit    // pauseLoot
        );

        // (C) Lock the manager role
        bytes memory lockManagerCall = abi.encodeWithSelector(
            Baal.lockManager.selector
        );

        // (D) Mint loot tokens to Owner and to the Vault
        uint256 userLootAmount  = config.readUint(".baal.userLootAmount");
        uint256 vaultLootAmount = config.readUint(".baal.vaultLootAmount");

        address[] memory recipients = new address[](2);
        recipients[0] = OWNER_ONE;
        recipients[1] = vault; // Use the vault address that was passed in

        uint256[] memory lootAmounts = new uint256[](2);
        lootAmounts[0] = userLootAmount * 10 ** 18;
        lootAmounts[1] = vaultLootAmount * 10 ** 18;

        bytes memory mintLootCall = abi.encodeWithSelector(
            Baal.mintLoot.selector,
            recipients,
            lootAmounts
        );

        // (E) Set Governance Configuration
        uint32 votingPeriod = uint32(config.readUint(".baal.votingPeriod"));
        uint32 gracePeriod = uint32(config.readUint(".baal.gracePeriod"));
        uint256 proposalOffering = config.readUint(".baal.proposalOffering");
        uint256 quorumPercent = config.readUint(".baal.quorumPercent");
        uint256 sponsorThreshold = config.readUint(".baal.sponsorThreshold");
        uint256 minRetentionPercent = config.readUint(".baal.minRetentionPercent");

        bytes memory setGovernanceConfigCall = abi.encodeWithSelector(
            Baal.setGovernanceConfig.selector,
            abi.encode(votingPeriod, gracePeriod, proposalOffering, quorumPercent, sponsorThreshold, minRetentionPercent)
        );
        
        // Combine all Baal init actions
        initActions = new bytes[](5);
        initActions[0] = mintSharesCall;
        initActions[1] = setAdminConfigCall;
        initActions[2] = lockManagerCall;
        initActions[3] = mintLootCall;
        initActions[4] = setGovernanceConfigCall;
        
        return initActions;
    }
    
    function deployGovernanceContracts(
        ISecurityContext securityContext,
        address lootTokenAddr,
        address payable vault
    ) internal returns (
        address govTokenAddr,
        address govVaultAddr
    ) {
        // 9) Deploy governance token
        string memory govTokenName   = config.readString(".governanceToken.name");
        string memory govTokenSymbol = config.readString(".governanceToken.symbol");

        GovernanceToken govToken = new GovernanceToken(
            securityContext, 
            IERC20(lootTokenAddr),
            govTokenName,
            govTokenSymbol
        );
        
        govTokenAddr = address(govToken);

        // 10) Deploy governance vault, reading vestingPeriod from config
        uint256 vestingPeriod = config.readUint(".governanceVault.vestingPeriod");

        GovernanceVault govVault = new GovernanceVault(
            lootTokenAddr,
            GovernanceToken(address(govToken)),
            vestingPeriod
        );
        
        govVaultAddr = address(govVault);

        // link the community vault <-> governance vault
        CommunityVault(vault).setGovernanceVault(address(govVault), lootTokenAddr);
        govVault.setCommunityVault(vault);
        
        return (govTokenAddr, govVaultAddr);
    }
    
    function deployGovernorAndTimelock(address govTokenAddr) internal returns (address timelockAddr) {
        // 11) Deploy Timelock + Governor
        uint256 timelockDelay = config.readUint(".governor.timelockDelay");

        address[] memory empty;
        TimelockController timelock = new TimelockController(
            timelockDelay,
            empty,
            empty,
            OWNER_ONE
        );
        
        timelockAddr = address(timelock);

        HamzaGovernor governor = new HamzaGovernor(
            GovernanceToken(govTokenAddr), 
            timelock
        );

        governorAddr = payable(address(governor));

        // 12) Deploy SystemSettings
        uint256 feeBPS = config.readUint(".systemSettings.feeBPS");
        SystemSettings systemSettings = new SystemSettings(
            ISecurityContext(hatsSecurityContextAddr),
            safeAddr,
            feeBPS
        );
        systemSettingsAddr = address(systemSettings);

        // 13) Grant roles in Timelock
        timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
        timelock.grantRole(0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, address(governor));

        // 14) grant timelock dao role to the governor
        {
            bytes memory data = abi.encodeWithSelector(
                Hats.mintHat.selector,
                daoHatId,
                address(timelock)
            );

            SafeTransactionHelper.execTransaction(
                safeAddr,
                hats,
                0,
                data,
                OWNER_ONE
            );
        }
        
        return timelockAddr;
    }
    
    function deployEscrowContracts(
        address payable vault,
        address lootTokenAddr
    ) internal {
        bool autoRelease = config.readBool(".escrow.autoRelease");
        
        // 15) Deploy PurchaseTracker
        PurchaseTracker purchaseTracker = new PurchaseTracker(vault, lootTokenAddr);

        //setPurchaseTracker in community vault
        CommunityVault(vault).setPurchaseTracker(address(purchaseTracker), lootTokenAddr);

        purchaseTrackerAddr = address(purchaseTracker);

        // 16) Deploy PaymentEscrow 
        PaymentEscrow paymentEscrow = new PaymentEscrow(
            ISecurityContext(hatsSecurityContextAddr),
            ISystemSettings(systemSettingsAddr),
            autoRelease,
            IPurchaseTracker(address(purchaseTracker))
        );

        escrowAddr = address(paymentEscrow);

        // authorize the escrow 
        purchaseTracker.authorizeEscrow(address(paymentEscrow));

        // 17) Deploy EscrowMulticall (without storing the reference)
        new EscrowMulticall();
    }
    
    function logDeployedAddresses(
        address newBaalAddr,
        address vault,
        address govTokenAddr,
        address govVaultAddr,
        address timelockAddr
    ) internal view {
        console2.log("Owner One (from PRIVATE_KEY):", OWNER_ONE);
        console2.log("Owner Two (from config):     ", OWNER_TWO);

        console2.log("CommunityVault deployed at:", vault);

        console2.log("BaalSummoner at:", BAAL_SUMMONER);
        console2.log("Baal (Hamza Vault) deployed at:", newBaalAddr);

        console2.log("Loot token address:", hamzaToken);

        console2.log("GovernanceToken deployed at:", govTokenAddr);
        console2.log("GovernanceVault deployed at:", govVaultAddr);
        console2.log("Governor deployed at:", governorAddr);
        console2.log("SystemSettings deployed at:", systemSettingsAddr);

        console2.log("Timelock deployed at:", timelockAddr);
        console2.log("PurchaseTracker deployed at:", purchaseTrackerAddr);
        console2.log("PaymentEscrow deployed at:", escrowAddr);
        console2.log("-----------------------------------------------");
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
