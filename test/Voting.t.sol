// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./DeploymentSetup.t.sol";
import "@hamza-escrow/security/HatsSecurityContext.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/HamzaGovernor.sol";
import { TestToken as VotingTestToken } from "../src/utils/TestToken.sol";
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
    address noVotingRightsAddr;


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
        
        // Add an address that won't have voting rights
        noVotingRightsAddr = address(0x22);
        
        // Use the existing securityContext, lootToken, and govToken from DeploymentSetup
        HatsSecurityContext securityContextLocal = HatsSecurityContext(hatsCtx);
        VotingTestToken lootTokenLocal = VotingTestToken(lootToken);
        GovernanceToken govTokenLocal = GovernanceToken(govToken);

        // Mint loot tokens to voters
        for(uint256 n=0; n<voters.length; n++) {
            vm.startPrank(baal);
            lootTokenLocal.mint(voters[n], 100);
            vm.stopPrank();
        }

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
    
    // Test abstain votes (support = 2) behavior
    function testAbstainVotes() public {
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        
        // Let half vote for
        for(uint8 n=0; n<voters.length/2; n++) {
            vote(voters[n], proposal, 1);
        }
        
        // Let half abstain (support = 2)
        for(uint8 n=uint8(voters.length/2); n<voters.length; n++) {
            vote(voters[n], proposal, 2);
        }
        
        vm.roll(block.number + 50401);
        
        // Proposal should succeed because abstain votes count toward quorum but not against
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
    }
    
    // Test quorum requirement - make sure we need 4% of total votes to pass
    function testQuorumRequirement() public {
        // Create proposal
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        
        // Get total votes
        uint256 totalVotes = 0;
        for(uint8 n=0; n<voters.length; n++) {
            totalVotes += GovernanceToken(govToken).getVotes(voters[n]);
        }
        
        // Calculate 4% of total votes (quorum)
        uint256 quorumVotes = (totalVotes * 4) / 100;
        
        // Only have voters representing less than quorum vote
        uint256 votedPower = 0;
        uint8 voterIndex = 0;
        
        // Ensure we don't subtract more than quorumVotes to avoid underflow
        uint256 targetVotes = quorumVotes > 100 ? quorumVotes - 100 : 0;
        
        while(votedPower < targetVotes && voterIndex < voters.length) {
            vote(voters[voterIndex], proposal, 1);
            votedPower += GovernanceToken(govToken).getVotes(voters[voterIndex]);
            voterIndex++;
        }
        
        // Roll forward to end voting period
        vm.roll(block.number + 50401);
        
        // Should be defeated due to not meeting quorum
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Defeated));
    }
    
    // Test proposal cancellation
    function testProposalCancellation() public {
        // Create proposal from the first voter
        vm.startPrank(voters[0]);
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.stopPrank();
        
        vm.roll(block.number + 2);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint(ProposalState.Active));
        
        // Cancel the proposal
        vm.startPrank(voters[0]);
        HamzaGovernor(governor).cancel(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        vm.stopPrank();
        
        // Verify it's canceled
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Canceled));
        
        // Ensure we can't vote on canceled proposals
        vm.startPrank(voters[1]);
        vm.expectRevert();
        HamzaGovernor(governor).castVote(proposal, 1);
        vm.stopPrank();
    }
    
    // Test that a voter can't vote twice
    function testDoubleVotePrevention() public {
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        
        // First vote for
        vote(voters[0], proposal, 1);
        
        // Try to vote again - should revert
        vm.startPrank(voters[0]);
        vm.expectRevert();
        HamzaGovernor(governor).castVote(proposal, 0);
        vm.stopPrank();
    }
    
    // Test that an account without voting power can't vote
    function testVoteWithoutPower() public {
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        
        // Try to vote from account with no voting power
        vm.startPrank(noVotingRightsAddr);

        HamzaGovernor(governor).castVote(proposal, 1);
        vm.stopPrank();
        
        // Skip ahead
        vm.roll(block.number + 50401);
        
        // If all others haven't voted, proposal should be defeated (zero votes)
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Defeated));
    }
    
    // Test vote delegation functionality
    function testVoteDelegation() public {
        VotingTestToken lootTokenLocal = VotingTestToken(lootToken);
        GovernanceToken govTokenLocal = GovernanceToken(govToken);
        
        // Delegate voter[1]'s votes to voter[0]
        vm.startPrank(voters[1]);
        govTokenLocal.delegate(voters[0]);
        vm.stopPrank();
        
        // Check that voter[0] now has their votes plus voter[1]'s votes
        assertEq(govTokenLocal.getVotes(voters[0]), 200); // 100 + 100
        assertEq(govTokenLocal.getVotes(voters[1]), 0);   // Delegated away
        
        // Create a proposal and vote with the delegated votes
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        
        // Only voter[0] votes (with delegated power)
        vote(voters[0], proposal, 1);
        
        // Skip ahead
        vm.roll(block.number + 50401);
        
        // If voter[0] has 200 votes and voted for the proposal, it should pass
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
        
        // Also verify the total voting power of voter[0]
        assertEq(govTokenLocal.getVotes(voters[0]), 200);
    }
    
    // Test that proposals can't be executed before the timelock has passed
    function testTimelockEnforcement() public {
        uint256 proposal = HamzaGovernor(governor).propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number + 2);
        
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }
        
        vm.roll(block.number + 50401);
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Succeeded));
        
        // Queue the proposal
        HamzaGovernor(governor).queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        
        // Try to execute immediately (before timelock delay)
        vm.expectRevert();
        HamzaGovernor(governor).execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        
        // Wait for timelock to pass
        vm.warp(block.timestamp + timeLockDelay + 1);
        
        // Now execution should work
        HamzaGovernor(governor).execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(HamzaGovernor(governor).state(proposal)), uint256(ProposalState.Executed));
    }
}
