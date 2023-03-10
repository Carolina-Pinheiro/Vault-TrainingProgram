// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.0;

import { Test } from "@forge-std/Test.sol";
import { Vault } from "src/Vault.sol";

contract VaultTest is Test, Vault {
    Vault vault;
    address public ownerVault = address(9032023);
    address public barbie = address(2005);

    event LogAddress(address);

    function setUp() external{
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(barbie, "Barbie");
        vm.startPrank(ownerVault);
        vault = new Vault();
        vm.stopPrank();
    }

    // Tests if the owner is being correctly initialized and saved
    function testOwnership() external{
        assertEq(ownerVault, vault.owner());
    }

    function testRewardsMultiplier() external{
        vm.startPrank(barbie);

        // Test the 4 tiers
        vault.deposit(1,6);
        vault.deposit(1,1);
        vault.deposit(1,2);
        vault.deposit(1,4);
        vm.stopPrank();

        (, uint256 rewardsMultiplier6Months,,,) = vault.depositList(vault.ownersDepositId(barbie, 0));
        (, uint256 rewardsMultiplier1Year,,,) = vault.depositList(vault.ownersDepositId(barbie, 1));
        (, uint256 rewardsMultiplier2Years,,,) = vault.depositList(vault.ownersDepositId(barbie, 2));
        (, uint256 rewardsMultiplier4Years,,,) = vault.depositList(vault.ownersDepositId(barbie, 3));

        assertEq(rewardsMultiplier6Months, 1);  // 6 months
        assertEq(rewardsMultiplier1Year, 2);  // 1 year
        assertEq(rewardsMultiplier2Years, 4);  // 2 years
        assertEq(rewardsMultiplier4Years, 8);  // 4 years

        //Test with an incorrect lock up period
        vm.startPrank(barbie);
        vm.expectRevert(
            "Lock up period chosen is not possible, choose between 6 (6 months), 1 (1 year), 2 (2 yeats) or 4 (4 years)"
        );
        vault.deposit(1, 3);
        vm.stopPrank();
    }

}