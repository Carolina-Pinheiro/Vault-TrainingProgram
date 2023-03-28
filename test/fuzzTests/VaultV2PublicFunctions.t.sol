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
    uint256 public constant AMOUNT_OF_DEPOSITS_TESTED = 100;

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
    mapping(uint16 => VaultV2) chainsToVault;
    mapping(uint16 => address) chainsToEndpoint;

    uint256 balanceBefore;
    uint256 balanceAfter;
    bool success;
    bytes data;
    uint256 startTime;
    // -------------- Variables
    uint256 time = block.timestamp + 52 weeks;
    uint256 depositId = 1;

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
    event LogChainConnect(uint16, string, uint16);

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
        vault1.addConnectedChains(uint16(2), address(vault2));
        vault2.setTrustedRemoteAddress(1, abi.encodePacked(address(vault1)));
        vault2.addConnectedChains(uint16(1), address(vault1));
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

    function testFuzz_SingleDeposit_SkipCI(uint256 amount_, uint256 seedLockUpPeriod_) public {
        vm.startPrank(lucy);
        uint256 nextId = 0;
        uint256 balance = _userGetLPTokens(lucy);

        //vm.assume(amount_ > 0);
        amount_ = bound(amount_, 1, MAX_DEPOSIT_AMOUNT);
        uint256 lockUpPeriod_ = seedLockUpPeriod_ % 6; // array com vários lockUpPeriod  [6,1,2,4,5] -> fazer o resto da divisão e limitar o resto da divisão

        //Approve  tokens to the vault
        _approveTokens(balance, address(vault1));

        // Pass some time so block.timestamp is more realistical
        time = block.timestamp + 52 weeks;
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

    function testFuzz_SingleWithdraw_SkipCI(uint256 timeAfterDeposit_, uint256 seedLockUpPeriod_, uint256 depositAmount_)
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

    function testFuzz_SingleClaimRewards_SkipCI(uint256 timeAfterDeposit_, uint256 seedLockUpPeriod_, uint256 depositAmount_)
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

    function testFuzz_Deposit_SkipCI(
        uint256 numberOfDeposits_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedDepositsAmount_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedLockUpPeriodList_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedTimeBetweenDeposits_,
        address[AMOUNT_OF_DEPOSITS_TESTED] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Variables
        time = block.timestamp + 52 weeks;
        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, AMOUNT_OF_DEPOSITS_TESTED); // bond number of deposits
        (
            uint256[] memory depositsAmount_,
            uint256[] memory lockUpPeriodList_,
            uint256[] memory timeBetweenDeposits_,
            address[] memory Addresses_
        ) = _createDepositFuzzVariablesWithSeed(
            numberOfDeposits_,
            seedDepositsAmount_,
            seedLockUpPeriodList_,
            seedTimeBetweenDeposits_,
            actorsAddresses_,
            address(vault1),
            seedAmountOfRepeatedAddresses % 99 + 1
        );
        vm.warp(time);

        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            // -------------- Make the deposit
            _makeADepositWithExpects(lockUpPeriodList_[i_], depositsAmount_[i_], vault1, Addresses_[i_]);

            // Wrap a random amount of time
            time = time + timeBetweenDeposits_[i_];
            vm.warp(time);
            vm.stopPrank();
        }
    }

    function testFuzz_Claim_SkipCI(
        uint256 numberOfDeposits_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedDepositsAmount_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedLockUpPeriodList_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedTimeBetweenDeposits_,
        address[AMOUNT_OF_DEPOSITS_TESTED] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Variables
        time = block.timestamp + 52 weeks;

        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, AMOUNT_OF_DEPOSITS_TESTED / 2); // bond number of deposits
        (
            uint256[] memory depositsAmount_,
            uint256[] memory lockUpPeriodList_,
            uint256[] memory timeBetweenDeposits_,
            address[] memory Addresses_
        ) = _createDepositFuzzVariablesWithSeed(
            numberOfDeposits_,
            seedDepositsAmount_,
            seedLockUpPeriodList_,
            seedTimeBetweenDeposits_,
            actorsAddresses_,
            address(vault1),
            seedAmountOfRepeatedAddresses % 99 + 1
        );
        vm.warp(time);

        // Make deposits
        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            // -------------- Make the deposit
            _makeADepositWithExpects(lockUpPeriodList_[i_], depositsAmount_[i_], vault1, Addresses_[i_]);
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

    function testFuzz_Withdraw_SkipCI(
        uint256 numberOfDeposits_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedDepositsAmount_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedLockUpPeriodList_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedTimeBetweenDeposits_,
        address[AMOUNT_OF_DEPOSITS_TESTED] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Variables
        time = block.timestamp + 52 weeks;

        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, AMOUNT_OF_DEPOSITS_TESTED / 2); // bond number of deposits
        (
            uint256[] memory depositsAmount_,
            uint256[] memory lockUpPeriodList_,
            uint256[] memory timeBetweenDeposits_,
            address[] memory Addresses_
        ) = _createDepositFuzzVariablesWithSeed(
            numberOfDeposits_,
            seedDepositsAmount_,
            seedLockUpPeriodList_,
            seedTimeBetweenDeposits_,
            actorsAddresses_,
            address(vault1),
            seedAmountOfRepeatedAddresses % 99 + 1
        );
        vm.warp(time);

        // Make deposits
        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            vm.startPrank(Addresses_[i_]);
            _makeADepositWithExpects(lockUpPeriodList_[i_], depositsAmount_[i_], vault1, Addresses_[i_]);

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
                } else {
                    // if only some have expired, there should be deposits to withdraw and the actor's balance will increase
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
            } else {
                // if the actor doesn't have any deposit, it will revert
                vm.prank(actorsAddresses_[i_]);
                vm.expectRevert(NoLPTokensToWithdrawError.selector);
                vault1.withdraw(depositsToWithdraw);
            }
            notExpiredCount = 0;
        }
    }

    // -------------------------------------------------
    // Test  different chains
    // -------------------------------------------------
    function testFuzz_Chains_SkipCI(
        uint256 numberOfChains_,
        uint256 numberOfDeposits_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedDepositsAmount_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedLockUpPeriodList_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedTimeBetweenDeposits_,
        address[AMOUNT_OF_DEPOSITS_TESTED] memory actorsAddresses_,
        uint256 seedAmountOfRepeatedAddresses
    ) public {
        // -------------- Create and connect chains and contracts
        numberOfChains_ = bound(numberOfChains_, 2, 4);
        uint16[] memory chainsToConnect_ = new uint16[](numberOfChains_);
        for (uint16 i_ = 0; i_ < numberOfChains_; i_++) {
            LZEndpointMock lzEndpoint_ = new LZEndpointMock(i_+10); // +10 to not overlap chains
            VaultV2 newVault_ = new VaultV2(LPToken, address(lzEndpoint_));
            chainsToConnect_[i_] = uint16(i_ + 10);
            chainsToVault[chainsToConnect_[i_]] = newVault_;
            chainsToEndpoint[chainsToConnect_[i_]] = address(lzEndpoint_);
            vm.deal(address(chainsToVault[chainsToConnect_[i_]]), 100 ether);
            vm.label(address(newVault_), string.concat("Vault ", uint2str(i_)));
        }

        for (uint16 i_ = 0; i_ < chainsToConnect_.length; i_++) {
            for (uint16 j_ = 0; j_ < chainsToConnect_.length; j_++) {
                _connectChains(chainsToConnect_[i_], chainsToConnect_[j_]);
            }
            //chainsToVault[chainsToConnect_[i_]].showConnectedChains();
        }

        // -------------- Fuzz test set up
        numberOfDeposits_ = bound(numberOfDeposits_, 1, 50); // bond number of deposits
        (
            uint256[] memory depositsAmount_,
            uint256[] memory lockUpPeriodList_,
            uint256[] memory timeBetweenDeposits_,
            address[] memory Addresses_
        ) = _createDepositFuzzVariablesWithSeed(
            numberOfDeposits_,
            seedDepositsAmount_,
            seedLockUpPeriodList_,
            seedTimeBetweenDeposits_,
            actorsAddresses_,
            address(vault1),
            seedAmountOfRepeatedAddresses % 99 + 1
        );
        uint16[] memory vaultAddresses_ = new uint16[](numberOfDeposits_);
        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            vaultAddresses_[i_] = uint16(seedTimeBetweenDeposits_[i_] % numberOfChains_); // use the same seed just to simplify
        }
        vm.warp(time);

        uint256[] memory successfullDeposits_ = new uint256[](numberOfChains_);
        startTime = block.timestamp;
        // --------------  Make various deposits
        for (uint256 i_ = 0; i_ < depositsAmount_.length; i_++) {
            _actorSetUp(Addresses_[i_], address(chainsToVault[chainsToConnect_[vaultAddresses_[i_]]]));
            vm.startPrank(Addresses_[i_]);
            emit LogUint(i_);
            success = _makeADepositWithExpects(
                lockUpPeriodList_[i_],
                depositsAmount_[i_],
                chainsToVault[chainsToConnect_[vaultAddresses_[i_]]],
                Addresses_[i_]
            );

            if (success) successfullDeposits_[vaultAddresses_[i_]]++;

            // Wrap a random amount of time
            time = time + timeBetweenDeposits_[i_];
            vm.warp(time);
            vm.stopPrank();
        }

        // Check if total deposits is the same as the deposit id
        _assertNumberOfDeposits(successfullDeposits_, numberOfChains_);

        // Check if the claimed rewards since the beggining are distributed across all chains
        //_assertRewardsDistributed(actorsAddresses_,numberOfChains_, chainsToConnect_ );
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

    // -------------------------------------------------
    // Asserts
    function _assertNumberOfDeposits(uint256[] memory successfullDeposits_, uint256 numberOfChains_) internal {
        uint256 totalDeposits_;
        for (uint16 i_ = 0; i_ < numberOfChains_; i_++) {
            totalDeposits_ = totalDeposits_ + successfullDeposits_[i_];
        }
        assertEq(depositId - 1, totalDeposits_);
    }

    function _assertRewardsDistributed(
        address[AMOUNT_OF_DEPOSITS_TESTED] memory actorsAddresses_,
        uint256 numberOfChains_,
        uint16[] memory chainsToConnect_
    ) internal {
        uint256 totalAwardsDistributedActual = 0;
        for (uint256 i_ = 0; i_ < actorsAddresses_.length; i_++) {
            for (uint16 j = 0; j < numberOfChains_; j++) {
                vm.prank(actorsAddresses_[i_]);
                try chainsToVault[chainsToConnect_[j]].claimRewards(0) returns (uint256 rewards) {
                    totalAwardsDistributedActual = totalAwardsDistributedActual + rewards;
                } catch (bytes memory reason) { }
                //rewards = 0;
                //totalAwardsDistributedActual = totalAwardsDistributedActual + chainsToVault[chainsToConnect_[j]].claimRewards(0);
            }
        }
        assert(_similarNumbers(REWARDS_PER_SECOND * (block.timestamp - startTime), totalAwardsDistributedActual, 5));
    }

    // -------------------------------------------------
    // Other helpers
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

        (success,) = router.call{ value: UNISWAP_INITIAL_WETH_RESERVE }(
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
        (, data) = factory.call(abi.encodeWithSignature("getPair(address,address)", address(poolToken), address(weth)));
        pair = abi.decode(data, (address));
        vm.label(pair, "Pair-LPTokens");

        return pair;
    }

    function _approveTokens(uint256 amount_, address to_) internal {
        (success,) = LPToken.call(abi.encodeWithSignature("approve(address,uint256)", to_, amount_));
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
        emit LogUintPair(number1_, number2_);
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

    function _connectChains(uint16 chain1_, uint16 chain2_) private {
        if (chain1_ != chain2_ && chain1_ != 0 && chain2_ != 0) {
            // New vault/chain connects to the others
            chainsToVault[chain1_].setTrustedRemoteAddress(chain2_, abi.encodePacked(address(chainsToVault[chain2_])));
            chainsToVault[chain1_].addConnectedChains(chain2_, address(chainsToVault[chain2_]));
            LZEndpointMock(chainsToEndpoint[chain1_]).setDestLzEndpoint(
                address(chainsToVault[chain2_]), address(chainsToEndpoint[chain2_])
            );
            emit LogChainConnect(chain1_, "->", chain2_);
        }
    }

    function _createDepositFuzzVariablesWithSeed(
        uint256 numberOfDeposits_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedDepositsAmount_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedLockUpPeriodList_,
        uint256[AMOUNT_OF_DEPOSITS_TESTED] memory seedTimeBetweenDeposits_,
        address[AMOUNT_OF_DEPOSITS_TESTED] memory actorsAddresses_,
        address vault,
        uint256 amountOfRepeatedAddresses
    ) private returns (uint256[] memory, uint256[] memory, uint256[] memory, address[] memory) {
        uint256[] memory depositsAmount_ = new uint256[](numberOfDeposits_);
        uint256[] memory lockUpPeriodList_ = new uint256[](numberOfDeposits_);
        uint256[] memory timeBetweenDeposits_ = new uint256[](numberOfDeposits_);
        address[] memory Addresses_ = new address[](numberOfDeposits_);

        for (uint256 i_ = 0; i_ < numberOfDeposits_; i_++) {
            depositsAmount_[i_] = seedDepositsAmount_[i_] % MAX_DEPOSIT_AMOUNT;
            lockUpPeriodList_[i_] = seedLockUpPeriodList_[i_] % 6;
            timeBetweenDeposits_[i_] = seedTimeBetweenDeposits_[i_] % (26 weeks);
            Addresses_[i_] = actorsAddresses_[i_ % amountOfRepeatedAddresses];
            if (Addresses_[i_] == address(0x0)) {
                // so the zero address is not used
                Addresses_[i_] = Addresses_[i_ - 1];
            }
            _actorSetUp(Addresses_[i_], address(vault));
        }

        return (depositsAmount_, lockUpPeriodList_, timeBetweenDeposits_, Addresses_);
    }

    function _makeADepositWithExpects(uint256 lockUpPeriod_, uint256 amount_, VaultV2 vault, address sender_)
        private
        returns (bool)
    {
        success = false;
        if (lockUpPeriod_ == 6 || lockUpPeriod_ == 1 || lockUpPeriod_ == 2 || lockUpPeriod_ == 4) {
            // -------------- Assertions
            if (amount_ != 0) {
                vm.expectEmit(true, true, true, true);
                emit LogNewDeposit(
                    sender_, depositId, amount_, amount_ * _getRewardsMultiplier(lockUpPeriod_), lockUpPeriod_
                );
                actorsWithDeposits[sender_].push(depositId);
                depositId++;
                success = true;
            } else {
                vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
            }
            vault.deposit(amount_, lockUpPeriod_);
        } else {
            // If lock up period is wrong
            // -------------- Assertions
            if (amount_ != 0) {
                vm.expectRevert(WrongLockUpPeriodError.selector);
            } else {
                vm.expectRevert(NotEnoughAmountOfTokensDepositedError.selector);
            }
            vault.deposit(amount_, lockUpPeriod_);
        }
        return (success);
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
