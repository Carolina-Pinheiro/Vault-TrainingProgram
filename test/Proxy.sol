// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Token } from "src/src-default/Token.sol";

contract Proxy is TransparentUpgradeableProxy {
    constructor(address _logic, address _admin, bytes memory _data)
        TransparentUpgradeableProxy(_logic, _admin, _data)
    {
        /*(bool success,) = _logic.call(
            abi.encodeWithSignature("initialize()")
        );*/
    }
}
