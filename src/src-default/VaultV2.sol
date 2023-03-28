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
    event LogConnectedTo(uint16);
    event LogString(string);
    event LogAddress(address);
    event LogBytes(bytes4);
    event LogMessageSentToChain(uint256);

    error NotTrustedChainOrAddressError();

    event LogNodeLL(Node);

    uint16[] _connectedChains;
    mapping(uint16 => address) private _trustedAddresses; // só uma vualt por chain

    struct depositInfo {
        uint256 hint;
        uint256 endTime;
        uint256 shares;
        uint256 amount;
    }

    constructor(address LPToken_, address lzEndpoint_) Vault(LPToken_) LzApp(lzEndpoint_) { }

    function transferOwnership(address newOwner) public virtual override(Ownable, Ownable2Step) onlyOwner {
        super.transferOwnership(newOwner);
    }

    /// ---------------------------------
    /// --- CHAIN MSG SENDER FUNCTIONS
    /// ---------------------------------
    /// @notice updates totalWeightLocked in a specific chain
    /// @param _dstChainId destination chain
    /// @param newLastMintTime_ updated last mint time, must be updated when totalWeightLocked is updated
    /// @param newTotalWeight_ new total weight locked
    function sendMessageUpdateTotalWeight(uint16 _dstChainId, uint256 newLastMintTime_, uint256 newTotalWeight_)
        external
        payable
    {
        //Note: also update totalWeightLocked

        // encode the payload with the new lastMintTime
        depositInfo memory newDeposit_;
        bytes memory payload = abi.encode(newLastMintTime_, newTotalWeight_, newDeposit_, 1);

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

    /// @notice updates totalShares in a specific chain
    /// @param _dstChainId destination chain
    /// @param totalShares_ new totalShares to update
    function sendMessageUpdateTotalShares(uint16 _dstChainId, uint256 totalShares_) external payable {
        depositInfo memory newDeposit_;
        // encode the payload with the new totalShares
        bytes memory payload = abi.encode(totalShares_, 0, newDeposit_, 2);

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

    /// @notice send message to update or remove new deposit according to the payload
    /// @param _dstChainId destination chain
    /// @param payload contains the info of the deposit
    /// @param adapterParams parameters of the message
    function sendMessageDeposit(uint16 _dstChainId, bytes memory payload, bytes memory adapterParams)
        external
        payable
    {
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

    /// ---------------------------------
    /// --- OVERIDDEN

    /// @notice called when a deposit is created in this vault. Sends message to the other vaults to add the new deposit but with zero address
    /// @param hint_ hint of where to insert the new deposit
    /// @param endTime_ expiration time of the new deposit
    /// @param shares_ amount of shares of the deposit
    /// @param amount_ amount of tokens deposited
    function _updateDeposit(uint256 hint_, uint256 endTime_, uint256 shares_, uint256 amount_) internal override {
        // NOTE CAN BE IMPROVED TO BE MORE EFFIECNT USING THE HINT
        depositInfo memory newDeposit_ =
            depositInfo({ hint: hint_, endTime: endTime_, shares: shares_, amount: amount_ });
        // encode the payload with the new totalShares
        bytes memory payload = abi.encode(0, 0, newDeposit_, 3);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350_000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        for (uint16 i = 0; i < _connectedChains.length; i++) {
            this.sendMessageDeposit{ value: 0.5 ether }(_connectedChains[i], payload, adapterParams);
        }
    }

    /// @notice called when a deposit expires according to the present vault. Sends message to the other vaults to remove the expired deposit
    /// @param idToRemove the id of the expired deposit that will be removed across all chains
    function _updateDepositExpired(uint256 idToRemove) internal override {
        // encode the payload with the new totalShares
        depositInfo memory newDeposit_;

        bytes memory payload = abi.encode(idToRemove, 0, newDeposit_, 4);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350_000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        for (uint16 i = 0; i < _connectedChains.length; i++) {
            this.sendMessageDeposit{ value: 0.5 ether }(_connectedChains[i], payload, adapterParams);
        }
    }

    /// ---------------------------------
    /// --- Internal
    /// ---------------------------------
    /// @notice called when a message is received that a deposit is created in another vault and is then propagated to this vault.
    /// @param hint_ hint of where to insert the new deposit
    /// @param endTime_ expiration time of the new deposit
    /// @param shares_ amount of shares of the deposit
    /// @param amount_ amount of tokens deposited
    function _addExternalDeposit(uint256 hint_, uint256 endTime_, uint256 shares_, uint256 amount_) internal {
        // Find position where to insert the node
        _updateTotalWeightLocked(block.timestamp);
        (uint256 previousId_, uint256 nextId_) = findPosition(endTime_, getHead()); //hint_

        // Create node
        Node memory newNode = Node({
            nextId: nextId_,
            endTime: endTime_,
            share: shares_,
            currentTotalWeight: getTotalWeightLocked(),
            owner: address(0x0), // the deposit does not belong to this vault, so the owner will be zero
            depositedLPTokens: amount_
        });

        // Insert the node into the list according to its position
        insert(newNode, previousId_);
        _updateTotalShares(getTotalShares() + shares_);
        // Print List
        uint256 id = getHead();
        while (id != 0) {
            emit LogNodeLL(deposits[id]);
            id = deposits[id].nextId;
        }
    }

    /// @notice called when a message is received that a deposit expired in another vault
    /// @param id_ the id of the expired deposit that will be removed across all chains
    function _removeExternalDeposit(uint256 id_) internal {
        // Start going over the list at the beggining
        address owner_;
        // See if any deposit has expired
        // Update weight locked according to the expiration date of the deposit that expired
        _updateTotalWeightLocked(deposits[id_].endTime);

        // Update rewards acrued by the user
        owner_ = deposits[id_].owner;
        if (owner_ != address(0x0)) {
            rewardsAcrued[owner_] = rewardsAcrued[owner_]
                + (getTotalWeightLocked() - deposits[id_].currentTotalWeight) * deposits[id_].share;
            emit LogRewardsAcrued(rewardsAcrued[owner_]);
        }
        // Reduce total amount of shares present in the vault
        _updateTotalShares(getTotalShares() - deposits[id_].share);
        deposits[id_].share = 0;
        emit LogDepositExpired(owner_, id_);

        // Remove node - the node to delete will always be the head, so previousId = 0
        remove(0, deposits[id_].nextId);

        // Print List
        uint256 id = getHead();
        while (id != 0) {
            emit LogNodeLL(deposits[id]);
            id = deposits[id].nextId;
        }
    }

    /// @notice called when a message is received that a deposit expired in another vault
    /// @param newOwner new owner of the vault contract
    function _transferOwnership(address newOwner) internal virtual override(Ownable, Ownable2Step) {
        super._transferOwnership(newOwner);
    }

    /// ---------------------------------
    /// --- Receiver message from other chains
    /// @notice called when a message is received from other contracts integrated in lz endpoints
    function _blockingLzReceive(uint16 _srcChainId, bytes memory srcAddress_, uint64, bytes memory _payload)
        internal
        virtual
        override
    {
        bool trusted_ = false;
        for (uint256 i_ = 0; i_ < _connectedChains.length; i_++) {
            if (
                _srcChainId == _connectedChains[i_]
                    && _trustedAddresses[_srcChainId] == address(uint160(bytes20(srcAddress_)))
            ) {
                trusted_ = true;
            }
        }
        if (!trusted_) revert NotTrustedChainOrAddressError();

        // decode the payload
        (uint256 arg1, uint256 arg2, depositInfo memory newDeposit, uint256 typeMessage) =
            abi.decode(_payload, (uint256, uint256, depositInfo, uint256));
        if (typeMessage == 1) {
            _setTotalWeightLocked(arg2);
            _setLastMintTime(arg1);
            emit LogNewWeightUpdated(_srcChainId, arg2);
            emit LogNewMintTime(_srcChainId, arg1);
        } else if (typeMessage == 2) {
            _setTotalShares(arg1);
            emit LogNewTotalShares(_srcChainId, arg1);
        } else if (typeMessage == 3) {
            _addExternalDeposit(newDeposit.hint, newDeposit.endTime, newDeposit.shares, newDeposit.amount);
        } else if (typeMessage == 4) {
            _removeExternalDeposit(arg1);
        }
    }

    /// ---------------------------------
    /// --- Helpers
    /// ---------------------------------
    /// @notice visually show which chains are connected and in which direction
    function showConnectedChains() public {
        for (uint16 i = 0; i < _connectedChains.length; i++) {
            emit LogConnectedTo(_connectedChains[i]);
        }
    }

    /// @notice adds a chain and address that should be trusted by the current vault
    /// @param chainId_ if of the trusted chain
    /// @param srcAddress_ address of the trusted contract
    function addConnectedChains(uint16 chainId_, address srcAddress_) public onlyOwner {
        _connectedChains.push(chainId_);
        _trustedAddresses[chainId_] = srcAddress_;
        emit LogAddress(srcAddress_);
    }
}
