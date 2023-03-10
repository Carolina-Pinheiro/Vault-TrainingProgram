// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Token } from "src/Token.sol";
import { Vault } from "src/Vault.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";

contract TokenTest is Test {
    Token token;
    Vault vault;
    LZEndpointMock lzEndpoint;
    address public ownerVault = vm.addr(11);
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(lucy, "Lucy");
        vm.label(phoebe, "Phoebe");
        vm.label(julien, "Julien");
        vm.startPrank(ownerVault);
        vault = new Vault();
        lzEndpoint = new LZEndpointMock(1); // 1 = chainId
        token = new Token(address(lzEndpoint), address(vault));
        vm.stopPrank();
    }

    // Tests if the owner is being correctly initialized and saved
    function testMintOnlyByVault() external {
        // Vault tries to mint tokens to a user
        vm.prank(address(vault));
        token.mint(lucy, 10);

        // Assert that the user received the tokens and the total supply is updated
        assertEq(token.balanceOf(lucy), 10);
        assertEq(token.totalSupply(), 10);

        // Someone who is not the vault tries to mint tokens
        vm.startPrank(phoebe);
        vm.expectRevert();
        token.mint(julien, 10);
        vm.stopPrank();
    }
}
