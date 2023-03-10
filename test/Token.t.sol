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
    address public ownerVault = address(9_032_023);
    address public barbie = address(2005);

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(barbie, "Barbie");
        vm.startPrank(ownerVault);
        vault = new Vault();
        lzEndpoint = new LZEndpointMock(1); // 1 = chainId
        token = Token(address(lzEndpoint));
        vm.stopPrank();
    }

    // Tests if the owner is being correctly initialized and saved
    function testTest() external {
        // do nothing
    }
}
