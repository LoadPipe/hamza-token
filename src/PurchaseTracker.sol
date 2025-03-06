// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@hamza-escrow/security/HasSecurityContext.sol";

/**
 * @title PurchaseTracker
 * @notice A singleton contract that records purchase data.
 *
 */
contract PurchaseTracker is HasSecurityContext {
    using SafeERC20 for IERC20;

    // Mapping from buyer address to cumulative purchase count and total purchase amount.
    mapping(address => uint256) public totalPurchaseCount;
    mapping(address => uint256) public totalPurchaseAmount;

    // mapping for sellers 
    mapping(address => uint256) public totalSalesCount;
    mapping(address => uint256) public totalSalesAmount;

    // mapping rewards distributed
    mapping(address => uint256) public rewardsDistributed;
    
    // Store details about each purchase (keyed by the unique payment ID).
    mapping(bytes32 => Purchase) public purchases;

    //Comunity Vault address
    address public communityVault;

    // loot token 
    IERC20 public lootToken;
    
    struct Purchase {
        address seller;
        address buyer;
        uint256 amount;
        bool recorded;
    }
    
    // Authorized contracts (such as escrow contracts) that are allowed to record purchases.
    mapping(address => bool) public authorizedEscrows;
    
    event PurchaseRecorded(bytes32 indexed paymentId, address indexed buyer, uint256 amount);
    
    modifier onlyAuthorized() {
        require(authorizedEscrows[msg.sender], "PurchaseTracker: Not authorized");
        _;
    }
    
    constructor(ISecurityContext securityContext, address _communityVault, address _lootToken) {
        communityVault = _communityVault;
        lootToken = IERC20(_lootToken);
        _setSecurityContext(securityContext);
    }
    
    /**
     * @notice Authorizes an escrow (or other) contract to record purchases.
     * @param escrow The address of the escrow contract.
     */
    function authorizeEscrow(address escrow) external onlyRole(Roles.SYSTEM_ROLE) {
        authorizedEscrows[escrow] = true;
    }
    
    /**
     * @notice Removes authorization for an escrow contract.
     * @param escrow The address to deauthorize.
     */
    function deauthorizeEscrow(address escrow) external onlyRole(Roles.SYSTEM_ROLE) {
        authorizedEscrows[escrow] = false;
    }
    
    /**
     * @notice Records a purchase.
     * @param paymentId The unique payment ID.
     * @param buyer The address of the buyer 
     * @param seller The address of the seller
     * @param amount The purchase amount.
     *
     * Requirements:
     * - The caller must be an authorized contract.
     * - A purchase with the same paymentId must not have been recorded already.
     */
    function recordPurchase(bytes32 paymentId, address seller, address buyer, uint256 amount) external onlyAuthorized {
        require(!purchases[paymentId].recorded, "PurchaseTracker: Purchase already recorded");
        
        purchases[paymentId] = Purchase(seller, buyer, amount, true);
        totalPurchaseCount[buyer] += 1;
        totalPurchaseAmount[buyer] += amount;

        //log seller info 
        totalSalesCount[seller] += 1;
        totalSalesAmount[seller] += amount;
        
        emit PurchaseRecorded(paymentId, buyer, amount);
    }
    
    // distrubte reward from communtiy vault
    function distributeReward(address recipient) external {
        // for every purchase or sale made by the recipient, distribute 1 loot token
        uint256 totalPurchase = totalPurchaseCount[recipient];
        uint256 totalSales = totalSalesCount[recipient];
        uint256 rewardsDist = rewardsDistributed[recipient];

        uint256 totalRewards = totalPurchase + totalSales - rewardsDist;

        require(totalRewards > 0, "PurchaseTracker: No rewards to distribute");

        // transfer loot token from community vault to recipient
        lootToken.safeTransferFrom(communityVault, recipient, totalRewards);

        rewardsDistributed[recipient] += totalRewards;
    }

   
}
