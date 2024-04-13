// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.22;

// imports
import {Test, console, console2} from "forge-std/Test.sol";
import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
// import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    DSCEngine public dSCEngine;
    DecentralizedStableCoin public dSC;
    DeployDSCEngine public deployer;
    HelperConfig public helperConfig;
    address ETHUSDpriceFeed;
    address BTCUSDpriceFeed;
    address wETH;
    address wBTC;
    uint256 deployerKey;
    uint256 amountCollateral = 10 ether;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("user1");
    // uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant LIQUIDATOR_ERC20_BALANCE = 20 ether;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDSCEngine();
        (dSCEngine, dSC, helperConfig) = deployer.run();
        (ETHUSDpriceFeed, , wETH, , ) = helperConfig.ActiveNetworkConfig();
        ERC20Mock(wETH).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wETH).mint(LIQUIDATOR, LIQUIDATOR_ERC20_BALANCE);
    }

    /////////////////
    ///Constructor///
    ////////////////
    function testRevertTokenAddressDoesntMatch() external {
        //Arrange
        tokenAddresses.push(wETH);
        priceFeedAddresses.push(ETHUSDpriceFeed);
        priceFeedAddresses.push(BTCUSDpriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressandPriceFeedAddressMustBeTheSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dSC));
    }

    /////////////////
    ///Price Test////
    ////////////////
    function testGetTokenAmountFromUSD() public {
        //Arrange
        uint256 USDAmount = 100 ether;
        // 1ETH/$2000
        uint256 actuawETHlValue = 0.05 ether;
        uint256 expectedwETHValue = dSCEngine.getTokenAmountFromUSD(
            wETH,
            USDAmount
        );
        //Act/assert
        assertEq(actuawETHlValue, expectedwETHValue);
    }

    function testGetUSDValue() public {
        // Arrange/Act
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedValue = 30000e18;
        uint256 actualValue = dSCEngine.getUSDValue(wETH, ethAmount);
        console.log("value is :%e", actualValue);
        //Assert
        assertEq(expectedValue, actualValue);
    }

    //////////////////////////////
    ///Deposit Collateral Test///
    /////////////////////////////
    function testRevertIfCollateralIsZero() external {
        //Arrange
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(dSCEngine), amountCollateral);
        //Act/assert
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dSCEngine.DepositCollateral(wETH, 0);
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock RanToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            amountCollateral
        );
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__NotAllowedToken.selector,
                address(RanToken)
            )
        );
        dSCEngine.DepositCollateral(address(RanToken), amountCollateral);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(dSCEngine), amountCollateral);
        dSCEngine.DepositCollateral(wETH, amountCollateral);
        _;
    }

    function testDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dSCEngine
            .getAccountInformation(USER);
        console.log(totalDSCMinted);
        console.log(collateralValueInUSD);

        uint256 expectedtotalDSCminted = 0;
        uint256 expectedDepositAmount = dSCEngine.getTokenAmountFromUSD(
            wETH,
            collateralValueInUSD
        );
        console.log(expectedDepositAmount);

        //assert
        assertEq(totalDSCMinted, expectedtotalDSCminted);
        assertEq(amountCollateral, expectedDepositAmount);
    }

    // function testEmitOnDepositCollateral() external depositCollateral {
    //     vm.expectEmit(true, true, false, true);
    //     emit CollateralDeposited(USER, wETH, amountCollateral);
    // }
    //////////////////////////////
    ///MintDSC Test///
    /////////////////////////////

    // if the amountOfDSCToMint surpassses 10000e18, the testfails as the health factoers
    function testMintDSC() external depositCollateral {
        //Arrange
        uint256 amountOfDSCToMint = 9999e18;
        //Act
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        uint256 expectedDSC = dSCEngine.getMintedDSCAmount(
            USER,
            amountOfDSCToMint
        );
        //Assert
        assertEq(amountOfDSCToMint, expectedDSC);
    }

    // here's a test for that
    function testMintDSCRevertIfItSBreaksHealthFactor()
        external
        depositCollateral
    {
        //Arrange
        uint256 amountOfDSCToMint = 10000e18;
        //Act
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        uint256 userhealthFactor = dSCEngine.getHealthFactor(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                userhealthFactor
            )
        );
        dSCEngine.mintDSC(amountOfDSCToMint);
    }

    function testRevertIfMintZero() external depositCollateral {
        //Arrange
        uint256 amountOfDSCToMint = 0;
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dSCEngine.mintDSC(amountOfDSCToMint);
    }

    //////////////////////////////
    ///DepositAndMintDSC Test///
    /////////////////////////////
    function testDepositAndMintDSC() external {
        //Arrange
        uint256 amountOfDSCToMint = 9999e18;
        //Act
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(dSCEngine), amountCollateral);
        dSCEngine.DepositCollateralAndMintDSC(
            wETH,
            amountCollateral,
            amountOfDSCToMint
        );
    }

    //////////////////////////////
    ///BurnDSC Test//////////////
    /////////////////////////////
    function testBurnDSC() external depositCollateral {
        //Arrange
        uint256 amountOfDSCToMint = 9999e18;
        uint256 UserDSC = dSC.balanceOf(USER);
        ///Act
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        UserDSC = dSC.balanceOf(USER);
        console.log("user DSC is:%e", UserDSC);
        dSC.approve(address(dSCEngine), amountOfDSCToMint);
        dSCEngine.burnDSC(amountOfDSCToMint);
        UserDSC = dSC.balanceOf(USER);
        console.log("user DSC is:%e", UserDSC);
    }

    function testRevertIfBurnDSCIsZero() external depositCollateral {
        //Arrange
        uint256 amountOfDSCToMint = 9999e18;
        uint256 amountOfToDSCToBurn = 0;
        uint256 UserDSC = dSC.balanceOf(USER);
        ///Act
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        dSC.approve(address(dSCEngine), amountOfToDSCToBurn);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dSCEngine.burnDSC(amountOfToDSCToBurn);
    }

    //////////////////////////////
    ///RedeemCollateralTest///
    /////////////////////////////
    function testRedeemCollateral() external depositCollateral {
        uint256 UserBalance = ERC20Mock(wETH).balanceOf(USER);
        console.log("user balance is:%e", UserBalance);
        vm.startPrank(USER);
        dSCEngine.redeemCollateral(wETH, amountCollateral);
        UserBalance = ERC20Mock(wETH).balanceOf(USER);
        console.log("user balance is:%e", UserBalance);
    }

    function testRedeemCollateralForDSC() external depositCollateral {
        //Arrange
        uint256 amountOfDSCToMint = 9999e18;
        uint256 UserBalance = ERC20Mock(wETH).balanceOf(USER);
        uint256 UserDSC = dSC.balanceOf(USER);
        console.log("user balance is:%e", UserBalance);
        console.log("user balance is:%e", UserDSC);
        //Act/assert
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        UserDSC = dSC.balanceOf(USER);
        console.log("user balance is:%e", UserDSC);
        dSC.approve(address(dSCEngine), amountOfDSCToMint);
        dSCEngine.redeemCollateralForDSC(
            wETH,
            amountCollateral,
            amountOfDSCToMint
        );
        UserBalance = ERC20Mock(wETH).balanceOf(USER);
        console.log("user balance is:%e", UserBalance);
        UserDSC = dSC.balanceOf(USER);
        console.log("user balance is:%e", UserDSC);
    }

    function testLiquidateUser() external depositCollateral {
        //Arrange
        uint256 amountOfDSCToMint = 100e18;
        // uint256 debtToCover =
        uint256 UserBalance = ERC20Mock(wETH).balanceOf(USER);
        uint256 UserDSC = dSC.balanceOf(USER);
        uint256 LiquidatorBalance = ERC20Mock(wETH).balanceOf(LIQUIDATOR);
        uint256 LiquidatorDSC = dSC.balanceOf(LIQUIDATOR);
        console.log("user balance is:%e", UserBalance);
        console.log("user balance is:%e", UserDSC);
        //Act/assert
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        UserDSC = dSC.balanceOf(USER);
        console.log("user balance is:%e", UserDSC);
        vm.stopPrank();
        //Liquidator
        //Arrange
        uint256 LiquidatorCollateral = 20e18;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wETH).approve(address(dSCEngine), LiquidatorCollateral);
        dSCEngine.DepositCollateralAndMintDSC(
            wETH,
            LiquidatorCollateral,
            amountOfDSCToMint
        );
        LiquidatorDSC = dSC.balanceOf(LIQUIDATOR);
        console.log("user balance is:%e", LiquidatorDSC);
        vm.stopPrank();
        //Arrange
        int256 ETHUSDUpdatedPrice = 18e8;
        MockV3Aggregator(ETHUSDpriceFeed).updateAnswer(ETHUSDUpdatedPrice);
        //Act
        vm.startPrank(LIQUIDATOR);
        dSC.approve(address(dSCEngine), amountOfDSCToMint);
        dSCEngine.liquidate(wETH, USER, amountOfDSCToMint);
        UserBalance = ERC20Mock(wETH).balanceOf(USER);
        console.log("user balance is:%e", UserBalance);
        UserDSC = dSC.balanceOf(USER);
        console.log("user balance is:%e", UserDSC);
        LiquidatorBalance = ERC20Mock(wETH).balanceOf(LIQUIDATOR);
        console.log("user balance is:%e", LiquidatorBalance);
    }

    function testCantLiquidateZeroAmountCollateral()
        external
        depositCollateral
    {
        uint256 amountOfDSCToMint = 100e18;
        uint256 ZeroAmount = 0;
        // uint256 debtToCover =
        //Act/assert
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        vm.stopPrank();
        //Liquidator
        //Arrange
        uint256 LiquidatorCollateral = 20e18;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wETH).approve(address(dSCEngine), LiquidatorCollateral);
        dSCEngine.DepositCollateralAndMintDSC(
            wETH,
            LiquidatorCollateral,
            amountOfDSCToMint
        );
        vm.stopPrank();
        //Arrange
        int256 ETHUSDUpdatedPrice = 18e8;
        MockV3Aggregator(ETHUSDpriceFeed).updateAnswer(ETHUSDUpdatedPrice);
        //Act
        vm.startPrank(LIQUIDATOR);
        dSC.approve(address(dSCEngine), amountOfDSCToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dSCEngine.liquidate(wETH, USER, ZeroAmount);
    }

    function testCanLiquidateIfHealthFactorIsBad() external {
        uint256 amountOfDSCToMint = 100e18;
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        vm.stopPrank();
        //Liquidator
        //Arrange
        uint256 LiquidatorCollateral = 20e18;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wETH).approve(address(dSCEngine), amountCollateral);
        dSCEngine.DepositCollateralAndMintDSC(
            wETH,
            amountCollateral,
            amountOfDSCToMint
        );
        uint256 userhealthFactor = dSCEngine.getHealthFactor(LIQUIDATOR);
        vm.stopPrank();
        //Arrange
        int256 ETHUSDUpdatedPrice = 18e8;
        MockV3Aggregator(ETHUSDpriceFeed).updateAnswer(ETHUSDUpdatedPrice);
        userhealthFactor = dSCEngine.getHealthFactor(LIQUIDATOR);
        //Act
        vm.startPrank(LIQUIDATOR);
        dSC.approve(address(dSCEngine), amountOfDSCToMint);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                userhealthFactor
            )
        );
        dSCEngine.liquidate(wETH, USER, amountOfDSCToMint);
    }

    function testCantLiquidateAUserWithAGoodHealthFactor()
        external
        depositCollateral
    {
        uint256 amountOfDSCToMint = 100e18;
        vm.startPrank(USER);
        dSCEngine.mintDSC(amountOfDSCToMint);
        vm.stopPrank();
        //Liquidator
        //Arrange
        uint256 LiquidatorCollateral = 20e18;
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wETH).approve(address(dSCEngine), amountCollateral);
        dSCEngine.DepositCollateralAndMintDSC(
            wETH,
            amountCollateral,
            amountOfDSCToMint
        );
        uint256 userhealthFactor = dSCEngine.getHealthFactor(LIQUIDATOR);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        dSC.approve(address(dSCEngine), amountOfDSCToMint);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dSCEngine.liquidate(wETH, USER, amountOfDSCToMint);
    }
}
