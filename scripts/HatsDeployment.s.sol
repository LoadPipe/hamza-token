// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { SafeTransactionHelper } from "./utils/SafeTransactionHelper.s.sol";

// Minimal interface to read the Gnosis Safe's nonce.
interface IGnosisSafe {
    function nonce() external view returns (uint256);
}

// Hats Protocol
import { Hats } from "@hats-protocol/Hats.sol";
import { EligibilityModule } from "@hamza-escrow/hats/EligibilityModule.sol";
import { ToggleModule } from "@hamza-escrow/hats/ToggleModule.sol";
import { HatsSecurityContext } from "@hamza-escrow/security/HatsSecurityContext.sol";
import { ISecurityContext } from "@hamza-escrow/security/ISecurityContext.sol";
import { Roles } from "@hamza-escrow/security/Roles.sol";

import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

/**
 * @title HatsDeployment
 * @notice Script to deploy the Hats protocol contracts and a Gnosis Safe.
 */
contract HatsDeployment is Script {
    // Gnosis Safe singleton & factory on Sepolia
    address constant SAFE_SINGLETON = 0x69f4D1788e39c87893C980c06EdF4b7f686e2938;
    address constant SAFE_FACTORY   = 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;

    address public adminAddress2;

    // The newly deployed Safe
    address public deployedSafe;

    // Hats references
    Hats public hats;
    EligibilityModule public eligibilityModule;
    ToggleModule public toggleModule;
    HatsSecurityContext public securityContext;

    uint256 public adminHatId;
    uint256 public arbiterHatId;
    uint256 public daoHatId;
    uint256 public topHatId;
    uint256 public systemHatId;
    uint256 public pauserHatId;
    uint256 public minterHatId;
    uint256 public burnerHatId;

    // Deployer's private key and derived addresses
    uint256 internal deployerPk;
    address internal adminAddress1;

    /**
     * @dev Helper to execute transactions on the newly deployed safe.
     */
    function execTransaction(
        address to,
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        SafeTransactionHelper.execTransaction(to, target, value, data, adminAddress1);
    }

    /**
     * @notice Runs the deployment. Returns the newly deployed safe address and other hats data.
     */
    function run()
        external
        returns (
            address safeAddress,
            address hatsAddress,
            address eligibilityModuleAddress,
            address toggleModuleAddress,
            address securityContextAddress,
            uint256 _adminHatId,
            uint256 _arbiterHatId,
            uint256 _daoHatId,
            uint256 _systemHatId,
            uint256 _pauserHatId,
            uint256 _minterHatId, 
            uint256 _burnerHatId
        )
    {

        // 1) read config
        string memory config = vm.readFile("./config.json");
        adminAddress2 = stdJson.readAddress(config, ".owners.ownerTwo"); 
        
        // read mode from config
        string memory mode = stdJson.readString(config, ".mode");

        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("Deploy"))) {
            // 2) load deployer private key
            deployerPk = vm.envUint("PRIVATE_KEY");
            adminAddress1 = vm.addr(deployerPk);
        }
        else {
            // 2) admin not from deployer private key
            deployerPk = uint256(0x123456789abcdef);
            adminAddress1 = vm.addr(deployerPk);
        }

        vm.startBroadcast(deployerPk);


        // 3) Use existing Hats or deploy a new instance
        //    If you want to deploy a fresh Hats contract, uncomment the second line:
        hats = Hats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137);
        // hats = new Hats("Hats Protocol v1", "ipfs://...");

        // 4) Deploy a new Gnosis Safe (1-of-2 owners)
        GnosisSafeProxyFactory factory = GnosisSafeProxyFactory(SAFE_FACTORY);
        address[] memory owners = new address[](2);
        owners[0] = adminAddress1;
        owners[1] = adminAddress2;

        bytes memory setupData = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            1,        // threshold = 1
            address(0),
            "",
            address(0),
            address(0),
            0,
            address(0)
        );

        address safeAddr = address(factory.createProxy(SAFE_SINGLETON, setupData));
        deployedSafe = safeAddr;

        // 5) Deploy Eligibility & Toggle modules
        eligibilityModule = new EligibilityModule(safeAddr);
        toggleModule      = new ToggleModule(safeAddr);

        // 6) Mint Top Hat to the Safe (via the Safe)
        {
            bytes memory data = abi.encodeWithSelector(
                Hats.mintTopHat.selector,
                safeAddr,
                "ipfs://bafkreih3vqseitn7pijlkl2jcawbjrhae3dfb2pakqtgd4epvxxfulwoqq",
                ""
            );
            execTransaction(safeAddr, address(hats), 0, data);
        }
        adminHatId = uint256(hats.lastTopHatId()) << 224;

        // 7) Create child Hats
        arbiterHatId = createHat("ipfs://bafkreicbhbvddt2f475inukntzh6n72ehm4iyljstyyjsmizdsojmbdase", 2);
        daoHatId = createHat("ipfs://bafkreic2f5b6ykdvafs5nhkouruvlql73caou5etgdrx67yt6ofp6pwf24", 2);
        systemHatId = createHat("ipfs://bafkreie2vxohaw7cneknlwv6hq7h4askkv6jfcadho6efz5bxfx66fqu3q", 2);
        pauserHatId = createHat("ipfs://bafkreiczfbtftesggzcfnumcy7rfru665a77uyznbabdk5b6ftfo2hvjw4", 2);
        minterHatId = createHat("ipfs://bafkreiczfbtftesggzcfnumcy7rfru665a77uyznbabdk5b6ftfo2hvjw1", 100);
        burnerHatId = createHat("ipfs://bafkreiczfbtftesggzcfnumcy7rfru665a77uyznbabdk5b6ftfo2hvjw2", 100);

        // 8) Deploy HatsSecurityContext & set role hats
        securityContext = new HatsSecurityContext(address(hats), adminHatId);

        // 9) Configure eligibility + toggle modules
        setHatRules(adminHatId, true, true);
        setHatRules(arbiterHatId, true, true);
        setHatRules(daoHatId, true, true);
        setHatRules(systemHatId, true, true);
        setHatRules(pauserHatId, true, true);
        setHatRules(minterHatId, true, true);
        setHatRules(burnerHatId, true, true);
        
        setHatStatus(adminHatId, true);
        setHatStatus(arbiterHatId, true);
        setHatStatus(daoHatId, true);
        setHatStatus(systemHatId, true);
        setHatStatus(pauserHatId, true);
        setHatStatus(minterHatId, true);
        setHatStatus(burnerHatId, true);

        // 10) Mint hats to relevant addresses
        //Arbiter
        mintHat(arbiterHatId, adminAddress1);
        mintHat(arbiterHatId, adminAddress2);

        //DAO
        mintHat(daoHatId, adminAddress1);

        //System
        mintHat(systemHatId, adminAddress1);
        mintHat(systemHatId, adminAddress2);

        //Pauser
        mintHat(pauserHatId, adminAddress1);
        mintHat(pauserHatId, adminAddress2);

        //Minter 
        mintHat(minterHatId, adminAddress1);
        mintHat(minterHatId, adminAddress2);

        //Burner 
        mintHat(burnerHatId, adminAddress1);
        mintHat(burnerHatId, adminAddress2);

        // 11) Set role hats in the HatsSecurityContext
        setHatRole(arbiterHatId, Roles.ARBITER_ROLE);
        setHatRole(daoHatId, Roles.DAO_ROLE);
        setHatRole(systemHatId, Roles.SYSTEM_ROLE);
        setHatRole(pauserHatId, Roles.PAUSER_ROLE);
        setHatRole(minterHatId, Roles.MINTER_ROLE);
        setHatRole(burnerHatId, Roles.BURNER_ROLE);

        vm.stopBroadcast();

        if (keccak256(abi.encodePacked(mode)) == keccak256(abi.encodePacked("Deploy"))) {

            console2.log("-----------------------------------------------");
            console2.log("Admin Hat ID:", adminHatId);
            console2.log("Arbiter Hat ID:", arbiterHatId);
            console2.log("DAO Hat ID:    ", daoHatId);
            console2.log("System Hat ID: ", systemHatId);
            console2.log("Pauser Hat ID: ", pauserHatId);
            console2.log("Minter Hat ID: ", minterHatId);
            console2.log("Burner Hat ID: ", burnerHatId);

            console2.log("-----------------------------------------------");
            console2.log("Hats Address is:             ", address(hats));
            console2.log("EligibilityModule deployed at:", address(eligibilityModule));
            console2.log("ToggleModule deployed at:     ", address(toggleModule));
            console2.log("HatsSecurityContext deployed: ", address(securityContext));
            console2.log("Gnosis Safe deployed at:      ", deployedSafe);
            console2.log("-----------------------------------------------");
        }

        // Return all relevant addresses and hat IDs
        return (
            deployedSafe,
            address(hats),
            address(eligibilityModule),
            address(toggleModule),
            address(securityContext),
            adminHatId,
            arbiterHatId,
            daoHatId,
            systemHatId,
            pauserHatId,
            minterHatId,
            burnerHatId
        );
    }

    function createHat(string memory uri, uint32 maxSupply) private returns (uint256) {
        uint256 hatId = hats.getNextId(adminHatId);
        bytes memory data = abi.encodeWithSelector(
            Hats.createHat.selector,
            adminHatId,
            uri,
            maxSupply,
            address(eligibilityModule),
            address(toggleModule),
            true,
            ""
        );
        execTransaction(deployedSafe, address(hats), 0, data);
        return hatId;
    }

    function setHatRules(uint256 hatId, bool eligible, bool standing) private {
        bytes memory data = abi.encodeWithSelector(
            EligibilityModule.setHatRules.selector,
            hatId,
            eligible,
            standing
        );
        execTransaction(deployedSafe, address(eligibilityModule), 0, data);
    }

    function setHatStatus(uint256 hatId, bool active) private {
        bytes memory data = abi.encodeWithSelector(
            ToggleModule.setHatStatus.selector,
            hatId,
            active
        );
        execTransaction(deployedSafe, address(toggleModule), 0, data);
    }

    function mintHat(uint256 hatId, address recipient) private {
        bytes memory data = abi.encodeWithSelector(
            Hats.mintHat.selector,
            hatId,
            recipient
        );
        execTransaction(deployedSafe, address(hats), 0, data);
    }

    function setHatRole(uint256 hatId, bytes32 role) private {
        bytes memory data = abi.encodeWithSelector(
            HatsSecurityContext.setRoleHat.selector,
            role,
            hatId
        );
        execTransaction(deployedSafe, address(securityContext), 0, data);
    }
}
