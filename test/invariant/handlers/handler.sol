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

    uint256 private _time = 52 weeks;

    address public ownerVault = vm.addr(11);
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);
    address public dacus = vm.addr(15);

    bool success;
    bytes data;

    event LogId(uint256);
    event LogAddr(address);

    uint256 constant NUM_ACTORS = 10;
    uint256 constant REWARDS_PER_SECOND = 317;

    VaultV2[] private _chainToVault = new VaultV2[](2);
    address[] private _actors = new address[](NUM_ACTORS);

    constructor(
        VaultV2 vault1_,
        VaultV2 vault2_,
        PoolToken poolToken_,
        WETH9 weth_,
        address LPToken_,
        address router_
    ) {
        vault1 = vault1_;
        emit LogAddr(address(vault1));

        _chainToVault[0] = vault1;
        emit LogAddr(address(_chainToVault[0]));

        vault2 = vault2_;
        _chainToVault[1] = vault2;
        emit LogAddr(address(_chainToVault[1]));

        poolToken = poolToken_;
        weth = weth_;
        LPToken = LPToken_;
        router = router_;

        _actors = _createActors(NUM_ACTORS);
    }

    modifier wrapTime(uint256 time_) {
        if (_time == 52 weeks) {
            vm.writeLine(
                "test/invariant/handlers/out.txt", "------------------------------NEW RUN------------------------"
            );
        }
        time_ = bound(time_, 600, 50_000);
        _time = _time + time_;
        vm.warp(_time);
        string memory s2 = string.concat("Time: ", uint2str(_time));
        vm.writeLine("test/invariant/handlers/out.txt", s2);
        _;
    }

    function deposit(uint256 amount_, uint256 seedLockUpPeriod_, uint256 seedActors_, uint256 seedChain_, uint256 time_)
        public
        wrapTime(time_)
    {
        vm.stopPrank();
        // Create a lockUpPeriod that is restricted between 0 and 6. 1,2,4,6 will pass; 0,3,5 will fail
        uint256 lockUpPeriod_ = seedLockUpPeriod_ % 6;

        // Choose the chain
        uint256 id = bound(seedChain_ % 2, 0, 1);
        VaultV2 vaultUsed_ = _chainToVault[id];

        // Select the amount between 0 and 1000
        amount_ = amount_ % 1000; // 1000 is the set max deposit amount

        // Set up actor so it can interact w/the vault - actor gets and approves tokens to the vault
        address actorAddress_ = _actors[seedActors_ % NUM_ACTORS];
        _actorSetUp(actorAddress_, address(vaultUsed_));

        // Make a deposit
        vm.prank(actorAddress_);
        success = vaultUsed_.deposit(amount_, lockUpPeriod_);

        // Log the deposit if it is a success
        if (success) {
            string memory s1 = string.concat("Vault ", uint2str(seedChain_ % 2));
            s1 = string.concat(s1, uint2str(vaultUsed_.getDepositEndtime(vaultUsed_.getMostRecentId())));
            vm.writeLine("test/invariant/handlers/out.txt", s1);
        }
    }

    function withdraw(uint256 time_, uint256 seedActors_, uint256 seedChain_) public wrapTime(time_) {
        vm.stopPrank();

        // Choose the chain
        uint256 id = bound(seedChain_ % 2, 0, 1);
        VaultV2 vaultUsed_ = _chainToVault[id];

        // Set up actor so it can interact w/the vault - actor gets and approves tokens to the vault
        address actorAddress_ = _actors[seedActors_ % NUM_ACTORS];

        // Prepare withdraw
        uint256[] memory depositsToWithdraw_ = new uint256[](1);
        //if (vaultUsed_.getMostRecentId() != 0) {
        depositsToWithdraw_[0] = vaultUsed_.ownersDepositId(actorAddress_, 0);

        // Try to withdraw
        vm.writeLine("test/invariant/handlers/out.txt", "--Withdraw Attempt");
        vm.prank(actorAddress_);
        vaultUsed_.withdraw(depositsToWithdraw_);
        vm.writeLine("test/invariant/handlers/out.txt", "--Withdraw Success");

        //}
    }

    function claimRewards(uint256 time_, uint256 seedChain_, uint256 seedActors_, uint256 seedRewards_)
        public
        wrapTime(time_)
    {
        vm.stopPrank();

        // Choose the chain
        uint256 id = bound(seedChain_ % 2, 0, 1);
        VaultV2 vaultUsed_ = _chainToVault[id];

        // Set up actor so it can interact w/the vault - actor gets and approves tokens to the vault
        address actorAddress_ = _actors[seedActors_ % NUM_ACTORS];

        // Make a claim
        vm.writeLine("test/invariant/handlers/out.txt", "--Claim Attempt");
        vm.prank(actorAddress_);
        vaultUsed_.claimRewards(seedRewards_ % (REWARDS_PER_SECOND * (_time - 52 weeks))); // try to claim between 0 and all the rewards acrued since the start of the run
        vm.writeLine("test/invariant/handlers/out.txt", "--Claim Success");
    }

    function skipBiggerTime(uint256 bigTime_, uint256 time_) public wrapTime(time_) {
        vm.stopPrank();
        bigTime_ = bound(bigTime_, 20 weeks, 200 weeks); // so it's more likely that a deposit expires
        _time = _time + bigTime_;
        string memory s2 = string.concat("Time: ", uint2str(_time));
        vm.writeLine("test/invariant/handlers/out.txt", s2);
    }

    //-----------------------------------------------------------------------
    //------------------------------HELPERS----------------------------------
    //-----------------------------------------------------------------------
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
            return " 0 ";
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
        str = string.concat(string.concat(" ", string(bstr)), " ");
    }

    function _createActors(uint256 userNum) internal returns (address[] memory) {
        address[] memory users = new address[](userNum);

        for (uint256 i = 1; i <= userNum; i++) {
            // This will create a new address using `keccak256(i)` as the private key
            address user = vm.addr(i);
            vm.deal(user, 100 ether);
            users[i - 1] = user;
        }

        return users;
    }
}
