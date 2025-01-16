// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@baal/Baal.sol";

contract CustomBaal is Baal {
    /// @notice Override the ragequit function to exclude the community vault from calculations
    function _ragequit(
        address to,
        uint256 sharesToBurn,
        uint256 lootToBurn,
        address[] memory tokens
    ) internal override {
        uint256 _totalSupply = totalLoot();

        // Ensure shares and loot to burn are valid
        if (lootToBurn != 0) {
            _burnLoot(_msgSender(), lootToBurn);
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance;

            if (tokens[i] == ETH) {
                balance = address(target).balance;
            } else {
                (, bytes memory balanceData) = tokens[i].staticcall(
                    abi.encodeWithSelector(0x70a08231, address(target))
                );
                balance = abi.decode(balanceData, (uint256));
            }

            // Exclude the community vault from ragequit calculations
            uint256 communityBalance = _getCommunityVaultBalance(tokens[i]);
            uint256 adjustedBalance = balance > communityBalance
                ? balance - communityBalance
                : 0;

            uint256 amountToRagequit = ((lootToBurn + sharesToBurn) *
                adjustedBalance) / _totalSupply;

            if (amountToRagequit != 0) {
                tokens[i] == ETH
                    ? _safeTransferETH(to, amountToRagequit)
                    : _safeTransfer(tokens[i], to, amountToRagequit);
            }
        }

        emit Ragequit(_msgSender(), to, lootToBurn, sharesToBurn, tokens);
    }

    function _getCommunityVaultBalance(address token) internal view returns (uint256) {
        // Logic to get the community vault balance for the specified token
        return 0;
    }
}
