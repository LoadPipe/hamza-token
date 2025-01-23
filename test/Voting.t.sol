// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/security/SecurityContext.sol";
import "../src/tokens/GovernanceToken.sol";
import "../src/HamzaGovernor.sol";
import "../src/utils/TestToken.sol";
import "../src/settings/SystemSettings.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import { HamzaGovernor } from "../src/HamzaGovernor.sol";

contract VotingTest is Test {
    SecurityContext securityContext;
    GovernanceToken govToken;
    HamzaGovernor governor;
    TestToken lootToken;
    SystemSettings systemSettings;
    TimelockController timelock;

    address admin;
    address voter1;
    address voter2;
    address voter3;

    address[] targets;
    uint256[] values;
    bytes[] calldatas;

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
        admin = address(0x12);
        voter1 = address(0x13);
        voter2 = address(0x14);
        voter3 = address(0x15);

        vm.deal(admin, 1 ether);
        vm.deal(voter1, 1 ether);
        vm.deal(voter2, 1 ether);
        vm.deal(voter3, 1 ether);

        vm.startPrank(admin);
        
        // Deploy contracts
        securityContext = new SecurityContext(admin);
        lootToken = new TestToken("LOOT", "LOOT");
        govToken = new GovernanceToken(lootToken, "Hamg", "HAMG");
        address[] memory empty;
        timelock = new TimelockController(1, empty, empty, admin);
        governor = new HamzaGovernor(govToken, timelock);
        systemSettings = new SystemSettings(securityContext, admin, 0);

        console.log("admin address is", admin);
        console.log("gov address is", address(governor));

        timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
        timelock.grantRole(0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1, address(governor));
        

        lootToken.mint(voter1, 100);
        lootToken.mint(voter2, 100);
        lootToken.mint(voter3, 100);

        vm.startPrank(voter1);
        lootToken.approve(address(govToken), 100);
        govToken.depositFor(voter1, 100);
        vm.stopPrank();

        vm.startPrank(voter2);
        lootToken.approve(address(govToken), 100);
        govToken.depositFor(voter2, 100);
        vm.stopPrank();

        vm.startPrank(voter3);
        lootToken.approve(address(govToken), 100);
        govToken.depositFor(voter3, 100);
        vm.stopPrank();

        console.log("token balance", govToken.balanceOf(voter1));
    }
    
    function testProposeVote() public {
        targets.push(address(systemSettings));
        values.push(uint256(0));
        calldatas.push(abi.encodeWithSignature("setFeeBps(uint256)", 1));

        uint256 proposal = governor.propose(targets, values, calldatas, "Test proposal");

        assertGt(proposal, 0);
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Pending));
        assertEq(systemSettings.feeBps(), 0);
        
        vm.roll(block.number +2);

        //state here should be active 
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));
    }
    
    function testVote() public {
        targets.push(address(systemSettings));
        values.push(uint256(0));
        calldatas.push(abi.encodeWithSignature("setFeeBps(uint256)", 1));

        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        uint256 proposal = governor.propose(targets, values, calldatas, "Test proposal");
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        vm.startPrank(voter1);
        governor.castVote(proposal, 1);
        vm.stopPrank();

        vm.startPrank(voter2);
        governor.castVote(proposal, 1);
        vm.stopPrank();

        vm.startPrank(voter3);
        governor.castVote(proposal, 1);
        vm.stopPrank();

        vm.roll(block.number +50401);
        vm.warp(block.timestamp + 50401);

        uint256 votes = govToken.getVotes(voter3);
        console.log("voting power:", votes);
        console.log("num checkpoints:", govToken.numCheckpoints(voter1));

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));

        //governor.queue(targets, values, calldatas, keccak256("Test proposal"));
        //governor.execute(targets, values, calldatas, "Test proposal");
        //assertEq(systemSettings.feeBps(), 1);
    }
    
    function testVoteExecute() public {
        targets.push(address(systemSettings));
        values.push(uint256(0));
        calldatas.push(abi.encodeWithSignature("setFeeBps(uint256)", 1));

        assertEq(systemSettings.feeBps(), 0);
        vm.roll(block.number +1);
        
        uint256 proposal = governor.propose(targets, values, calldatas, "Test proposal");
        vm.roll(block.number +2);
        assertEq(uint256(governor.state(proposal)), uint(ProposalState.Active));

        vm.startPrank(voter1);
        governor.castVote(proposal, 1);
        vm.stopPrank();

        vm.startPrank(voter2);
        governor.castVote(proposal, 1);
        vm.stopPrank();

        vm.startPrank(voter3);
        governor.castVote(proposal, 1);
        vm.stopPrank();

        vm.roll(block.number +50401);
        vm.warp(block.timestamp + 50401);

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));

        bytes32 descriptionHash = keccak256(bytes("Test proposal"));

        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Succeeded));
        vm.roll(block.number +1);
        vm.warp(block.timestamp + 999999);

        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint256(governor.state(proposal)), uint256(ProposalState.Executed));

        assertEq(systemSettings.feeBps(), 1);
    }
}

