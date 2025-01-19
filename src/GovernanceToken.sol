// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "./security/HasSecurityContext.sol"; 

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, ERC20Wrapper {
    constructor(IERC20 wrappedToken, string memory name_, string memory symbol_) 
        ERC20("HamGov", "HAM") ERC20Permit("HamGov") ERC20Wrapper(wrappedToken) {}

    function decimals() public view override(ERC20, ERC20Wrapper) returns(uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external /* onlyRole(MINTER_ROLE) */ {
        super._mint(to, amount);
    }

    function burn(address account, uint256 amount) external /* onlyRole(BURNER_ROLE) */ {
        super._burn(account, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) pure {
        
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) pure {
        
    }

    function transferFromNoAllowance(address from, address to, uint256 amount) external /* onlyRole(MINTER_ROLE) */ {
        _approve(from, address(this), amount);
        this.transferFrom(from, to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {}

    // including this excludes from coverage report foundry
    function test() public {}
}