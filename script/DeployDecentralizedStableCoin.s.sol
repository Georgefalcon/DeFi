// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.22;

// imports
import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";

contract DeployDecentralizedStableCoin is Script {
    DecentralizedStableCoin public decentralizedStableCoin;
    DSCEngine public dSCEngine;

    function run() external returns (DecentralizedStableCoin) {
        // dSCEngine = new DSCEngine();
        vm.startBroadcast();
        decentralizedStableCoin = new DecentralizedStableCoin();
        vm.stopBroadcast();
        return decentralizedStableCoin;
        decentralizedStableCoin.transferOwnership(address(dSCEngine));
    }
}
