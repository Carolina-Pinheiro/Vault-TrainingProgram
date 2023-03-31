// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

interface IVault is ILinkedList {
    //-----------------------------------------------------------------------
    //------------------------------LOGS-------------------------------------
    //-----------------------------------------------------------------------
    event LogUint(uint256);
    event LogTotalWeightUpdate(uint256, uint256); // old new
    event LogRewardsTokenMinted(address, uint256);
    event LogNode(Node);
    event LogDepositExpired(address, uint256); // Owner and deposit id
    event LogWithdrawHasNotExpired(uint256);
    event LogUintArray(uint256[]);
    event LogWithdraw(address, uint256);
    event LogRewardsAcrued(uint256);
    event LogUintPair(uint256, uint256);
    event LogNewDeposit(address, uint256, uint256, uint256, uint256);
    event LogNewMintTime(uint256);
    //-----------------------------------------------------------------------
    //------------------------------ERRORS-----------------------------------
    //-----------------------------------------------------------------------

    error NoRewardsToClaimError();
    error TransferOfLPTokensWasNotPossibleError();
    error NotEnoughAmountOfTokensDepositedError();
    error WrongLockUpPeriodError();
    error MsgSenderIsNotVaultError();
    error DepositAmountExceededError();
    error NoLPTokensToWithdrawError();

    //-----------------------------------------------------------------------
    //--------------------------FUNCTION-HEADERS-----------------------------
    //-----------------------------------------------------------------------

    //------------------------------EXTERNAL---------------------------------

    /// @notice Function where the user deposits the Uniswap LP tokens, chooses the lock-up period and receives LP tokens
    /// @param amount_: amount of Uniswap LP tokens to deposit
    /// @param lockUpPeriod_: lock up period chosen by the user that will determine the rewards multiplier - 6 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    function deposit(uint256 amount_, uint256 lockUpPeriod_) external payable returns (bool);

    /// @notice  Function where the user withdraws the deposits. The list of deposits to withdraw may be chosen.
    /// @param depositsToWithdraw: list of deposits ids that the user wants to withdraw, if left empty all deposits will try to be withdrawn.
    function withdraw(uint256[] memory depositsToWithdraw) external;

    /// @notice Function where the user can claim the rewards it has accrued
    /// @param rewardsToClaim: amount of rewards that the user wants to claim, if left at zero all rewards will be claimed
    /// @return rewardsToClaim: claimed rewards
    function claimRewards(uint256 rewardsToClaim) external payable returns (uint256);

    /// @notice getter to get info about a specific deposit - used in tests
    /// @param id_: id of the deposit
    /// @return Node: node that represents the deposit
    function getDeposit(uint256 id_) external view returns (Node memory);

    function getDepositEndtime(uint256 id_) external view returns (uint256);
}
