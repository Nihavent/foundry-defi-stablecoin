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

contract DSCEngine {

    ////////////////////////////
    // Errors                 //
    ////////////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();

    ////////////////////////////
    // State Variables        //
    ////////////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed

    DecentralisedStableCoin private immutable i_dsc;

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
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    ////////////////////////////
    // External Functions     //
    ////////////////////////////

    function depositCollateralAndMintDsc() external {}

    /* 
     * @param tokenCollateralAddress The address of the token tok deposit as collateral
     * @param amountcollateral The amount of collateral to deposit
     */

    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) external 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress) {

    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}