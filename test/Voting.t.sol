// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./DeploymentSetup.t.sol";
import "@hamza-escrow/security/HatsSecurityContext.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/HamzaGovernor.sol";
import "../src/utils/TestToken.sol";
import "@hamza-escrow/SystemSettings.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import { HamzaGovernor } from "../src/HamzaGovernor.sol";
import { Hats } from "@hats-protocol/Hats.sol";

contract VotingTest is DeploymentSetup {
    string proposalDescription = "Test Proposal";

    address[] voters;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;



    function setUp() public override {
        // Call DeploymentSetup's setUp function first
        super.setUp();

        // Initialize voters
        voters.push(address(0x13));
        voters.push(address(0x14));
        voters.push(address(0x15));
        voters.push(address(0x16));
        voters.push(address(0x17));
        voters.push(address(0x18));
        voters.push(address(0x19));
        voters.push(address(0x20));
        voters.push(address(0x21));

        // We'll use existing lootToken from DeploymentSetup (script.hamzaToken())
        // We'll use existing govToken from DeploymentSetup
        
        // Use the existing securityContext, lootToken, and govToken from DeploymentSetup
        HatsSecurityContext securityContextLocal = HatsSecurityContext(hatsCtx);
        TestToken lootTokenLocal = TestToken(lootToken);
        GovernanceToken govTokenLocal = GovernanceToken(govToken);

        // Mint loot tokens to voters
        for(uint256 n=0; n<voters.length; n++) {
            vm.startPrank(baal);
            lootTokenLocal.mint(voters[n], 100);
            vm.stopPrank();
        }

        // We'll use the existing governor and timelock from DeploymentSetup

        // Mint hats to voters
        vm.startPrank(safe);
        Hats hats = Hats(securityContextLocal.hats());
        uint256 minterHatId = script.minterHatId();

        for(uint8 n=0; n<voters.length; n++) {
            hats.mintHat(minterHatId, voters[n]);
        }
        vm.stopPrank();

        // Prepare proposal data
        targets.push(systemSettings);
        values.push(uint256(0));
        calldatas.push(abi.encodeWithSignature("setFeeBps(uint256)", 1));

        // Have all voters deposit their tokens to get governance rights
        for(uint8 n=0; n<voters.length; n++) {
            vm.startPrank(voters[n]);
            lootTokenLocal.approve(govToken, 100);
            govTokenLocal.depositFor(voters[n], 100);
            vm.stopPrank();
        }
    }

    function vote(address addr, uint256 proposal, uint8 support) internal {
        vm.startPrank(addr);
        HamzaGovernor(governor).castVote(proposal, support);
        vm.stopPrank();
    }
    
    function testProposeVote() public {
        // Make a proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);

        // Test proposal
        assertGt(proposal, 0);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Pending));
        
        // Roll forward
        vm.roll(block.number + 2);

        // State here should be active 
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));
    }
    
    function testVote() public {
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));

        // Let everyone vote for
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }

        // Roll forward
        vm.roll(block.number + 50401);
        vm.warp(block.timestamp + 50401);

        // Assert number of votes & checkpoints
        for(uint8 n=0; n<voters.length; n++) {
            assertEq(GovernanceToken(govToken).getVotes(voters[n]), 100);
        }
        for(uint8 n=0; n<voters.length; n++) {
            assertEq(GovernanceToken(govToken).numCheckpoints(voters[n]), 1);
        }

        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
    }
    
    function testUnanimousVoteDefeat() public {
        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
        vm.roll(block.number + 1);
        
        // Create proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));

        // Let everyone vote against
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 0);
        }

        // Roll forward
        vm.roll(block.number + 50401);

        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Defeated));
        vm.warp(block.timestamp + 999999);

        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
    }
    
    function testNonUnanimousVoteDefeat() public {
        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
        vm.roll(block.number + 1);
        
        // Create proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));

        // Let this guy vote for
        vote(voters[0], proposal, 1);

        // Let everyone else vote against
        for(uint8 n=1; n<voters.length; n++) {
            vote(voters[n], proposal, 0);
        }

        // Roll forward
        vm.roll(block.number + 50401);

        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Defeated));
        vm.warp(block.timestamp + 999999);

        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
    }
    
    function testNonUnanimousVoteExecute() public {
        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
        vm.roll(block.number + 1);
        
        // Create proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));

        // Let everyone vote for or against in alternating pattern
        for(uint8 n=0; n<voters.length; n++) {
            if (n % 2 == 0)
                vote(voters[n], proposal, 1);
            else 
                vote(voters[n], proposal, 0);
        }

        // Roll forward
        vm.roll(block.number + 50401);

        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
        vm.warp(block.timestamp + 999999);

        // Queue 
        HamzaGovernor(governor).queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));

        vm.warp(block.timestamp + 2);

        HamzaGovernor(governor).execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Executed));

        assertEq(SystemSettings(systemSettings).feeBps(), 1);
    }
    
    function testProposalVote() public {
        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
        vm.roll(block.number + 1);
        
        // Create proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));
        
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }
        // Roll forward
        vm.roll(block.number + 50401);

        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
        vm.warp(block.timestamp + 999999);

        // Queue
        HamzaGovernor(governor).queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));

        vm.warp(block.timestamp + 2);

        HamzaGovernor(governor).execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Executed));

        assertEq(SystemSettings(systemSettings).feeBps(), 1);
    }
    
    function testVoteQueue() public {
        assertEq(SystemSettings(systemSettings).feeBps(), initialFeeBps);
        vm.roll(block.number + 1);
        
        // Create proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));

        // Let everyone vote for
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }

        // Roll forward
        vm.roll(block.number + 50401);

        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
        vm.warp(block.timestamp + 999999);

        // Queue the proposal 
        HamzaGovernor(governor).queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Queued));

        // And then wait 
        vm.roll(block.number + 50401);
        vm.warp(block.timestamp + 50401);

        // And then execute
        HamzaGovernor(governor).execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Executed));

        // The fee has been changed at this point
        assertEq(SystemSettings(systemSettings).feeBps(), 1);
    }
}
