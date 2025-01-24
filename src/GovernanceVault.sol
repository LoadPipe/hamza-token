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

    function deposit(uint256 amount) external {
        deposits[_msgSender()].push(Deposit(amount, block.timestamp));
        governanceToken.depositFor(_msgSender(), amount);
    }

    function withdraw(uint256 amount) external {
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
        governanceToken.withdrawTo(msg.sender, requestedAmount);
    }
}