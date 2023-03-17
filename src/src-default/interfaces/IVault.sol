// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

interface IVault is ILinkedList {
    event LogUint(uint256);
    event LogRewardsTokenMinted(address, uint256);
    event LogNode(Node);
    //event LogWithdrawHasNotExpired(uint256);
    event LogDepositExpired(address,uint256); // Owner and deposit id
}
