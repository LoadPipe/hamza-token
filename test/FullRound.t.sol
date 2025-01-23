// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../scripts/DeployHamzaVault.s.sol";


contract FullRound is Test {
    DeployHamzaVault public script;
    uint256 public adminHatId;
    address baal;
    address communityVault;
    address govToken;
    address govVault;
    address safe;
    address hatsCtx;


    function setUp() public {

        script = new DeployHamzaVault();

        (
            baal,
            communityVault,
            govToken,
            govVault,
            safe,
            hatsCtx
        ) = script.run();

        adminHatId = script.adminHatId();

    }

    function testDeployment() public {

        // Basic sanity checks
        assertTrue(baal != address(0), "Baal address is zero");
        assertTrue(communityVault != address(0), "CommunityVault address is zero");
        assertTrue(govToken != address(0), "GovernanceToken address is zero");
        assertTrue(govVault != address(0), "GovernanceVault address is zero");
        assertTrue(safe != address(0), "Safe address is zero");
        assertTrue(hatsCtx != address(0), "HatsSecurityContext address is zero");

    }
}
