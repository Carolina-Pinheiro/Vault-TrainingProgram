// SPDX-License-Identifier: UNLINCESED
pragma solidity ^0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PoolToken is ERC20 {
    address private _owner;

    constructor() ERC20("PoolToken", "POOL") {
        _owner = msg.sender;
    }

    function mint(address to_, uint256 amount_) external {
        require(msg.sender == _owner);
        _mint(to_, amount_);
    }
}
