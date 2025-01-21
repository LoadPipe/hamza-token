// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// import "forge-std/Script.sol";

// We import the previously defined contract
import "./HatsDeployment.s.sol";

import "@baal/Baal.sol";
import "@baal/BaalSummoner.sol";

import "../src/CommunityVault.sol";

/**
 * @title DeployHamzaVault
 * @notice Runs the HatsDeployment script first, then uses the
 *         returned Safe address to deploy and configure the Baal DAO.
 */
contract DeployHamzaVault is Script {
    // (A) Deployed BaalSummoner on Sepolia
    address constant BAAL_SUMMONER = 0x33267E2d3decebCae26FA8D837Ef3F7608367ab2; 

    // addresses for loot recipients, etc.
    address constant OWNER_ONE = 0x1310cEdD03Cc8F6aE50F2Fb93848070FACB042b8;
    address constant OWNER_TWO = 0x1542612fee591eD35C05A3E980bAB325265c06a3;

    uint256 internal deployerPk;

    function run() external {

        // 1) Deploy all hats + new Gnosis Safe
        HatsDeployment hatsDeployment = new HatsDeployment();
        address safeAddr = hatsDeployment.run(); 

        console.log("Using Safe from HatsDeployment at:", safeAddr);

        deployerPk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPk);


        // 2) Deploy the Community Vault
        CommunityVault vault = new CommunityVault();
        console.log("CommunityVault deployed at:", address(vault));

        // 3) Summon the Baal DAO
        BaalSummoner summoner = BaalSummoner(BAAL_SUMMONER);
        console.log("BaalSummoner at:", address(summoner));

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
        address newBaalAddr = summoner.summonBaal(initParams, initActions, 7);
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
