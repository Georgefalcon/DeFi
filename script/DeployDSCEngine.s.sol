// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.22;

// imports
import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSCEngine is Script {
    DSCEngine public dSCEngine;
    HelperConfig public helperConfig;
    DecentralizedStableCoin public dSC;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run()
        external
        returns (DSCEngine, DecentralizedStableCoin, HelperConfig)
    {
        helperConfig = new HelperConfig();
        (
            address wETHUsdpriceFeed,
            address wBTCUsdpriceFeed,
            address wETH,
            address wBTC,
            uint256 deployerKey
        ) = helperConfig.ActiveNetworkConfig();
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHUsdpriceFeed, wBTCUsdpriceFeed];

        vm.startBroadcast(deployerKey);
        dSC = new DecentralizedStableCoin();
        dSCEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dSC)
        );
        dSC.transferOwnership(address(dSCEngine));
        vm.stopBroadcast();
        return (dSCEngine, dSC, helperConfig);
    }
}
