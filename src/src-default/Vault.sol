// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { LinkedList } from "src/src-default/LinkedList.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { Token } from "src/src-default/Token.sol";
import { IVault } from "src/src-default/interfaces/IVault.sol";

contract Vault is Initializable, OwnableUpgradeable, UUPSUpgradeable, LinkedList, IVault {
    //-----------------------------------------------------------------------
    //------------------------------VARIABLES--------------------------------
    //-----------------------------------------------------------------------

    address private _LPToken;
    uint256 private _totalWeightLocked;
    uint256 private _totalShares;
    Token private _rewardsToken;
    uint256 private _lastMintTime;
    uint256 REWARDS_PER_SECOND = 317;

    mapping(address => uint256) public rewardsAcrued; // updated when a user tries to claim rewards
    mapping(address => uint256[]) public ownersDepositId; // ids of the owners

    modifier onlyVault() {
        if (msg.sender != address(this)) revert MsgSenderIsNotVaultError();
        _;
    }

    constructor(address LPToken_) initializer {
        _LPToken = LPToken_;
        _rewardsToken = new Token(address(0x0), address(this));
    }

    receive() external payable { }

    fallback() external { }

    //-----------------------------------------------------------------------
    //------------------------------EXTERNAL---------------------------------
    //-----------------------------------------------------------------------

    /// @notice Set-up for the contract to be upgradable in the future

    function initialize() external initializer {
        // Initialize inheritance chain
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function deposit(uint256 amount_, uint256 lockUpPeriod_) external {
        if (amount_ == 0) revert NotEnoughAmountOfTokensDepositedError();
        // Check if any deposit has expired
        _checkForExpiredDeposits();

        // Transfer the tokens to the contract
        (bool success,) = _LPToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount_)
        );
        if (!success) revert TransferOfLPTokensWasNotPossibleError();

        // Create a new deposit
        uint256 share = amount_ * _getRewardsMultiplier(lockUpPeriod_);
        uint256 depositID = _insertNewNode(lockUpPeriod_, share, amount_); // new deposit
        ownersDepositId[msg.sender].push(depositID);

        // Update variables
        _totalWeightLocked = _updateTotalWeightLocked(block.timestamp);
        _totalShares = _totalShares + share;
    }

    function withdraw(uint256[] memory depositsToWithdraw) external {
        // Check if any deposit has expired
        _checkForExpiredDeposits();

        uint256 totalLPTokensToWithdraw_ = 0;
        // If the array if left empty, all deposits will try to be withdrawn
        if (depositsToWithdraw.length == 0) {
            depositsToWithdraw = ownersDepositId[msg.sender];
        }

        // Go over depositsToWithdraw array and check if any has expired
        for (uint256 i = 0; i < depositsToWithdraw.length; i++) {
            // Deposit has expired and belongs to the owner
            if (
                deposits[depositsToWithdraw[i]].endTime < block.timestamp
                    && deposits[depositsToWithdraw[i]].owner == msg.sender
            ) {
                // Sum to the total amount of tokens to withdraw
                totalLPTokensToWithdraw_ = totalLPTokensToWithdraw_ + deposits[depositsToWithdraw[i]].depositedLPTokens;

                // Zero out the deposits so the user may not be able to withdraw again
                deposits[depositsToWithdraw[i]].depositedLPTokens = 0;
            } else {
                emit LogWithdrawHasNotExpired(depositsToWithdraw[i]);
            }
        }

        // If there are tokens to transfer, transfer them
        if (totalLPTokensToWithdraw_ != 0) {
            // Transfer LP tokens to the msg.sender
            (bool success,) = _LPToken.call(
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, totalLPTokensToWithdraw_)
            );
            if (!success) revert TransferOfLPTokensWasNotPossibleError();
            emit LogWithdraw(msg.sender, totalLPTokensToWithdraw_);
        }
    }

    function claimRewards(uint256 rewardsToClaim) external returns (uint256) {
        // Check if any deposit has expired
        _checkForExpiredDeposits();

        // If there are any rewards to claim, they will be distributed
        if (rewardsAcrued[msg.sender] > 0) {
            // If rewardsToClaim is left at zero, all rewards will be claimed
            if (rewardsToClaim == 0) {
                rewardsToClaim = rewardsAcrued[msg.sender];
            }

            // Update total amount of rewards held by the msg.sender
            rewardsAcrued[msg.sender] = rewardsAcrued[msg.sender] - rewardsToClaim;

            // Mint rewards tokens to the user
            _rewardsToken.mint(msg.sender, rewardsToClaim);
            emit LogRewardsTokenMinted(msg.sender, rewardsToClaim);
        } else {
            revert NoRewardsToClaimError();
        }

        return rewardsToClaim;
    }

    function getDeposit(uint256 id_) external view onlyVault returns (ILinkedList.Node memory) {
        return (deposits[id_]);
    }

    //-----------------------------------------------------------------------
    //------------------------------INTERNAL---------------------------------
    //-----------------------------------------------------------------------

    /// @notice Function that checks if any deposits have expired and manages the expirations
    function _checkForExpiredDeposits() internal {
        // Start going over the list at the beggining
        uint256 currentId_ = getHead();
        address owner_;

        // See if any deposit has expired
        while (block.timestamp > deposits[currentId_].endTime && currentId_ != 0) {
            // Update weight locked according to the expiration date of the deposit that expired
            _totalWeightLocked = _updateTotalWeightLocked(deposits[currentId_].endTime);

            // Update rewards acrued by the user
            owner_ = deposits[currentId_].owner;
            rewardsAcrued[owner_] = rewardsAcrued[owner_]
                + (_totalWeightLocked - deposits[currentId_].currentTotalWeight) * deposits[currentId_].share;

            // Reduce total amount of shares present in the vault
            _totalShares = _totalShares - deposits[currentId_].share;
            emit LogDepositExpired(owner_, currentId_);

            // Update variables
            currentId_ = deposits[currentId_].nextId;

            // Remove node - the node to delete will always be the head, so previousId = 0
            remove(0, currentId_);
        }
    }

    /// @notice Gets the rewards multiplier according to the lockUpPeriod
    /// @param lockUpPeriod: lock up period chosen by the user that will determine the rewards multiplier - 6 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    /// @return rewardsMultiplier: the rewards multiplier according to the locking period
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

    /// @notice inserts a new node into the linked list according to its properties (lockUpPeriod, shares, amount of deposited lp tokens)
    /// @param lockUpPeriod_  lock up period chosen by the user:  6 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    /// @param shares_ amount of shares (deposited tokens * rewardsMultiplier) given to the user
    /// @param amountDepositedLPTokens_ amount of Uniswap LPTokens deposited by the user
    /// @return id of the deposit
    function _insertNewNode(uint256 lockUpPeriod_, uint256 shares_, uint256 amountDepositedLPTokens_)
        internal
        returns (uint256)
    {
        // Calculate end time of the deposit
        uint256 endTime_ = _calculateEndTime(lockUpPeriod_, block.timestamp);

        // Update total weight locked
        _totalWeightLocked = _updateTotalWeightLocked(block.timestamp);

        // Find position where to insert the node
        (uint256 previousId_, uint256 nextId_) = findPosition(endTime_, getHead());

        // Create node
        ILinkedList.Node memory newNode = ILinkedList.Node({
            nextId: nextId_,
            endTime: endTime_,
            share: shares_,
            currentTotalWeight: _totalWeightLocked,
            owner: msg.sender,
            depositedLPTokens: amountDepositedLPTokens_
        });

        // Insert the node into the list according to its position
        emit LogNode(newNode);
        return (insert(newNode, previousId_));
    }

    /// @notice updates the total weight locked according to the time interval considered (endTimeConsidered - lastMintTime)
    /// @param endTimeConsidered_ end time considered to define the time interval where the weight locked will be updated
    /// @return totalWeightLocked_ resulting total weight locked
    function _updateTotalWeightLocked(uint256 endTimeConsidered_) internal returns (uint256 totalWeightLocked_) {
        if (_totalShares != 0) {
            totalWeightLocked_ =
                _totalWeightLocked + (REWARDS_PER_SECOND * (endTimeConsidered_ - _lastMintTime)) / (_totalShares);
        } else {
            totalWeightLocked_ = 0;
        }
        _lastMintTime = endTimeConsidered_;
    }

    /// @notice calculates end time that the deposit will expire according to the lock up period and the current time
    /// @param lockUpPeriod_ lock up period chosen  6 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    /// @param currentTime_ time where the deposit is made and from which the end time will be calculated
    /// @return endTime_ end time where the deposit will expire according to the above mentioned variables
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

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(address newImplementation_) internal override onlyOwner { }
}
