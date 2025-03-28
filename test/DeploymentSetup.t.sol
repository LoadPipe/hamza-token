// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../scripts/DeployHamzaVault.s.sol";
import "../src/GovernanceVault.sol";

contract DeploymentSetup is Test {
    using stdJson for string;

    // Shared Variables
    DeployHamzaVault public script;
    address public baal;
    address payable public communityVault;
    address public govToken;
    address public govVault;
    address public safe;
    address public hatsCtx;
    address payable public governor;
    address public systemSettings;
    address public purchaseTracker;
    address public escrow;
    address public deployedTestToken;
    uint256 public adminHatId;
    address public admin;
    address public lootToken;
    address public user;
    uint256 public userLootAmountFromConfig;
    uint256 public vaultLootAmountFromConfig;
    uint256 public vestingPeriodFromConfig;
    uint256 public initialFeeBps;
    uint256 public timeLockDelay;
    bool public autoRelease;

    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    // Shared Setup
    function setUp() public virtual {
        // Load config
        string memory config = vm.readFile("./config.json");
        userLootAmountFromConfig = config.readUint(".baal.userLootAmount")*10**18;
        vaultLootAmountFromConfig = config.readUint(".baal.vaultLootAmount")*10**18;
        vestingPeriodFromConfig = config.readUint(".governanceVault.vestingPeriod");
        initialFeeBps = config.readUint(".systemSettings.feeBPS");
        timeLockDelay = config.readUint(".governor.timelockDelay");
        autoRelease = config.readBool(".escrow.autoRelease");

        // Deploy contracts
        script = new DeployHamzaVault();
        (baal, communityVault, govToken, govVault, safe, hatsCtx, deployedTestToken) = script.run();

        // Initialize addresses
        adminHatId = script.adminHatId();
        admin = script.OWNER_ONE();
        user = script.OWNER_ONE();
        lootToken = script.hamzaToken();
        governor = script.governorAddr();
        systemSettings = script.systemSettingsAddr();
        purchaseTracker = script.purchaseTrackerAddr();
        escrow = script.escrowAddr();
    }

    // Shared Helper Functions
    function getDepositCount(GovernanceVault gVault, address account) internal view returns (uint256) {
        uint256 count;
        try gVault.deposits(account, 0) {
            count++;
        } catch {
            return 0;
        }
        while (true) {
            try gVault.deposits(account, count) {
                count++;
            } catch {
                break;
            }
        }
        return count;
    }
}