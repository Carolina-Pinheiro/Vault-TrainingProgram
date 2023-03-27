// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { Test } from "@forge-std/Test.sol";
import { VaultV2 } from "src/src-default/VaultV2.sol";
import { Token } from "src/src-default/Token.sol";
import { LZEndpointMock } from "@layerZeroOmnichain/mocks/LZEndpointMock.sol";
import { WETH9 } from "test/WETH9.sol";
import { PoolToken } from "test/PoolToken.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";

contract VaultFuzzTestPublic is Test {
    VaultV2 vault1;
    VaultV2 vault2;
    address public ownerVault = vm.addr(11);
    address public lucy = vm.addr(12);
    address public phoebe = vm.addr(13);
    address public julien = vm.addr(14);
    address public dacus = vm.addr(15);

    //
    // Constants
    //
    uint256 public constant UNISWAP_INITIAL_TOKEN_RESERVE = 1_000_000_000 ether;
    uint256 public constant UNISWAP_INITIAL_WETH_RESERVE = 1_000_000_000 ether;

    //
    // Uniswap V2 contracts
    //
    address public factory;
    address public router;
    address public pair;

    //
    // Tokens
    //
    Token public rewardToken;
    WETH9 public weth;
    PoolToken public poolToken;
    address LPToken;
    //
    // Pool
    //
    address public pool;

    LZEndpointMock lzEndpoint1; // chainId=1
    LZEndpointMock lzEndpoint2; // chainId=2
    uint256 REWARDS_PER_SECOND = 317;
    uint256 MAX_DEPOSIT_AMOUNT = 1000;
    uint256 MINIMUM_TIME_TO_CLAIM = 600; // 10 minutes

    mapping(address => uint256) actorsWithRewardsClaimed;
    mapping(address => uint256[]) actorsWithDeposits;

    uint256 balanceBefore;
    uint256 balanceAfter;
    bool success;
    bytes data;

    //-----------------------------------------------------------------------
    //------------------------------LOGS-------------------------------------
    //-----------------------------------------------------------------------
    event LogUint(uint256);
    event LogRewardsTokenMinted(address, uint256);
    event LogNode(ILinkedList.Node);
    event LogDepositExpired(address, uint256); // Owner and deposit id
    event LogWithdrawHasNotExpired(uint256);
    event LogUintArray(uint256[]);
    event LogWithdraw(address, uint256);
    event LogAddress(address);
    event LogUintPair(uint256, uint256);
    event LogLockUpTimeAfterDepositAmount(uint256, uint256, uint256);
    event LogString(string, uint256);
    event LogNewDeposit(address, uint256, uint256, uint256, uint256);

    //-----------------------------------------------------------------------
    //------------------------------ERRORS-----------------------------------
    //-----------------------------------------------------------------------
    error NoRewardsToClaimError();
    error TransferOfLPTokensWasNotPossibleError();
    error NotEnoughAmountOfTokensDepositedError();
    error WrongLockUpPeriodError();
    error NoLPTokensToWithdrawError();

    function setUp() external {
        // Set-up the vault contract
        vm.label(ownerVault, "OwnerVault");
        vm.label(lucy, "Lucy");
        vm.label(phoebe, "Phoebe");
        vm.label(julien, "Julien");
        vm.label(dacus, "Dacus");
        lzEndpoint1 = new LZEndpointMock(1); // chainId=1
        lzEndpoint2 = new LZEndpointMock(2); // chainId=2
        rewardToken = new Token(address(lzEndpoint1), address(vault1));
        LPToken = _setUpUniswap();
        vm.startPrank(ownerVault);
        vault1 = new VaultV2(LPToken, address(lzEndpoint1));
        vault2 = new VaultV2(LPToken, address(lzEndpoint2));
        vault1.setTrustedRemoteAddress(2, abi.encodePacked(address(vault2)));
        vault1.addConnectedChains(uint16(2));
        vault2.setTrustedRemoteAddress(1, abi.encodePacked(address(vault1)));
        vault2.addConnectedChains(uint16(1));
        lzEndpoint1.setDestLzEndpoint(address(vault2), address(lzEndpoint2));
        lzEndpoint2.setDestLzEndpoint(address(vault1), address(lzEndpoint1));
        vm.stopPrank();
        vm.label(address(vault1), "Vault-Chain1");
        vm.label(address(vault2), "Vault-Chain2");
        vm.deal(ownerVault, 10_000 ether);
        vm.deal(address(vault1), 10_000 ether);
        vm.deal(address(vault2), 10_000 ether);
    }

    // Needed so the test contract itself can receive ether
    // when withdrawing
    receive() external payable { }

    // -------------------------------------------------
    // Test single interactions
    // -------------------------------------------------

    function testFuzz_SingleDeposit(uint256 amount_, uint256 seedLockUpPeriod_) public {
        vm.startPrank(lucy);
        uint256 nextId = 0;
        uint256 balance = _userGetLPTokens(lucy);

        //vm.assume(amount_ > 0);
        amount_ = bound(amount_, 1, MAX_DEPOSIT_AMOUNT);
        uint256 lockUpPeriod_ = seedLockUpPeriod_ % 6; // array com vários lockUpPeriod  [6,1,2,4,5] -> fazer o resto da divisão e limitar o resto da divisão

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));

        // Pass some time so block.timestamp is more realistical
        uint256 time = block.timestamp + 52 weeks;
        vm.warp(time);

        if (lockUpPeriod_ == 6 || lockUpPeriod_ == 1 || lockUpPeriod_ == 2 || lockUpPeriod_ == 4) {
            // User makes a deposit in vault 1
            ILinkedList.Node memory node = ILinkedList.Node({
                nextId: nextId,
                endTime: _calculateEndTime(lockUpPeriod_, time),
                share: amount_ * _getRewardsMultiplier(lockUpPeriod_),
                depositedLPTokens: amount_,
                currentTotalWeight: vault1.getTotalWeightLocked(),
                owner: address(lucy)
            });
            vm.expectEmit(true, true, true, true);
            emit LogNode(node);
            vault1.deposit(amount_, lockUpPeriod_);
        } else {
            vm.expectRevert(WrongLockUpPeriodError.selector);
            vault1.deposit(amount_, lockUpPeriod_);
        }
        vm.stopPrank();
    }

    function testFuzz_SingleWithdraw(uint256 timeAfterDeposit_, uint256 seedLockUpPeriod_, uint256 depositAmount_)
        public
    {
        // -------------- Variables
        timeAfterDeposit_ = bound(timeAfterDeposit_, MINIMUM_TIME_TO_CLAIM, 500 weeks);

        vm.assume(seedLockUpPeriod_ > 0);
        uint256 lockUpPeriod_ = seedLockUpPeriod_ % 6;

        depositAmount_ = bound(depositAmount_, 1, MAX_DEPOSIT_AMOUNT);

        bool reverted = false;

        // -------------- Give and approve tokens to the user
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));
        // Pass some time so block.timestamp is more realistic
        vm.warp(block.timestamp + 52 weeks);

        // -------------- Make a deposit
        if (lockUpPeriod_ == 6 || lockUpPeriod_ == 1 || lockUpPeriod_ == 2 || lockUpPeriod_ == 4) {
            // User makes a deposit in vault 1
            ILinkedList.Node memory node = ILinkedList.Node({
                nextId: 0,
                endTime: _calculateEndTime(lockUpPeriod_, block.timestamp + 52 weeks),
                share: depositAmount_ * _getRewardsMultiplier(lockUpPeriod_),
                depositedLPTokens: depositAmount_,
                currentTotalWeight: vault1.getTotalWeightLocked(),
                owner: address(lucy)
            });
            vault1.deposit(depositAmount_, lockUpPeriod_);
        } else {
            reverted = true;
        }
        vm.stopPrank();

        // -------------- Try to withdraw a deposit a random amount of time after
        vm.warp(block.timestamp + timeAfterDeposit_);
        uint256 lockUpTime_;
        uint256[] memory depositsToWithdraw = new uint256[](1);
        if (!reverted) {
            // deposit was successful
            depositsToWithdraw[0] = vault1.ownersDepositId(lucy, 0);
            // -------------- Assert
            //Note: making this with a mapping is more concise
            if (lockUpPeriod_ == 6) {
                lockUpTime_ = 26 weeks;
            } else if (lockUpPeriod_ == 1) {
                lockUpTime_ = 52 weeks;
            } else if (lockUpPeriod_ == 2) {
                lockUpTime_ = 104 weeks;
            } else if (lockUpPeriod_ == 4) {
                lockUpTime_ = 208 weeks;
            }

            if (timeAfterDeposit_ > lockUpTime_) {
                // -------------- Enough time has passed, expect LP transfer to the user
                vm.expectEmit(true, true, true, true);
                emit LogWithdraw(lucy, depositAmount_);
                vm.prank(lucy);
                vault1.withdraw(depositsToWithdraw);
            } else {
                // -------------- Not enough time has passed, expect revert
                vm.expectEmit(true, true, true, true);
                emit LogWithdrawHasNotExpired(depositsToWithdraw[0]);
                vm.expectRevert(IVault.NoLPTokensToWithdrawError.selector);
                vm.prank(lucy);
                vault1.withdraw(depositsToWithdraw);
            }
        }
    }

    function testFuzz_SingleClaimRewards(uint256 timeAfterDeposit_, uint256 seedLockUpPeriod_, uint256 depositAmount_)
        public
    {
        // -------------- Variables
        timeAfterDeposit_ = bound(timeAfterDeposit_, MINIMUM_TIME_TO_CLAIM, 300 weeks); // a little bit more than 4 years as a upper bound

        vm.assume(seedLockUpPeriod_ > 0);
        uint256 lockUpPeriod_ = seedLockUpPeriod_ % 6;

        depositAmount_ = bound(depositAmount_, 1, MAX_DEPOSIT_AMOUNT);

        bool reverted = false;
        // -------------- Give and approve tokens to the user
        vm.startPrank(lucy);
        uint256 balance = _userGetLPTokens(lucy);
        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));
        // Pass some time so block.timestamp is more realistic
        vm.warp(block.timestamp + 52 weeks);

        // -------------- Make a deposit
        if (lockUpPeriod_ == 6 || lockUpPeriod_ == 1 || lockUpPeriod_ == 2 || lockUpPeriod_ == 4) {
            // User makes a deposit in vault 1
            ILinkedList.Node memory node = ILinkedList.Node({
                nextId: 0,
                endTime: _calculateEndTime(lockUpPeriod_, block.timestamp + 52 weeks),
                share: depositAmount_ * _getRewardsMultiplier(lockUpPeriod_),
                depositedLPTokens: depositAmount_,
                currentTotalWeight: vault1.getTotalWeightLocked(),
                owner: address(lucy)
            });
            vault1.deposit(depositAmount_, lockUpPeriod_);
        } else {
            reverted = true;
        }
        vm.stopPrank();

        // -------------- Try to claim it a random amount of time after
        vm.warp(block.timestamp + timeAfterDeposit_);
        vm.prank(lucy);
        if (!reverted) {
            uint256 claimedRewards_ = vault1.claimRewards(0); // try to claim all the rewards

            // -------------- Assert
            //Note: making this with a mapping somehow may be more concise
            if (lockUpPeriod_ == 6 && timeAfterDeposit_ > 26 weeks) {
                timeAfterDeposit_ = 26 weeks;
            } else if (lockUpPeriod_ == 1 && timeAfterDeposit_ > 52 weeks) {
                timeAfterDeposit_ = 52 weeks;
            } else if (lockUpPeriod_ == 2 && timeAfterDeposit_ > 104 weeks) {
                timeAfterDeposit_ = 104 weeks;
            } else if (lockUpPeriod_ == 4 && timeAfterDeposit_ > 208 weeks) {
                timeAfterDeposit_ = 208 weeks;
            }
            emit LogLockUpTimeAfterDepositAmount(lockUpPeriod_, timeAfterDeposit_, depositAmount_);
            uint256 expectedRewards_ = (REWARDS_PER_SECOND) * timeAfterDeposit_;
            emit LogUint(expectedRewards_);
            assertEq(_similarNumbers(claimedRewards_, expectedRewards_, 5), true);
        }
    }

    // -------------------------------------------------
    // Test various interactions
    // -------------------------------------------------

    function testFuzz_Deposit(
        uint256 numberOfDeposits_,
        uint256[100] memory seedDepositsAmount_,
        uint256[100] memory seedLockUpPeriodList_,
        uint256[100] memory seedTimeBetweenDeposits_,
        address[100] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Variables
        uint256 time = block.timestamp + 52 weeks;
        uint256 depositId = 1;

        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, 100); // bond number of deposits
        uint256[] memory depositsAmount_ = new uint256[](numberOfDeposits_);
        uint256[] memory lockUpPeriodList_ = new uint256[](numberOfDeposits_);
        uint256[] memory timeBetweenDeposits_ = new uint256[](numberOfDeposits_);
        address[] memory Addresses_ = new address[](numberOfDeposits_);
        uint256 actorId_;
        uint256 amountOfRepeatedAddresses = seedAmountOfRepeatedAddresses % 99 + 1; // +1 so it never is zero, bound could be used as well

        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            depositsAmount_[i_] = seedDepositsAmount_[i_] % MAX_DEPOSIT_AMOUNT;
            lockUpPeriodList_[i_] = seedLockUpPeriodList_[i_] % 6;
            timeBetweenDeposits_[i_] = seedTimeBetweenDeposits_[i_] % (26 weeks);
            actorId_ = i_ % amountOfRepeatedAddresses;
            Addresses_[i_] = actorsAddresses_[actorId_];
            if (Addresses_[i_] == address(0x0)) {
                // so the zero address is not used
                Addresses_[i_] = Addresses_[i_ - 1];
            }
            _actorSetUp(Addresses_[i_], address(vault1));
        }
        vm.warp(time);

        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            // -------------- Make the deposit
            if (
                lockUpPeriodList_[i_] == 6 || lockUpPeriodList_[i_] == 1 || lockUpPeriodList_[i_] == 2
                    || lockUpPeriodList_[i_] == 4
            ) {
                // -------------- Assertions
                if (depositsAmount_[i_] != 0) {
                    vm.expectEmit(true, true, true, true);
                    emit LogNewDeposit(
                        Addresses_[i_],
                        depositId,
                        depositsAmount_[i_],
                        depositsAmount_[i_] * _getRewardsMultiplier(lockUpPeriodList_[i_]),
                        lockUpPeriodList_[i_]
                    );
                    depositId++;
                } else {
                    vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
                }
                vault1.deposit(depositsAmount_[i_], lockUpPeriodList_[i_]);
            } else {
                // If lock up period is wrong
                // -------------- Assertions
                if (depositsAmount_[i_] != 0) {
                    vm.expectRevert(WrongLockUpPeriodError.selector);
                } else {
                    vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
                }
                vault1.deposit(depositsAmount_[i_], lockUpPeriodList_[i_]);
            }

            // Wrap a random amount of time
            time = time + timeBetweenDeposits_[i_];
            vm.warp(time);
            vm.stopPrank();
        }
    }

    function testFuzz_Claim(
        uint256 numberOfDeposits_,
        uint256[100] memory seedDepositsAmount_,
        uint256[100] memory seedLockUpPeriodList_,
        uint256[100] memory seedTimeBetweenDeposits_,
        address[100] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Variables
        uint256 time = block.timestamp + 52 weeks;
        uint256 depositId = 1;

        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, 50); // bond number of deposits
        uint256[] memory depositsAmount_ = new uint256[](numberOfDeposits_);
        uint256[] memory lockUpPeriodList_ = new uint256[](numberOfDeposits_);
        uint256[] memory timeBetweenDeposits_ = new uint256[](numberOfDeposits_);
        address[] memory Addresses_ = new address[](numberOfDeposits_);
        uint256 actorId_;
        uint256 amountOfRepeatedAddresses = seedAmountOfRepeatedAddresses % 49 + 1; // +1 so it never is zero, bound could be used as well

        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            depositsAmount_[i_] = seedDepositsAmount_[i_] % MAX_DEPOSIT_AMOUNT;
            lockUpPeriodList_[i_] = seedLockUpPeriodList_[i_] % 6;
            timeBetweenDeposits_[i_] = seedTimeBetweenDeposits_[i_] % (26 weeks);
            actorId_ = i_ % amountOfRepeatedAddresses;
            Addresses_[i_] = actorsAddresses_[actorId_];
            if (Addresses_[i_] == address(0x0)) {
                // so the zero address is not used
                Addresses_[i_] = Addresses_[i_ - 1];
            }
            _actorSetUp(Addresses_[i_], address(vault1));
            //actorsWithRewardsClaimed[Addresses_[i_]] = 0; // reset mapping
        }
        vm.warp(time);

        // Make deposits
        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            // -------------- Make the deposit
            if (
                lockUpPeriodList_[i_] == 6 || lockUpPeriodList_[i_] == 1 || lockUpPeriodList_[i_] == 2
                    || lockUpPeriodList_[i_] == 4
            ) {
                // -------------- Assertions
                if (depositsAmount_[i_] != 0) {
                    vm.expectEmit(true, true, true, true);
                    emit LogNewDeposit(
                        Addresses_[i_],
                        depositId,
                        depositsAmount_[i_],
                        depositsAmount_[i_] * _getRewardsMultiplier(lockUpPeriodList_[i_]),
                        lockUpPeriodList_[i_]
                    );
                    depositId++;
                } else {
                    vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
                }
                vault1.deposit(depositsAmount_[i_], lockUpPeriodList_[i_]);
            } else {
                // If lock up period is wrong
                // -------------- Assertions
                if (depositsAmount_[i_] != 0) {
                    vm.expectRevert(WrongLockUpPeriodError.selector);
                } else {
                    vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
                }
                vault1.deposit(depositsAmount_[i_], lockUpPeriodList_[i_]);
            }

            // Wrap a random amount of time
            time = time + timeBetweenDeposits_[i_];
            vm.warp(time);
            vm.stopPrank();
        }

        // Try to claim
        vm.warp(time + 2 weeks); // so every valid deposit has rewards acrued
        uint256 rewardsClaimed;
        // Try to claim rewards from all valid deposits
        for (uint256 i_ = 0; i_ < Addresses_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            if (
                (
                    lockUpPeriodList_[i_] == 6 || lockUpPeriodList_[i_] == 1 || lockUpPeriodList_[i_] == 2
                        || lockUpPeriodList_[i_] == 4
                ) && depositsAmount_[i_] > 0 && (actorsWithRewardsClaimed[Addresses_[i_]] == 0)
            ) {
                // there was a valid lock up period, valid deposit and rewards have not been claimed
                rewardsClaimed = vault1.claimRewards(0);
                assertGt(rewardsClaimed, 0);
                actorsWithRewardsClaimed[Addresses_[i_]] = 1;
            }
            vm.stopPrank();
        }

        // Try to calim rewards from all non-valid deposits (deposits had wrong lock up period, deposit amount or rewards have already been acrued)
        // all claim rewards attempt should revert
        for (uint256 i_ = 0; i_ < Addresses_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            vm.expectRevert(NoRewardsToClaimError.selector);
            vault1.claimRewards(0);
            vm.stopPrank();
        }
    }

    function testFuzz_Withdraw(
        uint256 numberOfDeposits_,
        uint256[100] memory seedDepositsAmount_,
        uint256[100] memory seedLockUpPeriodList_,
        uint256[100] memory seedTimeBetweenDeposits_,
        address[100] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Variables
        uint256 time = block.timestamp + 52 weeks;
        uint256 depositId = 1;

        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, 50); // bond number of deposits
        uint256[] memory depositsAmount_ = new uint256[](numberOfDeposits_);
        uint256[] memory lockUpPeriodList_ = new uint256[](numberOfDeposits_);
        uint256[] memory timeBetweenDeposits_ = new uint256[](numberOfDeposits_);
        address[] memory Addresses_ = new address[](numberOfDeposits_);
        uint256 actorId_;
        uint256 amountOfRepeatedAddresses = seedAmountOfRepeatedAddresses % 49 + 1; // +1 so it never is zero, bound could be used as well

        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            depositsAmount_[i_] = seedDepositsAmount_[i_] % MAX_DEPOSIT_AMOUNT;
            lockUpPeriodList_[i_] = seedLockUpPeriodList_[i_] % 6;
            timeBetweenDeposits_[i_] = seedTimeBetweenDeposits_[i_] % (26 weeks);
            actorId_ = i_ % amountOfRepeatedAddresses;
            Addresses_[i_] = actorsAddresses_[actorId_];
            if (Addresses_[i_] == address(0x0)) {
                // so the zero address is not used
                Addresses_[i_] = Addresses_[i_ - 1];
            }
            _actorSetUp(Addresses_[i_], address(vault1));
            //actorsWithRewardsClaimed[Addresses_[i_]] = 0; // reset mapping
        }
        vm.warp(time);

        // Make deposits
        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            // -------------- Make the deposit
            if (
                lockUpPeriodList_[i_] == 6 || lockUpPeriodList_[i_] == 1 || lockUpPeriodList_[i_] == 2
                    || lockUpPeriodList_[i_] == 4
            ) {
                // -------------- Assertions
                if (depositsAmount_[i_] != 0) {
                    vm.expectEmit(true, true, true, true);
                    emit LogNewDeposit(
                        Addresses_[i_],
                        depositId,
                        depositsAmount_[i_],
                        depositsAmount_[i_] * _getRewardsMultiplier(lockUpPeriodList_[i_]),
                        lockUpPeriodList_[i_]
                    );
                    actorsWithDeposits[Addresses_[i_]].push(depositId);
                    depositId++;
                } else {
                    vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
                }
                vault1.deposit(depositsAmount_[i_], lockUpPeriodList_[i_]);
            } else {
                // If lock up period is wrong
                // -------------- Assertions
                if (depositsAmount_[i_] != 0) {
                    vm.expectRevert(WrongLockUpPeriodError.selector);
                } else {
                    vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
                }
                vault1.deposit(depositsAmount_[i_], lockUpPeriodList_[i_]);
            }

            // Wrap a random amount of time
            time = time + timeBetweenDeposits_[i_];
            vm.warp(time);
            vm.stopPrank();
        }

        vm.warp(time + 100 weeks); // so some deposits have expired
        uint256[] memory depositsToWithdraw;
        uint256 notExpiredCount;
        // Iterate through actors list
        for (uint256 i_ = 0; i_ < actorsAddresses_.length; i_++) {
            // get deposits ids for the specific actor
            depositsToWithdraw = actorsWithDeposits[actorsAddresses_[i_]];

            // check if there are deposits to withdraw
            if (depositsToWithdraw.length != 0) {
                // Check if some have expired or not
                for (uint256 j_ = 0; j_ < depositsToWithdraw.length; j_++) {
                    if (vault1.getDepositEndtime(depositsToWithdraw[j_]) > block.timestamp) {
                        // deposit has not expired
                        vm.expectEmit(true, true, true, true);
                        emit LogWithdrawHasNotExpired(depositsToWithdraw[j_]);
                        notExpiredCount++;
                    }
                }

                // if all the deposits have not expired, it should revert with a NoLPTokensToWithdrawError
                if (notExpiredCount == depositsToWithdraw.length) {
                    vm.prank(actorsAddresses_[i_]);
                    vm.expectRevert(NoLPTokensToWithdrawError.selector);
                    vault1.withdraw(depositsToWithdraw);
                } else { // if only some have expired, there should be deposits to withdraw and the actor's balance will increase
                    (success, data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", actorsAddresses_[i_]));
                    require(success);
                    balanceBefore = abi.decode(data, (uint256));

                    vm.prank(actorsAddresses_[i_]);
                    vault1.withdraw(depositsToWithdraw);

                    (success, data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", actorsAddresses_[i_]));
                    require(success);
                    balanceAfter = abi.decode(data, (uint256));

                    assertGt(balanceAfter, balanceBefore);
                    actorsWithDeposits[actorsAddresses_[i_]] = new uint256[](0);
                }
            } else { // if the actor doesn't have any deposit, it will revert
                vm.prank(actorsAddresses_[i_]);
                vm.expectRevert(NoLPTokensToWithdrawError.selector);
                vault1.withdraw(depositsToWithdraw);
            }
            notExpiredCount = 0;
        }
    }
    // -------------------------------------------------
    // Test helper functions

    function test_similarNumber() public {
        bool result = _similarNumbers(201, 202, 5);
        bool expected = true;
        assertEq(result, expected);

        result = _similarNumbers(5, 20, 5);
        expected = false;
        assertEq(result, expected);

        result = _similarNumbers(100_001, 100_011, 5);
        expected = true;
        assertEq(result, expected);

        result = _similarNumbers(20, 21, 5);
        expected = true;
        assertEq(result, expected);

        result = _similarNumbers(106, 100, 5);
        expected = false;
        assertEq(result, expected);

        result = _similarNumbers(5, 6, 5);
        expected = false;
        assertEq(result, expected);
    }
    // -------------------------------------------------
    // HELPER FUNCTIONS
    // ------------------------------------------------------

    function _setUpUniswap() internal returns (address) {
        // Setup token contracts
        weth = new WETH9();
        vm.label(address(weth), "WETH");

        vm.startPrank(lucy);
        poolToken = new PoolToken();

        // Give tokens to all the actors/contracts
        poolToken.mint(address(this), UNISWAP_INITIAL_TOKEN_RESERVE);
        poolToken.mint(phoebe, 1500 ether);
        poolToken.mint(lucy, 1500 ether);
        poolToken.mint(julien, 1500 ether);
        poolToken.mint(dacus, 1500 ether);
        vm.stopPrank();

        // Give ether to all the actors
        vm.deal(phoebe, 10 * 256 ether);
        vm.deal(lucy, 10 * 256 ether);
        vm.deal(julien, 10 * 256 ether);
        vm.deal(dacus, 10 * 256 ether);

        // Setup Uniswap V2 contracts
        factory = deployCode("UniswapV2Factory.sol", abi.encode(address(0)));
        router = deployCode("UniswapV2Router02.sol", abi.encode(address(factory), address(weth)));
        vm.label(factory, "Factory");
        vm.label(router, "Router");

        // Create pair WETH <-> poolToken and add liquidity
        poolToken.approve(router, UNISWAP_INITIAL_TOKEN_RESERVE);

        (bool success,) = router.call{ value: UNISWAP_INITIAL_WETH_RESERVE }(
            abi.encodeWithSignature(
                "addLiquidityETH(address,uint256,uint256,uint256,address,uint256)",
                address(poolToken),
                UNISWAP_INITIAL_TOKEN_RESERVE,
                0,
                0,
                lucy, //deployer
                block.timestamp * 2
            )
        );
        require(success);

        // Get the pair to interact with
        (, bytes memory data) =
            factory.call(abi.encodeWithSignature("getPair(address,address)", address(poolToken), address(weth)));
        pair = abi.decode(data, (address));
        vm.label(pair, "Pair-LPTokens");

        return pair;
    }

    function _approveTokens(uint256 amount_, address to_) internal {
        (bool success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", to_, amount_));
        require(success);
    }

    function _similarNumbers(uint256 number1_, uint256 number2_, uint256 percentageThreshold_)
        internal
        returns (bool)
    {
        uint256 difference_;
        uint256 biggerNumber_;
        if (number2_ > number1_) {
            difference_ = number2_ - number1_;
            biggerNumber_ = number2_;
        } else if (number1_ > number2_) {
            difference_ = number1_ - number2_;
            biggerNumber_ = number1_;
        } else if (number1_ == number2_) {
            return true;
        }

        uint256 percentage_ = (difference_ * 100) / biggerNumber_;
        emit LogUint(percentage_);
        if (percentage_ < percentageThreshold_) {
            // 5 %
            return true;
        } else {
            return false;
        }
    }

    // Function used to give LPTokens to a user, must be preeced with startPrank
    function _userGetLPTokens(address user) internal returns (uint256) {
        uint256 ethAmount = 1000 ether;
        // Wrap the ETH
        weth.deposit{ value: ethAmount }();

        // Use Pool to have LP tokens
        poolToken.approve(address(router), ethAmount);
        weth.approve(address(router), ethAmount);
        (bool success,) = router.call(
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
        bytes memory data;
        (success, data) = LPToken.call(abi.encodeWithSignature("balanceOf(address)", user));
        require(success);
        uint256 balance = abi.decode(data, (uint256));
        assertGt(balance, 0);

        return balance;
    }

    function _getRewardsMultiplier(uint256 lockUpPeriod) internal pure returns (uint256) {
        uint256 rewardsMultiplier;
        if (lockUpPeriod == 6) {
            rewardsMultiplier = 1;
        } else if (lockUpPeriod == 1) {
            rewardsMultiplier = 2;
        } else if (lockUpPeriod == 2) {
            rewardsMultiplier = 4;
        } else if (lockUpPeriod == 4) {
            rewardsMultiplier = 8;
        } else {
            revert WrongLockUpPeriodError();
        }

        return rewardsMultiplier;
    }

    function _calculateEndTime(uint256 lockUpPeriod_, uint256 currentTime_) internal pure returns (uint256 endTime_) {
        uint256 factor_;
        //TODO: implement this better
        if (lockUpPeriod_ == 6) {
            factor_ = 26;
            lockUpPeriod_ = 1;
        } else {
            factor_ = 52;
        }

        endTime_ = lockUpPeriod_ * factor_ * 1 weeks + currentTime_;
        return (endTime_);
    }

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
}
