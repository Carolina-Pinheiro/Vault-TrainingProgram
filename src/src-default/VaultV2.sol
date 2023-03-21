// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { Vault } from "src/src-default/Vault.sol";
import { LzApp } from "@layerZeroOmnichain/lzApp/LzApp.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultV2 is Vault, LzApp {
    event LogBlockingLzReceive();

    constructor(address LPToken_, address lzEndpoint_) Vault(LPToken_) LzApp(lzEndpoint_) { }

    function transferOwnership(address newOwner) public virtual override(Ownable, Ownable2Step) onlyOwner {
        super.transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual override(Ownable, Ownable2Step) onlyOwner {
        super._transferOwnership(newOwner);
    }

    function _blockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload)
        internal
        virtual
        override
    {
        emit LogBlockingLzReceive();
    }
}
