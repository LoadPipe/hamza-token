// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./tokens/GovernanceToken.sol";
import "@hamza-escrow/security/HasSecurityContext.sol";

contract GovernanceVault is HasSecurityContext {
    using SafeERC20 for IERC20;
    
    IERC20 public lootToken;
    GovernanceToken public governanceToken;
    address public communityVault;
    uint256 public vestingPeriodSeconds;
    
    struct Deposit {
        uint256 amount;
        uint256 stakedAt;
        bool rewardsDistributed;
    }

    mapping(address => Deposit[]) public deposits;

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RewardDistributed(address indexed staker, uint256 amount);

    constructor(
        ISecurityContext securityContext,
        address lootTokenAddress,
        GovernanceToken governanceTokenAddress,
        uint256 vestingPeriod
    ) {
        lootToken = IERC20(lootTokenAddress);
        governanceToken = governanceTokenAddress;
        vestingPeriodSeconds = vestingPeriod;

        _setSecurityContext(securityContext);
    }

    // deposit loot tokens into the vault
    function deposit(uint256 amount) external {
        _processDeposit(msg.sender, amount);
        lootToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    // deposit loot tokens on behalf of another account
    function depositFor(address account, uint256 amount) external {
        _processDeposit(account, amount);
        lootToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    // withdraw loot tokens from the vault
    function withdraw(uint256 amount) external {
        uint256 remaining = amount;
        Deposit[] storage userDeposits = deposits[msg.sender];

        while (remaining > 0 && userDeposits.length > 0) {
            Deposit storage oldest = userDeposits[0];
            require(block.timestamp >= oldest.stakedAt + vestingPeriodSeconds, "Deposit not vested");
            
            // Auto-distribute rewards before withdrawal
            if (!oldest.rewardsDistributed) {
                _distributeRewardsForDeposit(msg.sender, 0);
            }

            if (oldest.amount > remaining) {
                oldest.amount -= remaining;
                remaining = 0;
            } else {
                remaining -= oldest.amount;
                _removeFirstDeposit(userDeposits);
            }
        }

        governanceToken.burn(msg.sender, amount);
        lootToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    // distribute rewards to a staker
    function distributeRewards(address staker) public {
        uint256 totalReward;
        Deposit[] storage userDeposits = deposits[staker];

        for (uint256 i = 0; i < userDeposits.length; i++) {
            Deposit storage d = userDeposits[i];
            if (_isVested(d) && !d.rewardsDistributed) {
                totalReward += d.amount; // 100% reward
                d.rewardsDistributed = true;
            }
        }

        require(totalReward > 0, "No rewards available");
        _processRewardDistribution(staker, totalReward);
    }

    // admin function to set the community vault address
    function setCommunityVault(address _communityVault) external {
        require(_communityVault != address(0), "Invalid address");
        communityVault = _communityVault;
    }

    // helper function to process new deposits
    function _processDeposit(address account, uint256 amount) private {
        deposits[account].push(Deposit({
            amount: amount,
            stakedAt: block.timestamp,
            rewardsDistributed: false
        }));
        governanceToken.mint(account, amount);
        emit Deposited(account, amount);
    }

    // helper function to remove the first deposit from an array
    function _removeFirstDeposit(Deposit[] storage deps) private {
        if (deps.length > 0) {
            deps[0] = deps[deps.length - 1];
            deps.pop();
        }
    }

    // helper function to check if a deposit is vested
    function _isVested(Deposit memory d) private view returns (bool) {
        return block.timestamp >= d.stakedAt + vestingPeriodSeconds;
    }

    // helper function to distribute rewards for a specific deposit
    function _distributeRewardsForDeposit(address staker, uint256 depositIndex) private {
        Deposit storage d = deposits[staker][depositIndex];
        if (!_isVested(d) || d.rewardsDistributed) return;

        uint256 reward = d.amount;
        d.rewardsDistributed = true;
        _processRewardDistribution(staker, reward);
    }

    // helper function to process reward distribution
    function _processRewardDistribution(address staker, uint256 amount) private {
        lootToken.safeTransferFrom(communityVault, address(this), amount);
        
        deposits[staker].push(Deposit({
            amount: amount,
            stakedAt: block.timestamp,
            rewardsDistributed: false
        }));
        
        governanceToken.mint(staker, amount);
        emit RewardDistributed(staker, amount);
    }
}