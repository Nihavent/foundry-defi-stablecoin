// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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
// view & pure functions

pragma solidity 0.8.20;

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
 * @notice This cokntract is the core of the DSC System. It handles all the logic for mining and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is loosely based on the MakerDAO DSS (DAI) system
 * 
 */

contract DSCEngine {

}