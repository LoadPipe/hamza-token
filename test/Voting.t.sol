// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@hamza-escrow/HatsSecurityContext.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/HamzaGovernor.sol";
import "../src/utils/TestToken.sol";
import "@hamza-escrow/SystemSettings.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import { HamzaGovernor } from "../src/HamzaGovernor.sol";
import { Hats } from "@hats-protocol/Hats.sol";

contract VotingTest is Test {
    HatsSecurityContext securityContext;
    GovernanceToken govToken;
    HamzaGovernor governor;
    TestToken lootToken;
    SystemSettings systemSettings;
    TimelockController timelock;
    string proposalDescription = "Test Proposal";

    address admin;
    address[] voters;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;

    uint256 public adminHatId;

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

    function setUp() public {
        address[] memory empty;

        admin = address(0x12);
        voters.push(address(0x13));
        voters.push(address(0x14));
        voters.push(address(0x15));
        voters.push(address(0x16));
        voters.push(address(0x17));
        voters.push(address(0x18));
        voters.push(address(0x19));
        voters.push(address(0x20));
        voters.push(address(0x21));

        //create tokens & mint
        lootToken = new TestToken("LOOT", "LOOT");
        govToken = new GovernanceToken(lootToken, "Hamg", "HAMG");

        //mint tokens 
        for(uint256 n=0; n<voters.length; n++) {
            lootToken.mint(voters[n], 100);
        }

        //wrap tokens for voters
        for(uint8 n=0; n<voters.length; n++) {
            vm.startPrank(voters[n]);
            lootToken.approve(address(govToken), 100);
            govToken.depositFor(voters[n], 100);
            vm.stopPrank();
        }

        vm.startPrank(admin);
        
        // deploy main contracts
        securityContext = createHatsSecurityContext();
        timelock = new TimelockController(1, empty, empty, admin);
        governor = new HamzaGovernor(govToken, timelock);
        systemSettings = new SystemSettings(securityContext, admin, 0);

        //grant permissions for governor
        timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
        timelock.grantRole(0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, address(governor));

        // 1) Grab the Hats protocol reference & adminHatId from our security context
        Hats hats = Hats(securityContext.hats()); 

        // 2) Create a new child-hat under that adminHatId (if it doesn't already exist)
        //    In real deployments, you'd call createHat via Gnosis Safe that holds the top-hat,
        //    but here we assume your `admin` can create it for testing.
        uint256 daoHatId = hats.getNextId(adminHatId);
        hats.createHat(
            adminHatId,
            "DAO Hat",   // optional name
            2,          // maxSupply
            address(1), // eligibility module (none in this simple test)
            address(1), // toggle module (none in this simple test)
            true,       // mutable
            ""          // details
        );

        // 3) Tell the security context that "DAO_ROLE" = our newly created daoHatId
        securityContext.setRoleHat(Roles.DAO_ROLE, daoHatId);

        // 4) Mint the DAO hat to the Timelock
        hats.mintHat(daoHatId, address(timelock));

        //prepare proposal data
        targets.push(address(systemSettings));
        values.push(uint256(0));
        calldatas.push(abi.encodeWithSignature("setFeeBps(uint256)", 1));
    }

    function createHatsSecurityContext() internal returns (HatsSecurityContext) {
        address hatsAddress = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
        Hats hats = Hats(hatsAddress);
        adminHatId = uint256(hats.lastTopHatId()) << 224;
        // mint top-hat to admin
        hats.mintTopHat(admin, "ipfs://bafkreih3vqseitn7pijlkl2jcawbjrhae3dfb2pakqtgd4epvxxfulwoqq","");
        adminHatId = uint256(hats.lastTopHatId()) << 224;

        securityContext = new HatsSecurityContext(hatsAddress, adminHatId);


        return securityContext;
    }

    function vote(address addr, uint256 proposal, uint8 support) internal {
        vm.startPrank(addr);
        governor.castVote(proposal, support);
        vm.stopPrank();
    }
    
    function testProposeVote() public {
        //make a proposal
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);

        //test proposal
        assertGt(proposal, 0);
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Pending));
        
        //roll fwd
        vm.roll(block.number +2);

        //state here should be active 
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));
    }
    
    function testVote() public {
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        //let everyone vote for
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }

        //roll forward
        vm.roll(block.number +50401);
        vm.warp(block.timestamp + 50401);

        //assert number of votes & checkpoints
        for(uint8 n=0; n<voters.length; n++) {
            assertEq(govToken.getVotes(voters[n]), 100);
        }
        for(uint8 n=0; n<voters.length; n++) {
            assertEq(govToken.numCheckpoints(voters[n]), 1);
        }

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
    }
    
    function testUnanimousVoteDefeat() public {
        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        //create proposal
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        //let everyone vote agin
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 0);
        }

        //roll forward
        vm.roll(block.number +50401);

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Defeated));
        vm.warp(block.timestamp + 999999);

        assertEq(systemSettings.feeBps(), 0);
    }
    
    function testNonUnanimousVoteDefeat() public {
        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        //create proposal
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        //let this guy vote for
        vote(voters[0], proposal, 1);

        //let everyone else vote agin
        for(uint8 n=1; n<voters.length; n++) {
            vote(voters[n], proposal, 0);
        }

        //roll forward
        vm.roll(block.number +50401);

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Defeated));
        vm.warp(block.timestamp + 999999);

        assertEq(systemSettings.feeBps(), 0);
    }
    
    function testNonUnanimousVoteExecute() public {
        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        //create proposal
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        //let everyone vote for
        for(uint8 n=0; n<voters.length; n++) {
            if (n % 2 == 0)
                vote(voters[n], proposal, 1);
            else 
                vote(voters[n], proposal, 0);
        }

        //roll forward
        vm.roll(block.number +50401);

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
        vm.warp(block.timestamp + 999999);

        // queue 
        governor.queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));

        vm.warp(block.timestamp + 2);

        governor.execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Executed));

        assertEq(systemSettings.feeBps(), 1);
    }
    
    function testProposalVote() public {
        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        //create proposal
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        //vote(voters[0], proposal, 1);
        
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }
        //roll forward
        vm.roll(block.number +50401);


        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
        vm.warp(block.timestamp + 999999);

        // queue
        governor.queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));

        vm.warp(block.timestamp + 2);

        governor.execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Executed));

        assertEq(systemSettings.feeBps(), 1);
    }
    
    function testVoteQueue() public {
        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        //create proposal
        uint256 proposal = governor.propose(targets, values, calldatas, proposalDescription);
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        //let everyone vote for
        for(uint8 n=0; n<voters.length; n++) {
            vote(voters[n], proposal, 1);
        }

        //roll forward
        vm.roll(block.number +50401);

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
        vm.warp(block.timestamp + 999999);

        //queue the proposal 
        governor.queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Queued));

        //and then wait 
        vm.roll(block.number +50401);
        vm.warp(block.timestamp + 50401);

        // and then execute
        governor.execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Executed));

        //the fee has not changed at this point
        assertEq(systemSettings.feeBps(), 1);
    }
}
