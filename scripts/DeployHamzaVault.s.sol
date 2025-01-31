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
    // (A) Deployed BaalSummoner on Sepolia
    address constant BAAL_SUMMONER = 0x33267E2d3decebCae26FA8D837Ef3F7608367ab2; 

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

    function run()
        external
        returns (
            address hamzaBaal,
            address payable communityVault,
            address governanceToken,
            address governanceVault,
            address safeAddress,
            address hatsSecurityContext
        )
    {
        // 1) Read config file
        string memory config = vm.readFile("./config.json");

        // 2) Set up owners
        deployerPk = vm.envUint("PRIVATE_KEY");
        OWNER_ONE = vm.addr(deployerPk);

        // Read the second owner from config
        OWNER_TWO = stdJson.readAddress(config, ".owners.ownerTwo");

        console2.log("Owner One (from PRIVATE_KEY):", OWNER_ONE);
        console2.log("Owner Two (from config):     ", OWNER_TWO);

        // 3) Deploy all hats + new Gnosis Safe
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

        // 4) Start broadcast for subsequent deployments
        vm.startBroadcast(deployerPk);

        // 5) Deploy the Community Vault
        CommunityVault vault = new CommunityVault(hatsSecurityContextAddr);
        console2.log("CommunityVault deployed at:", address(vault));

        // 6) Summon the Baal DAO
        BaalSummoner summoner = BaalSummoner(BAAL_SUMMONER);
        console2.log("BaalSummoner at:", address(summoner));

        // read BAAL parameters from config
        string memory sharesName       = stdJson.readString(config, ".baal.sharesName");
        string memory sharesSymbol     = stdJson.readString(config, ".baal.sharesSymbol");
        bool pauseSharesOnInit         = stdJson.readBool(config, ".baal.pauseSharesOnInit");
        bool pauseLootOnInit           = stdJson.readBool(config, ".baal.pauseLootOnInit");
        uint256 sharesToMintForSafe    = stdJson.readUint(config, ".baal.safeSharesToMint");
        bool autoRelease               = stdJson.readBool(config, ".escrow.autoRelease");

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

        // 7) Build the initActions for Baal

        // (A) Mint shares to the Safe
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
        uint256 userLootAmount  = stdJson.readUint(config, ".baal.userLootAmount");
        uint256 vaultLootAmount = stdJson.readUint(config, ".baal.vaultLootAmount");

        address[] memory recipients = new address[](2);
        recipients[0] = OWNER_ONE;  
        recipients[1] = address(vault);

        uint256[] memory lootAmounts = new uint256[](2);
        lootAmounts[0] = userLootAmount;
        lootAmounts[1] = vaultLootAmount;

        bytes memory mintLootCall = abi.encodeWithSelector(
            Baal.mintLoot.selector,
            recipients,
            lootAmounts
        );

        // Combine all Baal init actions
        bytes[] memory initActions = new bytes[](4);
        initActions[0] = mintSharesCall;
        initActions[1] = setAdminConfigCall;
        initActions[2] = lockManagerCall;
        initActions[3] = mintLootCall;

        // 8) Summon Baal
        address newBaalAddr = summoner.summonBaal(initParams, initActions, 9);
        console2.log("Baal (Hamza Vault) deployed at:", newBaalAddr);

        // fetch loot token address (Baal's "loot token")
        address lootTokenAddr = address(Baal(newBaalAddr).lootToken());
        hamzaToken = lootTokenAddr;

        console2.log("Loot token address:", lootTokenAddr);

        // 9) Deploy governance token
        //    read from config
        string memory govTokenName   = stdJson.readString(config, ".governanceToken.name");
        string memory govTokenSymbol = stdJson.readString(config, ".governanceToken.symbol");

        GovernanceToken govToken = new GovernanceToken(
            IERC20(lootTokenAddr),
            govTokenName,
            govTokenSymbol
        );
        console2.log("GovernanceToken deployed at:", address(govToken));

        // 10) Deploy governance vault, reading vestingPeriod from config
        uint256 vestingPeriod = stdJson.readUint(config, ".governanceVault.vestingPeriod");

        GovernanceVault govVault = new GovernanceVault(
            lootTokenAddr,
            GovernanceToken(address(govToken)),
            vestingPeriod
        );

        // link the community vault <-> governance vault
        CommunityVault(vault).setGovernanceVault(address(govVault), lootTokenAddr);
        govVault.setCommunityVault(address(vault));

        console2.log("GovernanceVault deployed at:", address(govVault));

        // 11) Deploy Timelock + Governor
        //     read timelock delay from config
        uint256 timelockDelay = stdJson.readUint(config, ".governor.timelockDelay");

        address[] memory empty;
        TimelockController timelock = new TimelockController(
            timelockDelay,
            empty,
            empty,
            OWNER_ONE
        );

        HamzaGovernor governor = new HamzaGovernor(govToken, timelock);

        console2.log("Governor deployed at:", address(governor));
        governorAddr = payable(address(governor));

        // 12) Deploy SystemSettings
        // read feeBPS from config
        uint256 feeBPS = stdJson.readUint(config, ".systemSettings.feeBPS");
        SystemSettings systemSettings = new SystemSettings(
            IHatsSecurityContext(hatsSecurityContextAddr),
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
            console2.log("DAO hat minted to Timelock:", address(timelock));
        }

        // 15) Deploy PurchaseTracker
        PurchaseTracker purchaseTracker = new PurchaseTracker();
        console2.log("PurchaseTracker deployed at:", address(purchaseTracker));

        purchaseTrackerAddr = address(purchaseTracker);

        // 16) Deploy PaymentEscrow 
        PaymentEscrow paymentEscrow = new PaymentEscrow(
            IHatsSecurityContext(hatsSecurityContextAddr),
            ISystemSettings(address(systemSettings)),
            autoRelease,
            IPurchaseTracker(address(purchaseTracker))
        );

        escrowAddr = address(paymentEscrow);

        // authoruize the escrow 
        purchaseTracker.authorizeEscrow(address(paymentEscrow));

        // 16) Deploy EscrowMulticall
        EscrowMulticall escrowMulticall = new EscrowMulticall();

        console2.log("PaymentEscrow deployed at:", address(paymentEscrow));
        console2.log("EscrowMulticall deployed at:", address(escrowMulticall));

        vm.stopBroadcast();

        // Return addresses
        return (
            newBaalAddr,             // hamzaBaal
            payable(address(vault)), // communityVault
            address(govToken),       // governanceToken
            address(govVault),       // governanceVault
            safeAddr,                // safeAddress
            hatsSecurityContextAddr  // hatsSecurityContext
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
