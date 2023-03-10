// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract Vault {
    //-----------------------------------------------------------------------
    //---------------------------ERRORS-& EVENTS-----------------------------
    //-----------------------------------------------------------------------
    error wrongLockUpPeriod();

    //-----------------------------------------------------------------------
    //------------------------------VARIABLES--------------------------------
    //-----------------------------------------------------------------------

    uint256 depositID = 0;
    mapping(uint256 => uint256) private lockUpPeriod; // lockUpPeriod -> rewardsMultiplier

    //
    struct Deposit {
        uint256 balance; // number of LP tokens deposit
        uint256 share; // share of pool given the rewards multiplier
        uint256 depositShareId; // id of the deposit share at the time of the deposit - it will not change position from the linked list since all future nd are added after and le also after - it will be from this id that the reward calculations start
        uint256 id; // id of the deposit
        address owner; // debate if necessary
    }

    mapping(address => Deposit[]) public depositList; // depositsList[owner] = [Deposit deposit1, Deposit, deposit2, ... ]
    mapping(address => uint256) public rewardsAcrued; // updated when a user tries to claim rewards

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
    /// @param amount: amount of tokens to deposit
    /// @param userLockUpPeriod: lock up period chosen by the user that will determine the rewards multiplier - 0.5 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    function deposit(uint256 amount, uint256 userLockUpPeriod) external {
        // Check if any deposit has expired
        checkForDtUpdates();

        // TODO: Check if the Tokens can be transfered to the contract

        // Create a new deposit
        Deposit memory newDeposit = Deposit({
            balance: amount,
            share: amount * getRewardsMultiplier(userLockUpPeriod),
            depositShareId: getCurrentShareId(),
            id: depositID,
            owner: msg.sender
        });
        depositID++;
        depositList[msg.sender].push(newDeposit);
    }

    /// @notice  Function where the user withdraws the deposits
    /// @dev still in development
    /// @param depositsToWithdraw: list of deposits ids that the user wants to withdraw, if left empty all deposits will be withdrawn
    function withdraw(uint256[] calldata depositsToWithdraw) external {
        // Check if any deposit has expired
        checkForDtUpdates();
    }

    /// @notice Function where the user can claim the rewards it has accrued
    /// @dev still in development
    /// @param rewardsToClaim: amount of rewards that the user wants to claim, if left empty all rewards will be claimed
    function claimRewards(uint256 rewardsToClaim) external {
        // Check if any deposit has expired
        checkForDtUpdates();
    }

    //-----------------------------------------------------------------------
    //------------------------------INTERNAL---------------------------------
    //-----------------------------------------------------------------------

    /// @notice Function that checks if any deposits have expired and if the total shares needs to be updated
    /// @dev still in development
    function checkForDtUpdates() internal {
        // TODO
    }

    /// @notice Gets the rewards multiplier according to the lockUpPeriod
    /// @dev still in development
    /// @param userLockUpPeriod: lock up period chosen by the user that will determine the rewards multiplier - 6 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    /// @return rewardsMultiplier: the rewards multiplier according to the locking period
    function getRewardsMultiplier(uint256 userLockUpPeriod) internal view returns (uint256) {
        uint256 rewardsMultiplier;

        if (lockUpPeriod[userLockUpPeriod] != 0) {
            rewardsMultiplier = lockUpPeriod[userLockUpPeriod];
        } else {
            revert wrongLockUpPeriod();
        }
        return rewardsMultiplier;
    }

    /// @notice Gets the current share id
    /// @dev still in development
    /// @return currentShareId: the current share id
    function getCurrentShareId() internal pure returns (uint256) {
        // TODO

        return 0;
    }
}
