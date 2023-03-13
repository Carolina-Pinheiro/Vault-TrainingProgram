// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { OFT } from "@layerZeroOmnichain/token/oft/OFT.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title A LayerZero OmnichainFungibleToken example of BasedOFT
/// @notice Use this contract only on the BASE CHAIN. It locks tokens on source, on outgoing send(), and unlocks tokens when receiving from other chains.
contract Token is OFT, AccessControl {
    uint256 public MAX_SUPPLY = 10 ^ 10;

    address private _vaultContract;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address _layerZeroEndpoint, address vaultContract_) OFT("Token", "TOK", _layerZeroEndpoint) {
        _vaultContract = vaultContract_;
        _setupRole(MINTER_ROLE, _vaultContract);
    }

    modifier isMinter() {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role to mint");
        _;
    }

    /// @dev needed since contract is inhereting two contracts w/supportInterface
    /// @dev more info: https://forum.openzeppelin.com/t/derived-contract-must-override-function-supportsinterface/6315
    function supportsInterface(bytes4 interfaceId) public view virtual override(OFT, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Function that mints the tokens to a user according to an amount. msg.sender must have MINTER_ROLE
    /// @param to_: address where to send the tokens to
    /// @param amount_: amount of tokens to mint
    function mint(address to_, uint256 amount_) public virtual isMinter {
        _mint(to_, amount_);
    }
}
