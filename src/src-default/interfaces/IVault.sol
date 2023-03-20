// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

interface IVault is ILinkedList {
    //-----------------------------------------------------------------------
    //------------------------------LOGS-------------------------------------
    //-----------------------------------------------------------------------
    event LogUint(uint256);
    event LogRewardsTokenMinted(address, uint256);
    event LogNode(Node);
    event LogDepositExpired(address,uint256); // Owner and deposit id
    event LogWithdrawHasNotExpired(uint256);
    event LogUintArray(uint256[]);
    event LogWithdraw(address,uint256);

    //-----------------------------------------------------------------------
    //------------------------------ERRORS-----------------------------------
    //-----------------------------------------------------------------------
    error NoRewardsToClaimError();
    error TransferOfLPTokensWasNotPossibleError();
    error NotEnoughAmountOfTokensDepositedError();

}
