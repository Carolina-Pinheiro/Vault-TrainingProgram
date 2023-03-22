// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Vault } from "src/src-default/Vault.sol";
import { LzApp } from "@layerZeroOmnichain/lzApp/LzApp.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultV2 is Vault, LzApp {
    event LogNewWeightUpdated(uint16, uint256); // chain src, new weight
    event LogNewMintTime(uint16, uint256); // chain src, new mint time
    event LogNewTotalShares(uint16, uint256);

    uint16[] _connectedChains;

    constructor(address LPToken_, address lzEndpoint_) Vault(LPToken_) LzApp(lzEndpoint_) { }

    function transferOwnership(address newOwner) public virtual override(Ownable, Ownable2Step) onlyOwner {
        super.transferOwnership(newOwner);
    }

    function updateTotalWeight(uint16 _dstChainId, uint256 newLastMintTime_, uint256 newTotalWeight_) public payable {
        //Note: also update totalWeightLocked

        // encode the payload with the new lastMintTime
        bytes memory payload = abi.encode(newLastMintTime_, newTotalWeight_, true);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350_000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        // send LayerZero message
        _lzSend( // {value: messageFee} will be paid out of this contract!
            _dstChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(msg.sender), //payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
            address(0x0), // future param, unused for this example
            adapterParams, // v1 adapterParams, specify custom destination gas qty
            msg.value
        );
    }

    function updateTotalShares(uint16 _dstChainId, uint256 totalShares_) public payable {
        //Note: also update totalWeightLocked

        // encode the payload with the new lastMintTime
        bytes memory payload = abi.encode(totalShares_, 0, false);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350_000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        // send LayerZero message
        _lzSend( // {value: messageFee} will be paid out of this contract!
            _dstChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(msg.sender), //payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
            address(0x0), // future param, unused for this example
            adapterParams, // v1 adapterParams, specify custom destination gas qty
            msg.value
        );
    }

    function _transferOwnership(address newOwner) internal virtual override(Ownable, Ownable2Step) {
        super._transferOwnership(newOwner);
    }

    function addConnectedChains(uint16 chainId_) public onlyOwner {
        _connectedChains.push(chainId_);
    }

    function _blockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload)
        internal
        virtual
        override
    {
        // TODO: something to verify the correctness of the info received and its source

        // decode the payload
        (uint256 arg1, uint256 arg2, bool isTotalWeightUpdate_) = abi.decode(_payload, (uint256, uint256, bool));

        if (isTotalWeightUpdate_) {
            _setTotalWeightLocked(arg2);
            _setLastMintTime(arg1);
            emit LogNewWeightUpdated(_srcChainId, arg2);
            emit LogNewMintTime(_srcChainId, arg1);
        } else {
            _setTotalShares(arg1);
            emit LogNewTotalShares(_srcChainId, arg1);
        }
    }

    function _updateTotalWeightLocked(uint256 endTimeConsidered_)
        internal
        override
        returns (uint256 totalWeightLocked_)
    {
        if (getTotalShares() != 0) {
            totalWeightLocked_ = getTotalWeightLocked()
                + (REWARDS_PER_SECOND * (endTimeConsidered_ - getLastMintTime())) / (getTotalShares());
        } else {
            totalWeightLocked_ = getTotalWeightLocked();
        }
        _setLastMintTime(endTimeConsidered_);
        // TODO: 2 replace by chainID that should be tracked somewhere
        for (uint16 i; i < _connectedChains.length; i++) {
            updateTotalWeight(_connectedChains[i], getLastMintTime(), totalWeightLocked_);
        }
        return totalWeightLocked_;
    }

    function _updateTotalShares(uint256 newTotalShares_) internal override {
        _setTotalShares(newTotalShares_);
        for (uint16 i; i < _connectedChains.length; i++) {
            updateTotalShares(_connectedChains[i], newTotalShares_); // send info to other chain
        }
    }
}
