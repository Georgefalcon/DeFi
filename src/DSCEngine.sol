// SPDX-License-Identifier: SEE LICENSE IN LICENSE
// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts

// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

///////////////
///Imports/////
/////////////
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleLibrary, AggregatorV3Interface} from "./Libraries/OracleLibrary.sol";

pragma solidity 0.8.22;

/**
 * @title DSCEngine
 * @author GeorgeFalcon
 *
 * The system is designed to be as minimal as possible, and have the token maintain a 1 token == 1$ peg
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * It is smilar to DAI, if DAI had no governance,no fees, and was only backed by WETH and WBTC.
 * 
 *Our DSC system should always be "overcollaterized". At no point , should the value of all collateral be <= the $backed value of all the DSC

 * @notice This contract is the core of the DSC system. it handles all the logic for mining and redeeming  DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////
    ///Errors/////
    /////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressandPriceFeedAddressMustBeTheSameLength();
    error DSCEngine__NotAllowedToken(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////
    using OracleLibrary for AggregatorV3Interface;

    //////////////
    ///State variable/////
    /////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATORS_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /// @dev Mapping of token address to price feed address
    mapping(address CollateralToken => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address CollateralToken => uint256 amount))
        private s_CollateralDeposited;
    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    address[] private s_CollateralTokens;
    /// @dev If we know exactly how many tokens we have, we could make this immutable!
    DecentralizedStableCoin private immutable i_DSC;

    //////////////
    ///Events/////
    /////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralReddemed(
        address indexed from,
        address indexed to,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    ///////////////
    ///Modifiers/////
    /////////////
    modifier MoreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken(token);
        }
        _;
    }

    ///////////////
    ///Constructors/////
    /////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address DSCAddress
    ) {
        // USD priceFeed
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressandPriceFeedAddressMustBeTheSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_CollateralTokens.push(tokenAddresses[i]);
        }
        i_DSC = DecentralizedStableCoin(DSCAddress);
    }

    ///////////////
    ///External/////
    /////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to be deposited
     * @param amountCollateral The amount of collateral deposited
     * @param amountDSCToMint The amount of decentralized stable coin to mint
     * @notice This function would deposit your collateral and mint your DSC at one transaction
     *
     */
    function DepositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        DepositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice follows CEI (CHECKS|EFFECTS|INTERACTIONS)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of Collateral to deposit
     */
    function DepositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        MoreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    // nonReentrant
    {
        // revert("debug");
        s_CollateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (success != true) {
            revert DSCEngine__TransferFailed();

            emit CollateralDeposited(
                msg.sender,
                tokenCollateralAddress,
                amountCollateral
            );
        }
    }

    //  In order to redeem CollateralDeposited
    //  Health factor must be over one AFTER collateral pulled
    //  DRY: Don't Repeat Yourself
    //  CEI: checks,effects,interactions
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    /**
     * @param tokenCollateralAddress The tokenCollateral to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDSCToBurn The amount of DSC to burn
     * This function burns and redeem the underlying collateral in one transaction
     */
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // reddemCollatera already check health factor
    }

    /**
     * @notice Follows CEI
     * @param amountDSCToMint; the amount of decentralized Stable coin to mint
     * @notice They must have more collateral than the minimum threshold value
     */
    function mintDSC(
        uint256 amountDSCToMint
    ) public MoreThanZero(amountDSCToMint) nonReentrant {
        //if they minted too much ($150DSC,$100ETH)
        _revertHealthFactorIsBroken(msg.sender);
        bool minted = i_DSC.mint(msg.sender, amountDSCToMint);
        if (minted != true) {
            revert DSCEngine__MintFailed();
        }
        s_DSCMinted[msg.sender] += amountDSCToMint;
    }

    function burnDSC(uint256 amount) public MoreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
    }

    /**
     * @param collateral the erc20 collateral address to liquidate from the user;
     * @param user The user who has broken the health factor. their _healthFactor should be below MIN_HEALTH_FACTOR
     *  In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param debtToCover The amount of DSC you want to burn to improve users health factor
     * @notice You can partially liquidate a user
     * @notice you will get a liquidation bonus for taking a user funds
     * @notice This function working assumes the protocol will be roughly 200% overCollaterized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collaterized , then we wouldn't be able to incentive the liquidators
     * For example, if the price of the collateral plummeted before anyone could be liquidated
     *
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external MoreThanZero(debtToCover) nonReentrant {
        _revertHealthFactorIsBroken(msg.sender);
        // Needs to check the healthfactor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // we want to burn their DSC debt
        // we want to take their Collateral
        // Bad User: $140 ETH ,$100 DSC
        // debtToCover = $100
        // $100 of DSC == ??? ETH?
        //0.05ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(
            collateral,
            debtToCover
        );
        // and give them a 10% bonus
        // so we are giving the liquidator  $110 of wETH for 100 DSC
        // we should implement a feature to liquidate in the event the protocol is insolvent
        // and sweep extra amounts into a treasury
        // 0.05 * 0.1 = 0.005. Get 0.055
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATORS_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralRedeemed
        );
        _burnDSC(debtToCover, user, msg.sender);
        uint256 endingUserHealthfactor = _healthFactor(user);
        if (endingUserHealthfactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
            _revertHealthFactorIsBroken(msg.sender);
        }
        _revertHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external {}

    /////////////////////////////////////////
    ///Private & Internal view functions/////
    ////////////////////////////////////////
    /**
     * @dev Low Level internal function, do not call unless the function calling it is
     * checking for health factors being broken
     */
    function _burnDSC(
        uint256 amountOfDSCToBurn,
        address OnBehalf,
        address DSCFrom
    ) private {
        s_DSCMinted[OnBehalf] -= amountOfDSCToBurn;
        bool success = i_DSC.transferFrom(
            DSCFrom,
            address(this),
            amountOfDSCToBurn
        );
        // This condition is hypothetical unreachable
        if (success != true) {
            revert DSCEngine__TransferFailed();
            i_DSC.burn(amountOfDSCToBurn);
            _revertHealthFactorIsBroken(msg.sender); // probably wouldn't get to this to this point
        }
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (success != true) {
            revert DSCEngine__TransferFailed();
        }
        s_CollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralReddemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    function _getUSDValue(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // immagine the price of 1 ETH = $1000
        // the value returned by chainlink would be (1000 * 1e8) where 8 represent it's decimal
        //let say the amount of ETH you posses is 5000, in order to get the correct price of your amount you need to multiple the price by an exponenet 1e10 ,for accurate price precision
        // (1000 * 1e8) * 5000 * 1e18  ==> (1000 * 1e8 * 1e10) * 5000 * 1e18
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /**
     * Returns how close to liquidation, a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral value in USD
        (
            uint256 totalDSCMinted,
            uint256 collateralValueInUSD
        ) = _getAccountInformation(user);
        // $1000 worth ETH for 100DSC
        //(1000 * 50)/100 = 500
        //500/100 > 1 (overCollaterized)

        // $150 worth ETH for 100DSC
        //(150 *50)/100 = 75
        //75/100 < 1 (undercollaterized)
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 CollateralAdjustedForThreshold = (collateralValueInUSD *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (CollateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    // 1. chek healthFactor (do they have enough collateral);
    // 2. Revet if they don't
    function _revertHealthFactorIsBroken(address user) internal view {
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userhealthFactor);
        }
    }

    ///////////////
    ///Public & External view functions/////
    /////////////
    //price of ETH (token)

    function getTokenAmountFromUSD(
        address tokenCollateral,
        uint256 USDAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[tokenCollateral]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        //  price of ETH (token)
        // $/ETH ETH??
        //$2000/ETH.
        // AMOUNT OF TOKEN : AMOUNT * ETH/PRICE OF ETH
        return
            (USDAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUSD) {
        // loop through each token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < s_CollateralTokens.length; i++) {
            address token = s_CollateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralValueInUSD += _getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(
        address token,
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUSDValue(token, amount);
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    //GETTER
    function getMintedDSCAmount(
        address user,
        uint256 amountDSCToMint
    ) external returns (uint256) {
        return s_DSCMinted[user];
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralToken() external view returns (address[] memory) {
        return s_CollateralTokens;
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_CollateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }
}
