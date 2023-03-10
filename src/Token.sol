// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { OFT } from "@layerZeroOmnichain/token/oft/OFT.sol";

/// @title A LayerZero OmnichainFungibleToken example of BasedOFT
/// @notice Use this contract only on the BASE CHAIN. It locks tokens on source, on outgoing send(), and unlocks tokens when receiving from other chains.
contract Token is OFT {
    uint256 public MAX_SUPPLY = 10 ^ 10;

    address private _owner;
    address public vaultContract;

    constructor(address _layerZeroEndpoint) OFT("Token", "TOK", _layerZeroEndpoint) { }
}
