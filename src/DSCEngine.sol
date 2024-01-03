// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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
// view & pure functions

pragma solidity 0.8.20;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from  "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/*
 * @title DSCEngine
 * @author Nihavent
 * The systsem is designed to be minimal and maintain a peg to the USD
 * This stablecoin has the following properties:
 * -Exogenous collateral
 * -Dollar pegged
 * -Algorithmically stable
 * -Similar to DAI if DAI had no governance, no feeds, and only backed by WETH and WBTC
 * 
 * Our DSC system should always be "overcollateralised". At no point should the value of all collateral be less than the value of all DSC
 * 
 * @notice This cokntract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is loosely based on the MakerDAO DSS (DAI) system
 * 
 */

contract DSCEngine is ReentrancyGuard {

    ////////////////////////////
    // Errors                 //
    ////////////////////////////

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);

    ////////////////////////////
    // State Variables        //
    ////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // requirement to be 200% overcollateralised - because 50/100 = 1/2 so we're checking if the ratio of collateral to DSC is over 2:1
    uint256 private constant LIQUIDATION_PRECISION = 100; 
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // Mapping to a mapping, ie. nested mapping with each user address mapping to a mapping of tokens and values. ie. one address can have multiple different collateral deposited.
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;

    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;


    ////////////////////////////
    // Events                 //
    ////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////////////
    // Modifiers              //
    ////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        // If the toekn isn't allowed, then revert
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }



    ////////////////////////////
    // Functions              //
    ////////////////////////////
    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // Check the input length of tokenAddresses and priceFeedAddresses are the sames
        if (tokenAddresses.length != priceFeedAddresses.length){
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // Loop through inputs and add them to mapping
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    ////////////////////////////
    // External Functions     //
    ////////////////////////////

    function depositCollateralAndMintDsc() external {}

    /* 
     * @notice follows CEI - checks / effects / interactions
     * @param tokenCollateralAddress: The address of the token tok deposit as collateral
     * @param amountcollateral: The amount of collateral to deposit
     */

    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) external 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /* 
     * @notice follows CEI - checks / effects / interactions
     * @param amountDscToMint: The amount of decentralised stablecoin to mint
     * @notice they must have more collateral value than the minimum theshold
     */

    function mintDsc(
        uint256 amountDscToMint
    ) external 
        moreThanZero(amountDscToMint) 
        nonReentrant 
    {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}



    ///////////////////////////////////////////
    // Private & Internal View Functions     //
    ///////////////////////////////////////////


    function _getAccountInformation(address user) 
    private
    view 
    returns (
        uint256 totalDscMinted, 
        uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    } 

    /*
     * Returns how close to liquidation a user is.
     * If a user has a health factor of < 1 then they can get liquidated
     */
    function _healthFactor(address user) 
    private 
    view 
    returns (uint256 healthFactor) 
    {
        // total DSC minted
        // total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION / totalDscMinted);
    }

    // 1. Check health factor (do they have enough collateral)
    // 2. Revert if they don't
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }


    ////////////////////////////////////////////
    // Public & External View Functions       //
    ////////////////////////////////////////////

    function getAccountCollateralValue(address user) 
    public 
    view 
    returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token, get the amount they have deposited, and map it to the price to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // If 1 ETH = $1,000, the returned value from Chainlink will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }


}