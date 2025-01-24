// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.17;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "../src/security/SecurityContext.sol";
// import "../src/tokens/GovernanceToken.sol";
// import "../src/HamzaGovernor.sol";
// import "../src/utils/TestToken.sol";
// import "../src/settings/SystemSettings.sol";
// import "@openzeppelin/contracts/governance/TimelockController.sol";
// import { HamzaGovernor } from "../src/HamzaGovernor.sol";

// contract VotingTest is Test {
//     SecurityContext securityContext;
//     GovernanceToken govToken;
//     HamzaGovernor governor;
//     TestToken lootToken;
//     SystemSettings systemSettings;
//     TimelockController timelock;

//     address admin;
//     address voter1;
//     address voter2;
//     address voter3;

//     address[] targets;
//     uint256[] values;
//     bytes[] calldatas;

//     enum ProposalState {
//         Pending,
//         Active,
//         Canceled,
//         Defeated,
//         Succeeded,
//         Queued,
//         Expired,
//         Executed
//     }

//     function setUp() public {
//         admin = address(0x12);
//         voter1 = address(0x13);
//         voter2 = address(0x14);
//         voter3 = address(0x15);

//         vm.deal(admin, 1 ether);
//         vm.deal(voter1, 1 ether);
//         vm.deal(voter2, 1 ether);
//         vm.deal(voter3, 1 ether);

//         //create tokens & mint
//         lootToken = new TestToken("LOOT", "LOOT");
//         govToken = new GovernanceToken(lootToken, "Hamg", "HAMG");

//         lootToken.mint(voter1, 100);
//         lootToken.mint(voter2, 100);
//         lootToken.mint(voter3, 100);

//         //wrap tokens for voters
//         address[3] memory voters = [voter1, voter2, voter3];
//         for(uint8 n=0; n<voters.length; n++) {
//             vm.startPrank(voters[n]);
//             lootToken.approve(address(govToken), 100);
//             govToken.depositFor(voters[n], 100);
//             vm.stopPrank();
//         }

//         vm.startPrank(admin);
        
//         // deploy main contracts
//         securityContext = new SecurityContext(admin);
//         address[] memory empty;
//         timelock = new TimelockController(1, empty, empty, admin);
//         governor = new HamzaGovernor(govToken, timelock);
//         systemSettings = new SystemSettings(securityContext, admin, 0);

//         //grant permissions
//         timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));

//         //prepare proposal data
//         targets.push(address(systemSettings));
//         values.push(uint256(0));
//         calldatas.push(abi.encodeWithSignature("setFeeBps(uint256)", 1));
//     }
    
//     function testProposeVote() public {
//         //make a proposal
//         uint256 proposal = governor.propose(targets, values, calldatas, "Test proposal");

//         //test proposal
//         assertGt(proposal, 0);
//         assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Pending));
        
//         //roll fwd
//         vm.roll(block.number +2);

//         //state here should be active 
//         assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));
//     }
    
//     function testVote() public {
//         uint256 proposal = governor.propose(targets, values, calldatas, "Test proposal");
//         vm.roll(block.number +2);
//         assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

//         //let everyone vote for
//         address[3] memory voters = [voter1, voter2, voter3];
//         for(uint8 n=0; n<voters.length; n++) {
//             vm.startPrank(voters[n]);
//             governor.castVote(proposal, 1);
//             vm.stopPrank();
//         }

//         //roll forward
//         vm.roll(block.number +50401);
//         vm.warp(block.timestamp + 50401);

//         uint256 votes = govToken.getVotes(voter3);
//         assertEq(govToken.getVotes(voter1), 100);
//         assertEq(govToken.getVotes(voter2), 100);
//         assertEq(govToken.getVotes(voter3), 100);
//         assertEq(govToken.numCheckpoints(voter1), 1);
//         assertEq(govToken.numCheckpoints(voter2), 1);
//         assertEq(govToken.numCheckpoints(voter3), 1);
//         assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
//     }
    
//     function testVoteExecute() public {
//         assertEq(systemSettings.feeBps(), 0);
//         vm.roll(block.number +1);
        
//         //create proposal
//         uint256 proposal = governor.propose(targets, values, calldatas, "Test proposal");
//         vm.roll(block.number +2);
//         assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

//         //let everyone vote for
//         address[3] memory voters = [voter1, voter2, voter3];
//         for(uint8 n=0; n<voters.length; n++) {
//             vm.startPrank(voters[n]);
//             governor.castVote(proposal, 1);
//             vm.stopPrank();
//         }

//         //roll forward
//         vm.roll(block.number +50401);
//         vm.warp(block.timestamp + 50401);

//         assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));

//         bytes32 descriptionHash = keccak256(bytes("Test proposal"));
//         assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
//         vm.warp(block.timestamp + 999999);

//         governor.execute(targets, values, calldatas, descriptionHash);
//         assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Executed));

//         assertEq(systemSettings.feeBps(), 1);
//     }
// }

