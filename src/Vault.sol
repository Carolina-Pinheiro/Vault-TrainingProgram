// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Vault {
    //-----------------------------------------------------------------------
    //---------------------------ERRORS-& EVENTS-----------------------------
    //-----------------------------------------------------------------------
    error WrongLockUpPeriodError();

    //-----------------------------------------------------------------------
    //------------------------------VARIABLES--------------------------------
    //-----------------------------------------------------------------------

    uint256 depositID = 0;
    mapping(uint256 => uint256) private lockUpPeriod; // lockUpPeriod -> rewardsMultiplier
    uint256 REWARDS_PER_SECOND = 317; 

    //
    struct Deposit {
        uint256 balance; // number of LP tokens deposit
        uint256 share; // share of pool given the rewards multiplier
        uint256 depositShareId; // id of the deposit share at the time of the deposit - it will not change position from the linked list since all future nd are added after and le also after - it will be from this id that the reward calculations start
        uint256 id; // id of the deposit
        address owner; // debate if necessary
    }

    Deposit[] public depositList; // depositsList[owner] = [Deposit deposit1, Deposit, deposit2, ... ]
    mapping(address => uint256) public rewardsAcrued; // updated when a user tries to claim rewards
    mapping(address => uint256[]) public ownersDepositId; // ids of the owners

    // There are two situations when a depositShare updates - new deposit (nd) or lock up ends (le)
    // The linked list refers to the depositSharesUpdates, it is organized from past to future (past refers to the beggining of the list, future to the end)
    // TODO: implement linked list
    struct depositSharesUpdates {
        uint256 nextId;
        uint256 endTime; // in case of nd it is 'now', le it is 'now+lock-up time'
        uint256 shareToReduce; // + for nd, - for le
    }

    constructor() {
        // Set lock up period
        lockUpPeriod[6] = 1;
        lockUpPeriod[1] = 2;
        lockUpPeriod[2] = 4;
        lockUpPeriod[4] = 8;
    }

    receive() external payable { }

    fallback() external { }

    //-----------------------------------------------------------------------
    //------------------------------EXTERNAL---------------------------------
    //-----------------------------------------------------------------------

    /// @notice Function where the user deposits the liquidity, chooses the lock-up period and receives LP tokens
    /// @dev still in development
    /// @param amount_: amount of tokens to deposit
    /// @param userLockUpPeriod_: lock up period chosen by the user that will determine the rewards multiplier - 0.5 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    function deposit(uint256 amount_, uint256 userLockUpPeriod_) external {
        // Check if any deposit has expired
        _checkForDtUpdates();

        // TODO: Check if the Tokens can be transfered to the contract

        // Create a new deposit
        Deposit memory newDeposit_ = Deposit({
            balance: amount_,
            share: amount_ * getRewardsMultiplier(userLockUpPeriod_),
            depositShareId: getCurrentShareId(),
            id: depositID,
            owner: msg.sender
        });
        depositList[msg.sender].push(newDeposit_);
        ownersDepositId[msg.sender].push(depositID);
        depositID++;
    }

    /// @notice  Function where the user withdraws the deposits
    /// @dev still in development
    /// @param depositsToWithdraw_: list of deposits ids that the user wants to withdraw, if left empty all deposits will be withdrawn
    function withdraw(uint256[] calldata depositsToWithdraw_) external {
        // Check if any deposit has expired
        _checkForDtUpdates();
    }

    /// @notice Function where the user can claim the rewards it has accrued
    /// @dev still in development
    /// @param rewardsToClaim_: amount of rewards that the user wants to claim, if left empty all rewards will be claimed
    function claimRewards(uint256 rewardsToClaim_) external {
        // Check if any deposit has expired
        _checkForDtUpdates();
    }

    //-----------------------------------------------------------------------
    //------------------------------INTERNAL---------------------------------
    //-----------------------------------------------------------------------

    /// @notice Function that checks if any deposits have expired and if the total shares needs to be updated
    /// @dev still in development
    function _checkForDtUpdates() internal {
        // TODO
    }

    /// @notice Gets the rewards multiplier according to the lockUpPeriod
    /// @dev still in development
    /// @param userLockUpPeriod_: lock up period chosen by the user that will determine the rewards multiplier - 6 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    /// @return rewardsMultiplier_ : the rewards multiplier according to the locking period
    function getRewardsMultiplier(uint256 userLockUpPeriod_) internal view returns (uint256 rewardsMultiplier_) {
        if (lockUpPeriod[userLockUpPeriod_] != 0) {
            rewardsMultiplier_ = lockUpPeriod[userLockUpPeriod_];
        } else {
            revert WrongLockUpPeriodError();
        }
        return rewardsMultiplier_;
    }

    /// @notice Gets the current share id
    /// @dev still in development
    /// @return currentShareId: the current share id
    function getCurrentShareId() internal pure returns (uint256) {
        // TODO

        return 0;
    }
}
