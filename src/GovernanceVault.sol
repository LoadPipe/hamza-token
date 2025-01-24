// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./tokens/GovernanceToken.sol";
import "./security/HasSecurityContext.sol"; 

contract GovernanceVault is HasSecurityContext {
    using SafeERC20 for IERC20;
    
    IERC20 lootToken;
    GovernanceToken governanceToken;
    address public communityVault;

    uint256 vestingPeriodSeconds = 30;
    mapping(address => Deposit[]) deposits;

    struct Deposit {
        uint256 amount;
        uint256 stakedAt;
        uint256 lastClaimAt;
    }

    constructor(address looTokenAddress, GovernanceToken governanceTokenAddress, uint256 vestingPeriod) {
        lootToken = IERC20(looTokenAddress);
        governanceToken = governanceTokenAddress; 
        vestingPeriodSeconds = vestingPeriod;
    }

    function deposit(uint256 amount) external {
        deposits[msg.sender].push(Deposit(amount, block.timestamp, block.timestamp));
        governanceToken.depositFor(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        uint256 requestedAmount = amount;
        Deposit[] storage deps = deposits[msg.sender];
        uint256 count = 0;

        while(amount > 0 && deps.length > 0) {
            if (deps[0].stakedAt <= (block.timestamp - vestingPeriodSeconds)) {
                Deposit storage deposit = deps[0];

                //this deposit is mature, and has enough or more than enough 
                if (deposit.amount >= amount) {
                    deposit.amount -= amount; 
                    amount = 0;

                //this deposit is mature, but does not have enough to cover the full amount
                } else {
                    amount -= deposit.amount;
                    deposit.amount = 0;
                }

                //delete deposits that are empty
                if (deposit.amount == 0) {
                    //TODO: not this
                    for(uint256 n=0; n<deps.length-1; n++) {
                        deps[n] = deps[n+1];
                    }
                    deps.pop();
                }
            }
            else //here, we've gotten into the too-new ones 
                break;

            count += 1;
        }

        //if amount > 0, we've not found enough available to match the amount requested
        if (amount > 0) {
            revert("InsufficientBalance");
        }

        //otherwise, burn & return 
        governanceToken.withdrawTo(msg.sender, requestedAmount);
    }

    /// @notice Sum of all new (unclaimed) rewards for this staker
    function rewards(address staker) public view returns (uint256) {
        uint256 totalReward;
        Deposit[] storage userDeposits = deposits[staker];

        for (uint256 i = 0; i < userDeposits.length; i++) {
            Deposit storage d = userDeposits[i];

            uint256 claimStart = d.lastClaimAt;
            uint256 maxClaimEnd = d.stakedAt + vestingPeriodSeconds;

            // If we’ve already claimed everything from that deposit, skip
            if (claimStart >= maxClaimEnd) {
                continue;
            }

            // The portion we can claim is from [claimStart..claimEnd]
            uint256 claimEnd = block.timestamp;
            if (claimEnd > maxClaimEnd) {
                claimEnd = maxClaimEnd;
            }

            if (claimEnd > claimStart) {
                uint256 newSeconds = claimEnd - claimStart;
                // Linear vest: reward = (depositAmount * fraction_of_vesting_period)
                uint256 newReward = (d.amount * newSeconds) / vestingPeriodSeconds;
                totalReward += newReward;
            }
        }
        return totalReward;
    }

    /// @notice Convenient batch version
    function distributeRewardsMultiple(address[] calldata stakers) external {
        for (uint256 i = 0; i < stakers.length; i++) {
            distributeRewards(stakers[i]);
        }
    }

    /**
     * @notice Move real underlying tokens from the CommunityVault 
     *         and stake them on behalf of `staker`. Then mark all
     *         relevant deposit entries as claimed.
     */
    function distributeRewards(address staker) public {
        uint256 totalReward = rewards(staker);
        if (totalReward == 0) {
            return; 
        }

        // Mark all of the user’s deposits as “claimed through now”
        Deposit[] storage userDeposits = deposits[staker];
        for (uint256 i = 0; i < userDeposits.length; i++) {
            userDeposits[i].lastClaimAt = block.timestamp;
        }
        // Now pull tokens from the CommunityVault to this vault
        lootToken.safeTransferFrom(communityVault, address(this), totalReward);

        // Next, stake them on behalf of the staker
        lootToken.safeIncreaseAllowance(address(governanceToken), totalReward);

        // Finally, deposit them for the staker. 
        governanceToken.depositFor(staker, totalReward);
    }

    /**
     * @notice Set which CommunityVault we pull reward tokens from
     */
    function setCommunityVault(address _communityVault) external /* onlyAdminOrSomething */ {
        require(_communityVault != address(0), "Invalid address");
        communityVault = _communityVault;
    }
}