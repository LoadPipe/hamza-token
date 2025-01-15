// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import "@baal/Baal.sol";
import "@baal/BaalSummoner.sol";

contract DeployHamzaVault is Script {
    // (A) Deployed BaalSummoner on Sepolia
    address constant BAAL_SUMMONER = 0xB2B3909661552942AE1115E9Fc99dF0BC93d71d0;

    // (B) Admin multisig address
    address constant ADMIN_MULTISIG = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4; // random address

    //-------------------------------------------------------------------------
    // Deploy & configure the DAO
    //-------------------------------------------------------------------------
    function run() public {
        vm.startBroadcast();

        // STEP 1: Instantiate the deployed BaalSummoner
        BaalSummoner summoner = BaalSummoner(BAAL_SUMMONER);

        // STEP 2: Prepare “initializationParams” to pass to BaalSummoner
        string memory name = "Hamza Shares";   
        string memory symbol = "HS";
        address _forwarder = address(0);     // No meta-tx forwarder
        address _lootToken = address(0);     // Auto-deploy loot token
        address _sharesToken = address(0);   // Auto-deploy shares token

        bytes memory initParams = abi.encode(
            name,
            symbol,
            ADMIN_MULTISIG,  // DAO's vault or Hats Admin Multisig
            _forwarder,
            _lootToken,
            _sharesToken
        );

        // STEP 3: Create initialization actions
        // (A) Mint 1 share to the admin multisig
        bytes memory mintSharesCall = abi.encodeWithSelector(
            Baal.mintShares.selector,
            _singleAddressArray(ADMIN_MULTISIG),    // [ADMIN_MULTISIG]
            _singleUint256Array(1)                  // [1] => 1 share
        );

        // (B) Unpause loot token transfers, keep shares paused
        bytes memory unpauseLootCall = abi.encodeWithSelector(
            Baal.setAdminConfig.selector,
            true,   // pauseShares (true => paused)
            false   // pauseLoot (false => unpaused)
        );

        // Create a dynamic array of actions
        bytes[] memory initActions = new bytes[](2);
        initActions[0] = mintSharesCall;
        initActions[1] = unpauseLootCall;

        // STEP 4: Summon a new Baal
        address newBaalAddr = summoner.summonBaal(
            initParams,
            initActions,
            0 // _saltNonce
        );

        console.log("Deployed Baal (Hamza Vault) at:", newBaalAddr);

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
