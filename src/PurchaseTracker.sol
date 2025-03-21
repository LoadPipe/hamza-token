// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@hamza-escrow/security/HasSecurityContext.sol";
import "@hamza-escrow/IPurchaseTracker.sol";

/**
 * @title PurchaseTracker
 * @notice A singleton contract that records purchase data.
 *
 */
contract PurchaseTracker is HasSecurityContext, IPurchaseTracker {
    using SafeERC20 for IERC20;

    // Mapping from buyer address to cumulative purchase count and total purchase amount.
    mapping(address => uint256) public totalPurchaseCount;
    mapping(address => uint256) public totalPurchaseAmount;
    mapping(address => mapping(address => uint256)) public purchaseAmountByCurrency;
    
    // mapping for sellers 
    mapping(address => uint256) public totalSalesCount;
    mapping(address => uint256) public totalSalesAmount;
    mapping(address => mapping(address => uint256)) public salesAmountByCurrency;
    
    // Store details about each purchase (keyed by the unique payment ID).
    mapping(bytes32 => Purchase) public purchases;

    // loot token 
    IERC20 public lootToken;
    
    struct Purchase {
        address seller;
        address buyer;
        uint256 amount;
        address currency;
        bool recorded;
    }
    
    // Authorized contracts (such as escrow contracts) that are allowed to record purchases.
    mapping(address => bool) public authorizedEscrows;
    
    event PurchaseRecorded(bytes32 indexed paymentId, address indexed buyer, uint256 amount, address currency);
    
    modifier onlyAuthorized() {
        require(authorizedEscrows[msg.sender], "PurchaseTracker: Not authorized");
        _;
    }
    
    constructor(ISecurityContext securityContext, address _lootToken) {
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
     * @param seller The address of the seller
     * @param buyer The address of the buyer 
     * @param amount The purchase amount.
     * @param currency The currency used for the purchase.
     *
     * Requirements:
     * - The caller must be an authorized contract.
     * - A purchase with the same paymentId must not have been recorded already.
     */
    function recordPurchase(bytes32 paymentId, address seller, address buyer, uint256 amount, address currency) external onlyAuthorized {
        _recordPurchase(paymentId, seller, buyer, amount, currency);
    }
    
    /**
     * @notice Legacy recordPurchase function for backward compatibility.
     * Now calls the new function with a default currency of address(0).
     */
    function recordPurchase(bytes32 paymentId, address seller, address buyer, uint256 amount) external onlyAuthorized {
        _recordPurchase(paymentId, seller, buyer, amount, address(0));
    }
    
    /**
     * @dev Internal implementation of recordPurchase that both external functions call.
     */
    function _recordPurchase(bytes32 paymentId, address seller, address buyer, uint256 amount, address currency) internal {
        require(!purchases[paymentId].recorded, "PurchaseTracker: Purchase already recorded");
        
        purchases[paymentId] = Purchase(seller, buyer, amount, currency, true);
        totalPurchaseCount[buyer] += 1;
        totalPurchaseAmount[buyer] += amount;
        purchaseAmountByCurrency[buyer][currency] += amount;

        //log seller info 
        totalSalesCount[seller] += 1;
        totalSalesAmount[seller] += amount;
        salesAmountByCurrency[seller][currency] += amount;
        
        emit PurchaseRecorded(paymentId, buyer, amount, currency);
    }

    function getPurchaseCount(address recipient) external view returns (uint256) {
        return totalPurchaseCount[recipient];
    }

    function getPurchaseAmount(address recipient) external view returns (uint256) {
        return totalPurchaseAmount[recipient];
    }

    function getSalesCount(address recipient) external view returns (uint256) {
        return totalSalesCount[recipient];
    }

    function getSalesAmount(address recipient) external view returns (uint256) {
        return totalSalesAmount[recipient];
    }

    function getPurchaseAmountByCurrency(address recipient, address currency) external view returns (uint256) {
        return purchaseAmountByCurrency[recipient][currency];
    }

    function getSalesAmountByCurrency(address recipient, address currency) external view returns (uint256) {
        return salesAmountByCurrency[recipient][currency];
    }
}
