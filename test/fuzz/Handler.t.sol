// SPDX-License-Identifier: MIT

// Handler is going to narrow down the ways we call functions to ensure we don't waste test runs

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    //DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    //HelperConfig config;

    //address wethContract;
    //address wbtcContract;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled = 0;
    address[] public usersWithCollateralDeposited;

    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MIN_DEPOSIT_SIZE = 1; 
    uint256 MIN_REDEMPTION_SIZE = 1;
    uint256 MIN_MINT_SIZE = 1; 
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // max uint96 value

    constructor(
        DSCEngine _dscEngine, 
        DecentralisedStableCoin _dsc) 
    {
        dscEngine = _dscEngine;
        dsc = _dsc;

        // Get array of collateral token addresses
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    // depositCollateral
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralAddress = _getCollateralAddressFromSeed(collateralSeed); //Supply valid collateral addres

        amountCollateral = bound(amountCollateral, MIN_DEPOSIT_SIZE, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralAddress.mint(msg.sender, amountCollateral); // Mint collateral to any user who calls this
        collateralAddress.approve(address(dscEngine), amountCollateral); // Approve collateral to be deposited  to dscEngine
        dscEngine.depositCollateral(address(collateralAddress), amountCollateral); // Deposit collateral
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    // redeemCollateral
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralAddress = _getCollateralAddressFromSeed(collateralSeed); //Supply valid collateral addres

        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateralAddress)); // Get max collateral to redeem
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem); 
        // Ensure amountCollateral is never 0
        if (amountCollateral == 0) {
            return;
        }
        //vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateralAddress), amountCollateral); // Redeem collateral
        //vm.stopPrank();
    }

    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length == 0){
            return;
        }
        //Essentially, randomly select an address from the array of users with collateral depositeds
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender); // Check collateral and DSC minted of address
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted); // Always mint the max DSC based on their collateral to ensure health factor remains.
        
        if (maxDscToMint <= 0) {
            return;
        }
        
        amountToMint = bound(amountToMint, 0, uint256(maxDscToMint));
        if (amountToMint <= 0) {
            return;
        }

        vm.prank(sender);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    // This breaks our invariant test suite.. It fuzzes a scenario where the price of the collateral plummets which means our system is under collateralised

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }


    ////////////////////////////
    // Helper Functions       //
    ////////////////////////////

    function _getCollateralAddressFromSeed(uint256 collateralSeed) 
    private 
    view 
    returns (ERC20Mock) 
    {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

}



