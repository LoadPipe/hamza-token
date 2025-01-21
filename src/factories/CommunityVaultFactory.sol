// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../CommunityVault.sol";

contract CommunityVaultFactory {
    event CommunityVaultDeployed(address indexed creator, address vault);

    function deploy(address hatsSecurityContext) external returns (address) {
        CommunityVault vault = new CommunityVault(hatsSecurityContext);
        emit CommunityVaultDeployed(msg.sender, address(vault));
        return address(vault);
    }
}
