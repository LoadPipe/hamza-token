// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./security/HasSecurityContext.sol"; 

contract GovernanceToken is ERC20, HasSecurityContext {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        super._mint(to, amount);
    }

    function burn(address account, uint256 amount) external {
        super._burn(account, amount);
    }

    // including this excludes from coverage report foundry
    function test() public {}
}