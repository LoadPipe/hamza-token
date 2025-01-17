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
    uint256 vestingPeriodSeconds = 30;
    mapping(address => Deposit[]) deposits;

    struct Deposit {
        uint256 amount;
        uint256 timestamp;
    }

    constructor(IERC20 looTokenAddress, GovernanceToken governanceTokenAddress, uint256 vestingPeriod) {
        lootToken = looTokenAddress;
        governanceToken = governanceTokenAddress; 
        vestingPeriodSeconds = vestingPeriod;
    }

    //TODO: reentrancy-guard
    function stake(uint256 amount) external {
        //soak up the loot token 
        IERC20(lootToken).safeTransferFrom(msg.sender, address(this), amount);

        //record the deposit 
        deposits[msg.sender].push(Deposit(amount, block.timestamp));

        //emit governance token 
        governanceToken.mint(msg.sender, amount);
    }

    function burn(uint256 amount) external {
        uint256 requestedAmount = amount;
        Deposit[] storage deps = deposits[msg.sender];
        uint256 count = 0;

        while(amount > 0 && deps.length > 0) {
            if (deps[0].timestamp <= (block.timestamp - vestingPeriodSeconds)) {
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
        governanceToken.burn(msg.sender, requestedAmount);
        lootToken.transfer(msg.sender, requestedAmount);
    }
}
