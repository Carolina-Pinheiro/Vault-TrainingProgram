// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import { LinkedList } from "src/src-default/LinkedList.sol";
import { ILinkedList } from "src/src-default/interfaces/ILinkedList.sol";
import { Token } from "src/src-default/Token.sol";

contract Vault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    //-----------------------------------------------------------------------
    //------------------------------VARIABLES--------------------------------
    //-----------------------------------------------------------------------

    uint256 REWARDS_PER_SECOND = 317;
    address private _LPToken;
    uint256 private _totalWeightLocked;
    uint256 private _totalShares;
    Token private _rewardsToken;
    uint256 private _lastMintTime;

    // There are two situations when a depositShare updates - new deposit (nd) or lock up ends (le)
    // The linked list refers to the depositSharesUpdates, it is organized from past to future (past refers to the beggining of the list, future to the end)
    LinkedList private _deposits = new LinkedList();

    mapping(address => uint256) public rewardsAcrued; // updated when a user tries to claim rewards
    mapping(address => uint256[]) public ownersDepositId; // ids of the owners

    event LogUint(uint256);
    event LogRewardsTokenMinted(address, uint256);

    modifier onlyVault() {
        require(msg.sender == address(this)); // TODO: add error
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

    /// @notice Function where the user deposits the liquidity, chooses the lock-up period and receives LP tokens
    /// @dev still in development
    /// @param amount_: amount of tokens to deposit
    /// @param lockUpPeriod_: lock up period chosen by the user that will determine the rewards multiplier - 0.5 = 6 months, 1 = 1 year, 2 = 2 years, 4 = 4 years
    function deposit(uint256 amount_, uint256 lockUpPeriod_) external {
        // Check if any deposit has expired
        _checkForExpiredDeposits();

        // Transfer the tokens to the contract
        (bool success, bytes memory data) = _LPToken.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount_)
        );
        require(success);

        // Create a new deposit
        uint256 share = amount_ * _getRewardsMultiplier(lockUpPeriod_);
        uint256 depositID = _insertNewNode(lockUpPeriod_, share); // new deposit
        ownersDepositId[msg.sender].push(depositID);
        
        if (_totalShares != 0){
            _totalWeightLocked = _totalWeightLocked + (REWARDS_PER_SECOND * (block.timestamp - _lastMintTime)) / (_totalShares);
        } 
        _lastMintTime = block.timestamp;
        _totalShares = _totalShares + share;
    }

    /// @notice  Function where the user withdraws the deposits
    /// @dev still in development
    /// @param depositsToWithdraw: list of deposits ids that the user wants to withdraw, if left empty all deposits will be withdrawn
    function withdraw(uint256 depositsToWithdraw) external {
        // Check if any deposit has expired
        _checkForExpiredDeposits();
    }

    /// @notice Function where the user can claim the rewards it has accrued
    /// @dev still in development
    /// @param rewardsToClaim: amount of rewards that the user wants to claim, if left empty all rewards will be claimed
    function claimRewards(uint256 rewardsToClaim) external {
        // Check if any deposit has expired
        _checkForExpiredDeposits();

        if (rewardsAcrued[msg.sender] > 0 ){
            // Transfer rewards to the user
            if (rewardsToClaim == 0) { // if rewardsToClaim is left at zero, all rewards will be claimed
                rewardsToClaim = rewardsAcrued[msg.sender] ;
            } 
            rewardsAcrued[msg.sender] = rewardsAcrued[msg.sender] - rewardsToClaim;
            _rewardsToken.mint(msg.sender,rewardsToClaim);
            emit LogRewardsTokenMinted(msg.sender,rewardsToClaim);
        } else {
            revert("No rewards to claim"); // TODO: write proper error message
        }
    }

    //-----------------------------------------------------------------------
    //------------------------------INTERNAL---------------------------------
    //-----------------------------------------------------------------------

    /// @notice Function that checks if any deposits have expired and if the total shares needs to be updated
    /// @dev still in development
    function _checkForExpiredDeposits() internal {
        uint256 rewardsToDistribute_;
        uint256 currentId_ = _deposits.getHead();
        address owner_;


        // See if any deposit has expired
        while (block.timestamp > _deposits.getEndTimeOfNode(currentId_) && currentId_ != 0) {
            if (_totalShares != 0){
                _totalWeightLocked = _totalWeightLocked + (REWARDS_PER_SECOND * (_deposits.getEndTimeOfNode(currentId_)- _lastMintTime))/(_totalShares);
            } else {
                _totalWeightLocked = 0;
            }
            owner_ = _deposits.getOwner(currentId_);
            rewardsAcrued[owner_] = rewardsAcrued[owner_]
                + (_totalWeightLocked - _deposits.getCurrentTotalWeight(currentId_)) * _deposits.getShares(currentId_);
            _totalShares = _totalShares - _deposits.getShares(currentId_);

            currentId_ = _deposits.getNextIdOfNode(currentId_);
            if (currentId_ != 0){ // currentId_ = 0 -> tail, so the list is empty
                _deposits.remove(0,currentId_); // the node to delete will always be the head, so there is no previousId
            }
            _lastMintTime = _deposits.getEndTimeOfNode(currentId_);
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
            revert(
                "Lock up period chosen is not possible, choose between 6 (6 months), 1 (1 year), 2 (2 yeats) or 4 (4 years)"
            );
        }

        return rewardsMultiplier;
    }

    ///
    ///
    ///
    function _insertNewNode(uint256 lockUpPeriod_, uint256 shares_) internal returns (uint256) {
        // Search list since the lastExpiredDepositShareUpdate to insert the new deposit and its end
        uint256 endTime_ = _calculateEndTime(lockUpPeriod_, block.timestamp);
        (uint256 previousId_, uint256 nextId_) = _deposits.findPosition(endTime_, _deposits.getHead());

        // insert into list
        ILinkedList.Node memory newNode = ILinkedList.Node({
            nextId: nextId_,
            startTime: block.timestamp,
            endTime: endTime_,
            share: shares_,
            currentTotalWeight: _totalWeightLocked,
            owner: msg.sender
        });
        return (_deposits.insert(newNode, previousId_));
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

    function getDeposit(uint256 id_) external onlyVault returns (ILinkedList.Node memory) {
        return (_deposits.getNode(id_));
    }

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade

    function _authorizeUpgrade(address newImplementation_) internal override onlyOwner { }
}
