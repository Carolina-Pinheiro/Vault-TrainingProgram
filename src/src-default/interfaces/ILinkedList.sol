// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILinkedList {
    /**
     * @notice A node of the linked list.
     * @param endTime The value of the node.
     * @dev Use this to pass parameters to the insert function.
     */
    struct Node {
        uint256 nextId;
        uint256 endTime; // in case of nd it is 'now', le it is 'now+lock-up time'
        uint256 share; // + for nd, - for le
        uint256 depositedLPTokens;
        uint256 currentTotalWeight;
        address owner;
    }
}
