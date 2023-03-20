// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Vault } from "src/src-default/Vault.sol";


contract VaultUpgrade is Vault{

    constructor(address LPToken_) Vault(LPToken_) {
    }

    /// @dev updates an claimRewards to return a specific a number to test if the implementation is correct
    function claimRewards(uint256 rewardsToClaim) external override returns (uint256) {
        return (rewardsToClaim*2);
    }

}