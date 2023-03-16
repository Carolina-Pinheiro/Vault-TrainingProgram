// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { LinkedList } from "src/src-default/LinkedList.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

contract LinkedListTest is Test, ILinkedList {
    LinkedList list;
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);
    address public vault = vm.addr(15);

    function setUp() external {
        // Set-up the addresses
        vm.label(lucy, "Lucy");
        vm.label(phoebe, "Phoebe");
        vm.label(julien, "Julien");
        vm.label(vault, "Vault");

        // Initialize list
        vm.prank(vault);
        list = new LinkedList();
    }

    // Tests if the first node is being inserted into the list correctly
    function testInsertFirstNode() external {
        uint256 endTime = 100;
        vm.startPrank(vault);
        (uint256 previousId, uint256 nextId) = list.findPosition(endTime, list.getHead());

        assertEq(previousId, 0);
        assertEq(nextId, 0);

        Node memory node_ = Node({
            nextId: nextId,
            startTime: endTime - 10,
            endTime: endTime,
            share: 10,
            currentTotalWeight: 0,
            owner: julien,
            depositedLPTokens: 40
        });

        list.insert(node_, previousId);

        node_ = list.getNode(list.getMostRecentId());

        assertEq(node_.nextId, 0); // nextId initialized correctly
        assertEq(list.getHead(), 1); // first node is head
        assertEq(list.getTail(), 1); // first node is tail

        vm.stopPrank();
    }

    // Test insert new node in various situations
    function testInsertNewNode() external {
        // Insert first node - (new deposit) // 1
        uint256 endTime = 100;
        vm.startPrank(vault);
        (uint256 previousId, uint256 nextId) = list.findPosition(endTime, list.getHead());
        Node memory newNode_ = Node({
            nextId: nextId,
            startTime: endTime - 10,
            endTime: endTime,
            share: 10,
            currentTotalWeight: 0,
            owner: julien,
            depositedLPTokens: 40
        });

        list.insert(newNode_, previousId);

        // Insert a new node - (lock-up ends) // 1 2
        endTime = endTime + 500;
        (previousId, nextId) = list.findPosition(endTime, list.getHead());
        newNode_ = Node({
            nextId: nextId,
            startTime: endTime - 10,
            endTime: endTime,
            share: 20,
            currentTotalWeight: 0,
            owner: julien,
            depositedLPTokens: 40
        });
        list.insert(newNode_, previousId);
        assertEq(list.getHead(), 1); // the first node is the head
        assertEq(list.getNextIdOfNode(1), 2); // the first node is connected to this new node
        assertEq(list.getTail(), 2); // the new node is the tail

        // Insert a new node between both of them // 1 3 2
        endTime = endTime - 50;
        (previousId, nextId) = list.findPosition(endTime, list.getHead());
        newNode_ = Node({
            nextId: nextId,
            startTime: endTime - 10,
            endTime: endTime,
            share: 30,
            currentTotalWeight: 0,
            owner: julien,
            depositedLPTokens: 40
        });
        list.insert(newNode_, previousId);
        assertEq(list.getHead(), 1); // the first node is the head
        assertEq(list.getNextIdOfNode(1), 3); // the first node is connected to this new node
        assertEq(list.getNextIdOfNode(3), 2); // the new node is connected to the second one
        assertEq(list.getTail(), 2); // the second node is the tail

        // Insert a new node supposed to be in the second position // 1 4 3 2
        endTime = 110;
        (previousId, nextId) = list.findPosition(endTime, list.getHead());
        newNode_ = Node({
            nextId: nextId,
            startTime: endTime - 10,
            endTime: endTime,
            share: 40,
            currentTotalWeight: 0,
            owner: julien,
            depositedLPTokens: 40
        });
        list.insert(newNode_, previousId);
        assertEq(list.getHead(), 1); // the first node is the head
        assertEq(list.getNextIdOfNode(1), 4); // the first node is connected to this new node
        assertEq(list.getNextIdOfNode(4), 3); // the new node is connected to the third one
        assertEq(list.getNextIdOfNode(3), 2); // the third node is connected to the second one
        assertEq(list.getTail(), 2); // the second node is the tail

        vm.stopPrank();
    }
}
