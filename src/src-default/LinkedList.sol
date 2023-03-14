// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

contract LinkedList is ILinkedList {
    address public vault;

    modifier onlyVault() {
        require(msg.sender == vault);
        _;
    }

    /// @notice The head of the linked list.
    uint256 private _head;
    /// @notice The tail of the linked list.
    uint256 private _tail;

    /**
     * @notice Maps an Id to a node.
     */
    mapping(uint256 => Node) private _nodes;

    /// @notice The nonce for the linked list.
    uint256 private _id = 0;

    constructor() {
        vault = msg.sender;
    }

    /**
     * @notice Inserts a node into the linked list.
     * @param node_ The new node.
     * @param previousNodeId_ The slot of the previous node.
     */
    function insert(Node memory node_, uint256 previousNodeId_) public {
        uint256 currId_ = ++_id;

        _nodes[currId_] = node_;

        // If the node is not the last, set the next node.
        if (node_.nextId == 0) _tail = currId_;

        // If the node is not the first, set the previous node to point to the new node.
        if (previousNodeId_ != 0) _nodes[previousNodeId_].nextId = currId_;
        // If the node is the first, then it is the new head.
        else _head = currId_;
    }

    /**
     * @notice Removes a node from the linked list.
     * @dev Deleting the node will actually spend more gas, so we just leave it "as is".
     * @param previousNodeId_ The previous node.
     * @param nextNodeId_ The next node.
     */
    function remove(uint256 previousNodeId_, uint256 nextNodeId_) public {
        // If the next node is null, the previous node becomes the tail.
        if (nextNodeId_ == 0) _tail = previousNodeId_;

        // If the removed node is not the head, set the next node of the previous node to the next node.
        if (previousNodeId_ != 0) _nodes[previousNodeId_].nextId = nextNodeId_;
        // If the previous node is null, the current node is the head, so set the head as the next node.
        else _head = nextNodeId_;
    }

    /**
     * @notice Returns the head of the linked list.
     * @return The head of the linked list.
     */
    function getHead() external view returns (uint256) {
        return _head;
    }

    /**
     * @notice Returns the tail of the linked list.
     * @return The tail of the linked list.
     */
    function getTail() external view returns (uint256) {
        return (_getTail());
    }

    function getNode(uint256 id_) external view returns (Node memory) {
        return _nodes[id_];
    }

    function getNextIdOfNode(uint256 id_) external view onlyVault returns (uint256) {
        return (_getNextIdOfNode(id_));
    }

    function getEndTimeOfNode(uint256 id_) external view onlyVault returns (uint256) {
        return (_getEndTimeOfNode(id_));
    }

    function getMostRecentId() external view onlyVault returns (uint256) {
        return (_getMostRecentId());
    }

    function _getEndTimeOfNode(uint256 id_) internal view returns (uint256) {
        return _nodes[id_].endTime;
    }

    function _getNextIdOfNode(uint256 id_) internal view returns (uint256) {
        return _nodes[id_].nextId;
    }

    function _getMostRecentId() internal view returns (uint256) {
        return (_id);
    }

    function _getTail() internal view onlyVault returns (uint256) {
        return _tail;
    }

    /**
     * @notice Finds the position of a new node based on the endTime
     * @return (previousId, nextId) the previous id and the next id where the node will be inserted
     */
    function findPosition(uint256 endTime, uint256 firstIdToSearch)
        external
        view
        onlyVault
        returns (uint256, uint256)
    {
        uint256 currId = firstIdToSearch;

        if (_id == 0) {
            // the list is empty
            return (0, 0); // node will be both the head and the tail
        }

        while (
            _getEndTimeOfNode(_getNextIdOfNode(currId)) < endTime // finds the nodes between which to insert
                && _getTail() != currId // or is at the end of the list
        ) {
            currId = _getNextIdOfNode(currId);
        }
        uint256 previousId = currId;
        uint256 nextId = _getNextIdOfNode(currId);

        return (previousId, nextId);
    }
}
