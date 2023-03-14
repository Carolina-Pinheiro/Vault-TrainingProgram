// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { LinkedList } from "src/src-default/LinkedList.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";

contract Vault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    //-----------------------------------------------------------------------
    //------------------------------VARIABLES--------------------------------
    //-----------------------------------------------------------------------

    uint256 depositID = 0;
    uint256 REWARDS_PER_SECOND = 317;
    address public LPToken;
    uint256 private _lastExpiredDepositSharesUpdate = 0;

    // There are two situations when a depositShare updates - new deposit (nd) or lock up ends (le)
    // The linked list refers to the depositSharesUpdates, it is organized from past to future (past refers to the beggining of the list, future to the end)
    LinkedList private _depositSharesUpdates = new LinkedList();
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

    event LogUint(uint256);

    constructor(address LPToken_) initializer {
        LPToken = LPToken_;
        /**
         * LinkedList.Node memory zeroNode =
         *         LinkedList.Node({
         *                           nextId: 0,
         *                           endTime: 1,
         *                           shareToReduce: 0,
         *                           dtAtDeposit: 0
         *                         });
         *     _depositSharesUpdates.insert(zeroNode, 0);
         *
         */
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

    /// @notice Function where the user deposits the liquidity, chooses the lock-up period and receives LP tokens
    /// @dev still in development
    /// @param amount_: amount of tokens to deposit
    /// @param lockUpPeriod_: lock up period chosen by the user that will determine the rewards multiplier - 0.5 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    function deposit(uint256 amount_, uint256 lockUpPeriod_) external {
        // Check if any deposit has expired
        _checkForDtUpdates();

        // Transfer the tokens to the contract
        (bool success, bytes memory data) = LPToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount_)
        );
        require(success);

        // Create a new deposit
        uint256 share = amount_ * _getRewardsMultiplier(lockUpPeriod_);
        Deposit memory newDeposit = Deposit({
            balance: amount_,
            share: share,
            depositShareId: _getCurrentShareId(),
            id: depositID,
            owner: msg.sender
        });
        depositList.push(newDeposit);
        ownersDepositId[msg.sender].push(depositID);
        depositID++;

        _insertNewNode(0, share, true); // new deposit
        _insertNewNode(lockUpPeriod_, share, false); // lock up period ends
    }

    /// @notice  Function where the user withdraws the deposits
    /// @dev still in development
    /// @param depositsToWithdraw: list of deposits ids that the user wants to withdraw, if left empty all deposits will be withdrawn
    function withdraw(uint256[] calldata depositsToWithdraw) external {
        // Check if any deposit has expired
        _checkForDtUpdates();
    }

    /// @notice Function where the user can claim the rewards it has accrued
    /// @dev still in development
    /// @param rewardsToClaim: amount of rewards that the user wants to claim, if left empty all rewards will be claimed
    function claimRewards(uint256 rewardsToClaim) external {
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
            revert(
                "Lock up period chosen is not possible, choose between 6 (6 months), 1 (1 year), 2 (2 yeats) or 4 (4 years)"
            );
        }

        return rewardsMultiplier;
    }

    /// @notice Gets the current share id
    /// @dev still in development
    /// @return currentShareId: the current share id
    function _getCurrentShareId() internal pure returns (uint256) {
        // TODO

        return 0;
    }

    ///
    ///
    ///
    function _insertNewNode(uint256 lockUpPeriod_, uint256 shares_, bool isNewDeposit_) internal {
        // Search list since the lastExpiredDepositShareUpdate to insert the new deposit and its end
        uint256 endTime_ = _calculateEndTime(lockUpPeriod_, block.timestamp);
        (uint256 previousId_, uint256 nextId_) =
            _depositSharesUpdates.findPosition(endTime_, _lastExpiredDepositSharesUpdate);

        // insert into list
        ILinkedList.Node memory newNode = ILinkedList.Node({
            nextId: nextId_,
            endTime: endTime_,
            shares: shares_,
            dtAtDeposit: 10,
            isNewDeposit: isNewDeposit_
        });
        _depositSharesUpdates.insert(newNode, previousId_);

        if (isNewDeposit_ && previousId_ != 0) {
            _lastExpiredDepositSharesUpdate = _depositSharesUpdates.getNextIdOfNode(previousId_);
        } else if (isNewDeposit_) {
            _lastExpiredDepositSharesUpdate = _depositSharesUpdates.getHead();
        }
    }

    ///
    ///
    ///
    function _calculateEndTime(uint256 lockUpPeriod_, uint256 currentTime_) internal pure returns (uint256 endTime_) {
        uint256 factor_;
        //TODO: implement this better
        if (lockUpPeriod_ == 6) {
            factor_ = 26;
            lockUpPeriod_ = 1;
        } else if (lockUpPeriod_ == 0) {
            factor_ = 0;
        } else {
            factor_ = 52;
        }

        endTime_ = lockUpPeriod_ * factor_ * 1 weeks + currentTime_;
        return (endTime_);
    }
    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade

    function _authorizeUpgrade(address newImplementation_) internal override onlyOwner { }
}
