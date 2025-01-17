// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import "@baal/BaalSummoner.sol";
import "../src/CustomBaal.sol";
import "../src/CommunityVault.sol";

/**
 * @notice Example Foundry script that:
 *  1) Deploys a new BaalSummoner
 *  2) Deploys a CustomBaal
 *  3) setAddrs(...) so Summoner uses the CustomBaal instead of default Baal
 */
contract DeployCustomBaalSummoner is Script {
    // Addresses from your block explorer reference:
    address constant GNOSIS_SINGLETON         = 0x69f4D1788e39c87893C980c06EdF4b7f686e2938;
    address constant GNOSIS_FALLBACK_LIBRARY  = 0x017062a1dE2FE6b99BE3d9d37841FeD19F573804;
    address constant GNOSIS_MULTISEND_LIBRARY = 0x998739BFdAAdde7C933B942a68053933098f9EDa;
    address constant GNOSIS_SAFE_PROXY_FACTORY= 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;
    address constant MODULE_PROXY_FACTORY     = 0x00000000000DC7F163742Eb4aBEf650037b1f588;
    address constant LOOT_SINGLETON           = 0x00768B047f73D88b6e9c14bcA97221d6E179d468;
    address constant SHARES_SINGLETON         = 0x52acf023d38A31f7e7bC92cCe5E68d36cC9752d6;

    function run() external {
        vm.startBroadcast();

        // 1) Deploy a fresh BaalSummoner
        BaalSummoner summoner = new BaalSummoner();
        summoner.initialize(); // set up ownership, UUPS, etc.
        console.log("BaalSummoner deployed at:", address(summoner));

        // 2) Deploy the CustomBaal
        CustomBaal customBaalMaster = new CustomBaal();
        console.log("CustomBaal master at:", address(customBaalMaster));

        // 3) Summoner.setAddrs to update `_template` with customBaalMaster
        //    but keep the other addresses found on sepolia block explorer
        summoner.setAddrs(
            payable(address(customBaalMaster)), // _template
            GNOSIS_SINGLETON,                   // _gnosisSingleton
            GNOSIS_FALLBACK_LIBRARY,            // _gnosisFallbackLibrary
            GNOSIS_MULTISEND_LIBRARY,           // _gnosisMultisendLibrary
            GNOSIS_SAFE_PROXY_FACTORY,          // _gnosisSafeProxyFactory
            MODULE_PROXY_FACTORY,               // _moduleProxyFactory
            LOOT_SINGLETON,                     // _lootSingleton
            SHARES_SINGLETON                    // _sharesSingleton
        );

        console.log("Summoner _template set to CustomBaal:", address(customBaalMaster));

        vm.stopBroadcast();
    }
}
