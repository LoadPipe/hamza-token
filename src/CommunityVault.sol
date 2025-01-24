// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./security/HasSecurityContext.sol"; 
import "./security/Roles.sol";
import "./security/IHatsSecurityContext.sol";
import "./GovernanceVault.sol";      

/**
 * @title CommunityVault
 * @dev A vault for holding and distributing community funds, with Hats-based role control.
 */
contract CommunityVault is HasSecurityContext {
    using SafeERC20 for IERC20;

    // Mapping to store token balances held in the community vault
    mapping(address => uint256) public tokenBalances;

    // Governance staking contract address
    address public governanceVault;

    // Events
    event Deposit(address indexed token, address indexed from, uint256 amount);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event Distribute(address indexed token, address indexed to, uint256 amount);
    event RewardDistributed(address indexed token, address indexed recipient, uint256 amount);

    /**
     * @dev Constructor to initialize the security context.
     * @param _securityContext Address of the HatsSecurityContext contract.
     */
    constructor(address _securityContext) {
        if (address(_securityContext) == address(0)) revert ZeroAddressArgument();
        _setSecurityContext(IHatsSecurityContext(_securityContext));
    }

    /**
     * @dev Deposit tokens into the community vault
     * @param token The address of the token 
     * @param amount The amount of tokens to deposit
     */
    function deposit(address token, uint256 amount) external payable {
        if (token == address(0)) {
            // ETH deposit
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            // ERC20 deposit
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        tokenBalances[token] += amount;

        emit Deposit(token, msg.sender, amount);
    }

    /**
     * @dev Withdraw tokens or ETH from the community vault
     * @param token The address of the token (use address(0) for ETH)
     * @param to The address to send the tokens or ETH to
     * @param amount The amount to withdraw
     */
    function withdraw(address token, address to, uint256 amount) external onlyRole(Roles.ADMIN_ROLE) {
        require(tokenBalances[token] >= amount, "Insufficient balance");

        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).safeTransfer(to, amount);
        }

        tokenBalances[token] -= amount;

        emit Withdraw(token, to, amount);
    }

    /**
     * @dev Distribute tokens or ETH from the community vault to multiple recipients
     * @param token The address of the token 
     * @param recipients The array of recipient addresses
     * @param amounts The array of amounts to distribute
     */
    function distribute(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(Roles.ADMIN_ROLE) {
        require(recipients.length == amounts.length, "Mismatched arrays");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(tokenBalances[token] >= amounts[i], "Insufficient balance");

            if (token == address(0)) {
                // ETH distribution
                (bool success, ) = recipients[i].call{value: amounts[i]}("");
                require(success, "ETH transfer failed");
            } else {
                // ERC20 distribution
                IERC20(token).safeTransfer(recipients[i], amounts[i]);
            }

            tokenBalances[token] -= amounts[i];

            emit Distribute(token, recipients[i], amounts[i]);
        }
    }

    /**
     * @dev Distribute governance rewards to multiple recipients
     * @param recipients The array of recipient addresses
     */
    function distributeGovernanceRewards(
        address[] calldata recipients
    ) external onlyRole(Roles.ADMIN_ROLE) {

        //call the distrubtRewardsMultiple function in the governance vault
        GovernanceVault(governanceVault).distributeRewardsMultiple(recipients);
        
    }

    /**
    * @dev Set the governance vault address and grant it unlimited allowance for `lootToken`.
    *      Must be called by an admin role or similar.
    * @param vault The address of the governance vault
    * @param lootToken The address of the ERC20 token for which you'd like to grant unlimited allowance
    */
    function setGovernanceVault(address vault, address lootToken)
        external
        onlyRole(Roles.ADMIN_ROLE)
    {
        require(vault != address(0), "Invalid staking contract address");
        require(lootToken != address(0), "Invalid loot token address");

        governanceVault = vault;

        // Best practice when changing allowances:

        IERC20(lootToken).safeApprove(vault, 0);
        IERC20(lootToken).safeApprove(vault, type(uint256).max);
    }

    /**
     * @dev Get the balance of a token in the community vault
     * @param token The address of the token
     */
    function getBalance(address token) external view returns (uint256) {
        return tokenBalances[token];
    }

    // Fallback to receive ETH
    receive() external payable {}
}
