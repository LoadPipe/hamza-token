// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@hamza-escrow/security/HasSecurityContext.sol";
import "@hamza-escrow/security/Roles.sol";
import "@hamza-escrow/security/ISecurityContext.sol";
import "./ICommunityRewardsCalculator.sol";

/**
 * @title CommunityVault
 * @dev A vault for holding and distributing community funds, with Hats-based role control.
 */
contract CommunityVault is HasSecurityContext {
    using SafeERC20 for IERC20;

    // Store the last claim checkpoint for each user/token combination
    // Instead of storing accumulated rewards, we store the "checkpoint" values
    // This allows us to only distribute rewards that have occurred since the last claim
    struct ClaimCheckpoint {
        uint256 lastClaimedPurchases;  // Last claimed purchase count
        uint256 lastClaimedSales;      // Last claimed sales count
    }

    // Mapping: token => user => checkpoint
    mapping(address => mapping(address => ClaimCheckpoint)) public lastClaimCheckpoints;

    // Governance staking contract address
    address public governanceVault;

    // Address for purchase tracker 
    address public purchaseTracker;

    // Address for rewards calculator 
    ICommunityRewardsCalculator public rewardsCalculator;

    // Events
    event Deposit(address indexed token, address indexed from, uint256 amount);
    event Withdraw(address indexed token, address indexed to, uint256 amount);
    event Distribute(address indexed token, address indexed to, uint256 amount);
    event RewardDistributed(address indexed token, address indexed recipient, uint256 amount, uint256 newPurchaseCheckpoint, uint256 newSalesCheckpoint);

    /**
     * @dev Constructor to initialize the security context.
     * @param _securityContext Address of the HatsSecurityContext contract.
     */
    constructor(address _securityContext) {
        if (address(_securityContext) == address(0)) revert ZeroAddressArgument();
        _setSecurityContext(ISecurityContext(_securityContext));
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

        emit Deposit(token, msg.sender, amount);
    }

    /**
     * @dev Withdraw tokens or ETH from the community vault
     * @param token The address of the token (use address(0) for ETH)
     * @param to The address to send the tokens or ETH to
     * @param amount The amount to withdraw
     */
    function withdraw(address token, address to, uint256 amount) external onlyRole(Roles.SYSTEM_ROLE) {
        require(this.getBalance(token) >= amount, "Insufficient balance");

        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).safeTransfer(to, amount);
        }

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
    ) external onlyRole(Roles.SYSTEM_ROLE) {
        _distribute(token, recipients, amounts);
    }

    /**
     * @dev Distribute tokens or ETH from the community vault to multiple recipients, using the 
     *      CommunityRewardsCalculator to calculate the amounts to reward each recipient.
     * @param token The address of the token 
     * @param recipients The array of recipient addresses
     */
    function distributeRewards(address token, address[] memory recipients) external onlyRole(Roles.SYSTEM_ROLE) {
        _distributeRewards(token, recipients);
    }

    /**
     * @dev Allows a rightful recipient of rewards to claim rewards that have been allocated to them.
     * @param token The address of the token 
     */
    function claimRewards(address token) external {
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        _distributeRewards(token, recipients);
    }

    /**
     * @dev Set the governance vault address and grant it unlimited allowance for `lootToken`.
     *      Must be called by an admin role or similar.
     * @param vault The address of the governance vault
     * @param lootToken The address of the ERC20 token for which you'd like to grant unlimited allowance
     */
    function setGovernanceVault(address vault, address lootToken) external onlyRole(Roles.SYSTEM_ROLE)  {
        require(vault != address(0), "Invalid staking contract address");
        require(lootToken != address(0), "Invalid loot token address");

        governanceVault = vault;

        // Grant unlimited allowance to the governance vault
        IERC20(lootToken).safeApprove(vault, 0);
        IERC20(lootToken).safeApprove(vault, type(uint256).max);
    }

    /**
     * @dev Sets the purchase tracker that is used to keep track of who has done what, in order to get rewards. 
     */
    function setPurchaseTracker(address _purchaseTracker) external onlyRole(Roles.SYSTEM_ROLE) {
        require(_purchaseTracker != address(0), "Invalid purchase tracker address");
        
        purchaseTracker = _purchaseTracker;
    }

    /**
     * @dev Sets the address of the contract which holds the logic for calculating how to divide up rewards. 
     */
    function setCommunityRewardsCalculator(ICommunityRewardsCalculator calculator) external onlyRole(Roles.SYSTEM_ROLE) {
        rewardsCalculator = calculator;
    }

    /**
     * @dev Get the balance of a token in the community vault
     * @param token The address of the token
     */
    function getBalance(address token) external view returns (uint256) {
        if (token == address(0)) return (address(this)).balance;
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev For backward compatibility - returns the total rewards distributed to a recipient
     * @param token The token address
     * @param recipient The recipient address
     * @return The sum of all previous rewards
     */
    function rewardsDistributed(address token, address recipient) external view returns (uint256) {
        if (address(purchaseTracker) == address(0)) return 0;
        
        ClaimCheckpoint memory checkpoint = lastClaimCheckpoints[token][recipient];
        return checkpoint.lastClaimedPurchases + checkpoint.lastClaimedSales;
    }

    function _distributeRewards(address token, address[] memory recipients) internal {
        if (address(rewardsCalculator) == address(0) || address(purchaseTracker) == address(0)) {
            return;
        }
        
        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            
            // Get the current checkpoint for this user/token
            ClaimCheckpoint memory checkpoint = lastClaimCheckpoints[token][recipient];
            
            // Get current totals from purchase tracker
            uint256 currentPurchases = IPurchaseTracker(purchaseTracker).getPurchaseCount(recipient);
            uint256 currentSales = IPurchaseTracker(purchaseTracker).getSalesCount(recipient);
            
            // Calculate reward using the calculator
            uint256 totalReward = rewardsCalculator.calculateUserRewards(
                token,
                recipient,
                IPurchaseTracker(purchaseTracker),
                checkpoint.lastClaimedPurchases,
                checkpoint.lastClaimedSales
            );
            
            if (totalReward > 0) {
                // Update the checkpoint before distribution to prevent reentrancy
                lastClaimCheckpoints[token][recipient] = ClaimCheckpoint(
                    currentPurchases,
                    currentSales
                );
                
                // Distribute rewards
                if (token == address(0)) {
                    // ETH distribution
                    require(address(this).balance >= totalReward, "Insufficient ETH balance");
                    (bool success, ) = recipient.call{value: totalReward}("");
                    require(success, "ETH transfer failed");
                } else {
                    // ERC20 distribution
                    require(IERC20(token).balanceOf(address(this)) >= totalReward, "Insufficient token balance");
                    IERC20(token).safeTransfer(recipient, totalReward);
                }
                
                emit RewardDistributed(token, recipient, totalReward, currentPurchases, currentSales);
            }
        }
    }

    function _distribute(
        address token,
        address[] memory recipients,
        uint256[] memory amounts
    ) internal {
        require(recipients.length == amounts.length, "Mismatched arrays");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(this.getBalance(token) >= amounts[i], "Insufficient balance");

            if (token == address(0)) {
                // ETH distribution
                (bool success, ) = recipients[i].call{value: amounts[i]}("");
                require(success, "ETH transfer failed");
            } else {
                // ERC20 distribution
                IERC20(token).safeTransfer(recipients[i], amounts[i]);
            }

            emit Distribute(token, recipients[i], amounts[i]);
        }
    }

    // Fallback to receive ETH
    receive() external payable {}
}
