// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ILinkedList {
    //-----------------------------------------------------------------------
    //------------------------------STRUCT-----------------------------------
    //-----------------------------------------------------------------------
    /// @notice A node of the linked list.
    /// @param endTime The value of the node.
    /// @dev Use this to pass parameters to the insert function.
    struct Node {
        uint256 nextId;
        uint256 endTime; // in case of nd it is 'now', le it is 'now+lock-up time'
        uint256 share; // + for nd, - for le
        uint256 depositedLPTokens;
        uint256 currentTotalWeight;
        address owner;
    }

    //-----------------------------------------------------------------------
    //------------------------------ERRORS-----------------------------------
    //-----------------------------------------------------------------------

    //-----------------------------------------------------------------------
    //--------------------------FUNCTION-HEADERS-----------------------------
    //-----------------------------------------------------------------------

    //------------------------------EXTERNAL----------------------------------
    /// @notice gets the most recent id created (id of the most recent deposit)
    /// @return id of the most recent deposit
    function getMostRecentId() external view returns (uint256);

    /// @notice gets the node according to an id
    /// @param id_ of the deposit
    /// @return node corresponding to the id
    function getNode(uint256 id_) external view returns (Node memory);
}
