// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// // Have our Invariant aka properties hold true for all time

// // what are our invariants?
// //what are the properties of the system that should always hold true?
// // what are the properties of the system tat should always hold

// // 1. the total supply of DSC  should always be less than the value of collateral
// // 2. getter view function should never revert <- evergreen invariant

// pragma solidity 0.8.22;

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {MockV3Aggregator} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

// contract OpenInvariantTest is StdInvariant, Test {
//     DSCEngine public dSCEngine;
//     DecentralizedStableCoin public dSC;
//     DeployDSCEngine public deployer;
//     HelperConfig public helperConfig;
//     address ETHUSDpriceFeed;
//     address BTCUSDpriceFeed;
//     address wETH;
//     address wBTC;

//     function setUp() external {
//         deployer = new DeployDSCEngine();
//         (dSCEngine, dSC, helperConfig) = deployer.run();
//         (ETHUSDpriceFeed, BTCUSDpriceFeed, wETH, wBTC, ) = helperConfig
//             .ActiveNetworkConfig();
//         targetContract(address(dSCEngine));
//     }

//     function invariant_protocolMustHaveMoreThanTotalSupply() external {
//         // get the value of all the collateral in the protocol
//         // compare it to the debt(dSC)
//         uint256 totalSupply = dSC.totalSupply();
//         uint256 totalwETHDeposited = IERC20(wETH).balanceOf(address(dSCEngine));
//         uint256 totalwBTCDeposited = IERC20(wBTC).balanceOf(address(dSCEngine));

//         uint256 wETHValueInUSD = dSCEngine.getUSDValue(
//             wETH,
//             totalwETHDeposited
//         );
//         uint256 wBTCValueInUSD = dSCEngine.getUSDValue(
//             wBTC,
//             totalwBTCDeposited
//         );
//         assert(wETHValueInUSD + wBTCValueInUSD >= totalSupply);
//     }
// }
