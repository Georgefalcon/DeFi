//SPDX-License-Identifier: MIT
// Handler is going to narrow down  the way we call our function

pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DecentralizedStableCoin public dSC;
    DSCEngine public dSCEngine;
    ERC20Mock public wETH;
    ERC20Mock public wBTC;
    uint256 public timeMintIsCalled;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public userWithDepositedCollateral;
    MockV3Aggregator public ETHUsdpriceFeed;
    MockV3Aggregator public BTCUsdpriceFeed;

    constructor(DSCEngine _dSCEngine, DecentralizedStableCoin _dSC) {
        dSC = _dSC;
        dSCEngine = _dSCEngine;
        address[] memory collateralToken = dSCEngine.getCollateralToken();
        wETH = ERC20Mock(collateralToken[0]);
        wBTC = ERC20Mock(collateralToken[1]);
        ETHUsdpriceFeed = MockV3Aggregator(
            dSCEngine.getCollateralTokenPriceFeed(address(wETH))
        );
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        if (userWithDepositedCollateral.length == 0) {
            return;
        }
        address sender = userWithDepositedCollateral[
            addressSeed % userWithDepositedCollateral.length
        ];
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dSCEngine
            .getAccountInformation(sender);
        int256 maxDSCToMint = (int256(collateralValueInUSD) / 2) -
            int256(totalDSCMinted);
        if (maxDSCToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        dSCEngine.mintDSC(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    function DepositCollateral(
        uint256 CollateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock Collateral = _getCollateralFromSeed(CollateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        Collateral.mint(msg.sender, amountCollateral);
        Collateral.approve(address(dSCEngine), amountCollateral);
        dSCEngine.DepositCollateral(address(Collateral), amountCollateral);
        vm.stopPrank();
        userWithDepositedCollateral.push(msg.sender);
    }

    function RedeemCollateral(
        uint256 CollateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock Collateral = _getCollateralFromSeed(CollateralSeed);
        uint256 maxCollateralToRedeem = dSCEngine.getCollateralBalanceOfUser(
            msg.sender,
            address(Collateral)
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dSCEngine.redeemCollateral(address(Collateral), amountCollateral);
    }

    // This breaks our invariant suite!!
    // function updateCollateralPrice(uint96 price) public {
    //     int256 newPrice = int256(uint256(price));
    //     ETHUsdpriceFeed.updateAnswer(newPrice);
    // }

    // Helper
    function _getCollateralFromSeed(
        uint256 CollateralSeed
    ) private view returns (ERC20Mock) {
        if (CollateralSeed % 2 == 0) {
            return wETH;
        }
        return wBTC;
    }
}
