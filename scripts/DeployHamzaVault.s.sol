// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";

import "@baal/Baal.sol";
import "@baal/BaalSummoner.sol";

import "../src/CommunityVault.sol";

contract DeployHamzaVault is Script {
    // (A) Deployed BaalSummoner on Sepolia
    address constant BAAL_SUMMONER = 0x33267E2d3decebCae26FA8D837Ef3F7608367ab2; //new summoner with custom baal

    // (B) Gnosis Safe singleton & factory on Sepolia
    address constant SAFE_SINGLETON = 0x69f4D1788e39c87893C980c06EdF4b7f686e2938;
    address constant SAFE_FACTORY  = 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;

    // (C) Two owners
    address constant OWNER_ONE = 0x1310cEdD03Cc8F6aE50F2Fb93848070FACB042b8;
    address constant OWNER_TWO = 0x1542612fee591eD35C05A3E980bAB325265c06a3;

    // Deploy & configure the DAO
    function run() public {
        vm.startBroadcast();

        // STEP 1: Deploy a 2-of-2 Gnosis Safe
        GnosisSafeProxyFactory factory = GnosisSafeProxyFactory(SAFE_FACTORY);

        //deploy communtiy vault
        CommunityVault vault = new CommunityVault();

        address[] memory owners = new address[](2);
        owners[0] = OWNER_ONE;
        owners[1] = OWNER_TWO;

        bytes memory setupData = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,      // Owners array
            1,           // Threshold (1-of-2)
            address(0),  // No `to` delegate call
            "",          // No `data`
            address(0),  // No fallback handler
            address(0),  // No payment token
            0,           // Payment = 0
            address(0),   // No payment receiver
            address(vault) //community vault
        );

        address safeAddr = address(factory.createProxy(
            SAFE_SINGLETON,
            setupData
        ));

        console.log("Gnosis Safe deployed at:", safeAddr);

        // STEP 2: Instantiate the BaalSummoner
        BaalSummoner summoner = BaalSummoner(BAAL_SUMMONER);
        console.log("BaalSummoner at:", address(summoner));

        // STEP 3: Prepare initialization params for BaalSummoner
        string memory name       = "Hamza Shares";   
        string memory symbol     = "HS";
        address _forwarder       = address(0);
        address _lootToken       = address(0);
        address _sharesToken     = address(0);

        bytes memory initParams = abi.encode(
            name,
            symbol,
            address(0), //setups safe 
            _forwarder,
            _lootToken,
            _sharesToken
        );

        // STEP 4: Create initialization actions

        // (A) Mint 1 share to the new Safe
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

        // (C) Lock the manager role so no more shares can be minted
        //     This calls: lockManager managerLock = true
        //     After that no one can be assigned manager permissions
        bytes memory lockManagerCall = abi.encodeWithSelector(
            Baal.lockManager.selector
        );

        // (D) Mint 100 loot tokens to the owner and the vault
        address[] memory recipients =  new address[](2);
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

        // Combine all three calls into initActions
        bytes[] memory initActions = new bytes[](4);
        initActions[0] = mintSharesCall;
        initActions[1] = unpauseLootCall;
        initActions[2] = lockManagerCall;
        initActions[3] = mintLootCall;

        // STEP 5: Summon a new Baal DAO
        address newBaalAddr = summoner.summonBaal(initParams, initActions, 5);
        console.log("Baal (Hamza Vault) deployed at:", newBaalAddr);

        vm.stopBroadcast();
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
