// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { VaultV2 } from "src/src-default/VaultV2.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";
import { Test } from "@forge-std/Test.sol"; // so vm cheat codes and others can be used
import { PoolToken } from "test/PoolToken.sol";
import { Token } from "src/src-default/Token.sol";
import { WETH9 } from "test/WETH9.sol";


contract Handler is Test {

    VaultV2 public vault1;
    VaultV2 public vault2;
    PoolToken public poolToken;
    Token public rewardToken;
    WETH9 public weth;
    address LPToken;
    address router;

    uint256 _time = 52 weeks;
    address public ownerVault = vm.addr(11);
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);
    address public dacus = vm.addr(15);

    bool success;
    bytes data;

    event LogId(uint256);
    event LogAddr(address);
    
    address[] public _chainToVault = new address[](2);

    constructor(VaultV2 vault1_, VaultV2 vault2_, PoolToken poolToken_, WETH9 weth_, address LPToken_, address router_){
        vault1 = vault1_;
        emit LogAddr(address(vault1));

        _chainToVault[0] = address(vault1);
        emit LogAddr(address(_chainToVault[0] ));
        
        vault2 = vault2_;
        _chainToVault[1] = address(vault2);
        emit LogAddr(address(_chainToVault[1] ));

        poolToken = poolToken_;
        weth = weth_;
        LPToken = LPToken_;
        router = router_;
    }

    modifier wrapTime(){
        vm.warp(_time);
        _time = _time + 600;  // 10 minutes between each action at least
        _;
    }

    function deposit(uint256 amount_, uint256 seedLockUpPeriod_, address actorAddress_, uint256 seedChain_) public wrapTime{
        vm.stopPrank();
        // Create a lockUpPeriod that is restricted between 0 and 6. 1,2,4,6 will pass; 0,3,5 will fail
        uint256 lockUpPeriod_ = seedLockUpPeriod_ % 6;
        uint256 id = bound(seedChain_ % 2,0,1);
        address vaultUsed_ = _chainToVault[id];
        
        // Set up actor so it can interact w/the vault - actor gets and approves tokens to the vault
        _actorSetUp(actorAddress_, address(vaultUsed_));
        
        // Make a deposit
        emit LogId(id);
        vm.prank(actorAddress_);
        bool success = IVault(vaultUsed_).deposit(amount_, lockUpPeriod_);

        if (success) {
            string memory s1 = string.concat("Vault", uint2str(seedChain_%2));
            vm.writeLine("test/invariant/handlers/out.txt", s1);
        }
    }



    // -----------------------------------------------
    // Helper functions
    // -----------------------------------------------
    function _actorSetUp(address actor_, address vault_) internal {
        vm.deal(actor_, 1000 ether);
        vm.prank(lucy); // owner of the pool
        poolToken.mint(actor_, 1500 ether);
        vm.startPrank(actor_);
        uint256 balance = _userGetLPTokens(actor_);
        //Approve  tokens to the vault
        _approveTokens(balance, address(vault_));
        // Pass some time so block.timestamp is more realistic
        vm.stopPrank();
    }


    // Function used to give LPTokens to a user, must be preeced with startPrank
    function _userGetLPTokens(address user) internal returns (uint256) {
        uint256 ethAmount = 1000 ether;
        // Wrap the ETH
        weth.deposit{ value: ethAmount }();

        // Use Pool to have LP tokens
        poolToken.approve(address(router), ethAmount);
        weth.approve(address(router), ethAmount);
        (success,) = router.call(
            abi.encodeWithSignature(
                "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)",
                address(poolToken),
                address(weth),
                ethAmount,
                ethAmount,
                ethAmount,
                ethAmount,
                user, //recipient
                block.timestamp * 2
            )
        );
        require(success);

        // Make sure that the user received liquidty tokens
        (success, data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", user));
        require(success);
        uint256 balance = abi.decode(data, (uint256));
        assertGt(balance, 0);

        return balance;
    }


    
    function _approveTokens(uint256 amount_, address to_) internal {
        (success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", to_, amount_));
        require(success);
    }

    
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }

}