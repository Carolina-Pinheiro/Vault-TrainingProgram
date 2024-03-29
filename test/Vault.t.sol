// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Vault } from "src/Vault.sol";

contract VaultTest is Test, Vault {
    Vault vault;
    address public ownerVault = vm.addr(10);
    address public barbie = vm.addr(11);

    event LogAddress(address);

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(barbie, "Barbie");
        vm.prank(ownerVault);
        vault = new Vault();
    }

    function testRewardsMultiplier() external {
        // Test the 4 tiers
        uint8[4] memory rewardsTiers = [6, 1, 2, 4]; // 6 months, 1 year, 2 years, 4 years
        uint8[4] memory expectedRewardsMultiplier = [1, 2, 4, 8];
        uint256 rewardsMultiplier;
        vm.startPrank(barbie);
        for (uint256 i = 0; i < 4; i++) {
            vault.deposit(1, rewardsTiers[i]);
            (, rewardsMultiplier,,,) = vault.depositList(barbie, i);
            assertEq(rewardsMultiplier, expectedRewardsMultiplier[i]);
        }

        //Test with an incorrect lock up period
        vm.expectRevert();
        vault.deposit(1, 3);

        vm.stopPrank();
    }
}
