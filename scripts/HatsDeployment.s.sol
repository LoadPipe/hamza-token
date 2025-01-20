// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";

// Hats Protocol
import { Hats } from "@hats-protocol/Hats.sol";

// Hats modules
import { EligibilityModule } from "../src/security/hats/EligibilityModule.sol";
import { ToggleModule } from "../src/security/hats/ToggleModule.sol";

// Security context & system
import { HatsSecurityContext } from "../src/security/HatsSecurityContext.sol";
import { IHatsSecurityContext } from "../src/security/IHatsSecurityContext.sol";

// Roles
import { Roles } from "../src/security/Roles.sol";

import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";


contract HatsDeployment is Script {
    // (B) Gnosis Safe singleton & factory on Sepolia
    address constant SAFE_SINGLETON = 0x69f4D1788e39c87893C980c06EdF4b7f686e2938;
    address constant SAFE_FACTORY  = 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;

    address public adminAddress1   = 0x1310cEdD03Cc8F6aE50F2Fb93848070FACB042b8;
    address public adminAddress2 = 0x1542612fee591eD35C05A3E980bAB325265c06a3;    // The admin address
    address public vaultAddress   = address(0x11);     // The vault that will receive fees
    address public arbiterAddress = address(0x12);     // The arbiter address
    address public daoAddress     = address(0x13);     // The DAO address
    bool    internal autoRelease    = true;             // Whether PaymentEscrow starts with autoRelease

    Hats public hats;
    EligibilityModule public eligibilityModule;
    ToggleModule public toggleModule;
    HatsSecurityContext public securityContext;

    uint256 public adminHatId;
    uint256 public arbiterHatId;
    uint256 public daoHatId;
    uint256 public topHatId;
    

    function run() external {
        vm.startBroadcast(adminAddress1);
        console.log("Starting Hats deployment");

        hats = Hats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137);// this is the hats contract on all chains
        //hats = new Hats("Hats Protocol v1", "ipfs://bafkreiflezpk3kjz6zsv23pbvowtatnd5hmqfkdro33x5mh2azlhne3ah4"); 
        //use this just for amoy. the above address is on polygon and base

        // 1. Deploy admin Gnosis Safe
        GnosisSafeProxyFactory factory = GnosisSafeProxyFactory(SAFE_FACTORY);

        address[] memory owners = new address[](2);
        owners[0] = adminAddress1;
        owners[1] = adminAddress2;

        bytes memory setupData = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,      // Owners array
            1,           // Threshold (1-of-2)
            address(0),  // No `to` delegate call
            "",          // No `data`
            address(0),  // No fallback handler
            address(0),  // No payment token
            0,           // Payment = 0
            address(0)   // No payment receiver
        );

        address safeAddr = address(factory.createProxy(
            SAFE_SINGLETON,
            setupData
        ));

        vm.stopBroadcast();
        vm.startBroadcast(safeAddr);

        // 2. Deploy Eligibility & Toggle Modules 
        // pass admin address to each module’s constructor
        eligibilityModule = new EligibilityModule(safeAddr);
        toggleModule = new ToggleModule(safeAddr);

        // 3. Mint the Top Hat to admin 

        // details in json format uploaded to IPFS
        // {"type":"1.0","data":{"name":"sxxs","description":"xssxsxsx"}}
        adminHatId = hats.mintTopHat(
        safeAddr,
        "ipfs://bafkreih3vqseitn7pijlkl2jcawbjrhae3dfb2pakqtgd4epvxxfulwoqq", //from ipfs/admin.json
        ""
        );

        // 4. Create child hats

        // adminHatId = hats.createHat(
        // topHatId,
        // "ipfs://bafkreih3vqseitn7pijlkl2jcawbjrhae3dfb2pakqtgd4epvxxfulwoqq", //from ipfs/admin.json
        // 2,                      // maxSupply
        // address(eligibilityModule),
        // address(toggleModule),
        // true,                   // mutable
        // ""// no image 
        // );

        arbiterHatId = hats.createHat(
            adminHatId,
            "ipfs://bafkreicbhbvddt2f475inukntzh6n72ehm4iyljstyyjsmizdsojmbdase", //from ipfs/arbiter.json
            2,                      // maxSupply
            address(eligibilityModule),
            address(toggleModule),
            true,                   // mutable
            ""// no image 
        );

        daoHatId = hats.createHat(
            adminHatId,
            "ipfs://bafkreic2f5b6ykdvafs5nhkouruvlql73caou5etgdrx67yt6ofp6pwf24", //from ipfs/dao.json
            2, 
            address(eligibilityModule),
            address(toggleModule),
            true, 
            ""
        );

        uint256 systemHatId = hats.createHat(
            adminHatId,
            "ipfs://bafkreie2vxohaw7cneknlwv6hq7h4askkv6jfcadho6efz5bxfx66fqu3q", //from ipfs/system.json
            2, 
            address(eligibilityModule),
            address(toggleModule),
            true, 
            ""
        );

        uint256 pauserHatId = hats.createHat(
            adminHatId,
            "ipfs://bafkreiczfbtftesggzcfnumcy7rfru665a77uyznbabdk5b6ftfo2hvjw4", //from ipfs/pauser.json
            2, 
            address(eligibilityModule),
            address(toggleModule),
            true, 
            ""
        );

        console.log("Arbiter Hat ID:", arbiterHatId);
        console.log("DAO Hat ID:", daoHatId);
        console.log("System Hat ID:", systemHatId);
        console.log("Pauser Hat ID:", pauserHatId);

        // 5. Deploy HatsSecurityContext & set role hats
        securityContext = new HatsSecurityContext(
            address(hats),
            adminHatId
        );

        // 6. Set the eligibility and toggle module
        eligibilityModule.setHatRules(adminHatId, true, true);
        eligibilityModule.setHatRules(arbiterHatId, true, true);
        eligibilityModule.setHatRules(daoHatId, true, true);
        eligibilityModule.setHatRules(systemHatId, true, true);
        eligibilityModule.setHatRules(pauserHatId, true, true);

        toggleModule.setHatStatus(adminHatId, true);
        toggleModule.setHatStatus(arbiterHatId, true);
        toggleModule.setHatStatus(daoHatId, true);
        toggleModule.setHatStatus(systemHatId, true);
        toggleModule.setHatStatus(pauserHatId, true);

        // 7. Mint the hats to the respective addresses
        // Mint the arbiter hat to the arbiter address
        hats.mintHat(arbiterHatId, adminAddress1);
        hats.mintHat(arbiterHatId, adminAddress2);

        // Mint the DAO hat to the DAO address
        hats.mintHat(daoHatId, adminAddress1);
        hats.mintHat(daoHatId, adminAddress2);

        // Mint the system hat to the admin address
        hats.mintHat(systemHatId, adminAddress1);
        hats.mintHat(systemHatId, adminAddress2);


        // Mint the pauser hat to the admin address
        hats.mintHat(pauserHatId, adminAddress1);
        hats.mintHat(pauserHatId, adminAddress2);

        // Map each role to the correct hat
        securityContext.setRoleHat(Roles.ARBITER_ROLE, arbiterHatId);
        securityContext.setRoleHat(Roles.DAO_ROLE,     daoHatId);
        securityContext.setRoleHat(Roles.SYSTEM_ROLE,  systemHatId);
        securityContext.setRoleHat(Roles.PAUSER_ROLE,  pauserHatId);

        vm.stopBroadcast();

        console.log("Hats deployed at:             ", address(hats));
        console.log("EligibilityModule deployed at:", address(eligibilityModule));
        console.log("ToggleModule deployed at:     ", address(toggleModule));
        console.log("safeAddr deployed at:         ", safeAddr);
        console.log("HatsSecurityContext deployed: ", address(securityContext));
    }
}
