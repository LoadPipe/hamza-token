// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import "@hamza-escrow/security/HasSecurityContext.sol"; 

contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes, ERC20Wrapper, HasSecurityContext {
    constructor(ISecurityContext _securityContext, IERC20 wrappedToken, string memory /*name_*/, string memory /*symbol_*/) 
        ERC20("HamGov", "HAM") ERC20Permit("HamGov") ERC20Wrapper(wrappedToken) {
            _setSecurityContext(_securityContext);
        }

    function decimals() public view override(ERC20, ERC20Wrapper) returns(uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external /* onlyRole(MINTER_ROLE) */ {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external /* onlyRole(BURNER_ROLE) */ {
        _burn(account, amount);
    }
    
    function depositFor(address account, uint256 amount) public override(ERC20Wrapper) returns (bool) /* onlyRole(MINTER_ROLE) */ {
        return super.depositFor(account, amount);
    }

    function withdrawTo(address account, uint256 amount) public override(ERC20Wrapper) returns (bool) /* onlyRole(MINTER_ROLE) */ {
        return super.withdrawTo(account, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
        //TODO: this line is suspect
        _delegate(to, to);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {

        super._afterTokenTransfer(from, to, amount);
    }
}