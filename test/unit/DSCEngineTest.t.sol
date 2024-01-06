// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";



contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address wethContract;
    address wbtcContract;

    //variables for mocking FailedTransferFrom
    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);


    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, wethContract, wbtcContract, ) = config.activeNetworkConfig();

        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(wethContract).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtcContract).mint(user, STARTING_USER_BALANCE);
    }


    ////////////////////////////
    // Constructor Tests      //
    ////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeedLength() public {
        tokenAddresses.push(wethContract);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }


    ////////////////////////////
    // Price Feed Tests       //
    ////////////////////////////


    // Tests that the USD value of a token and amount of that token matches expected value
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        // This $2000/ETH comes from our default price setup on the Anvil chain in HelperConfig.s.sol
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(wethContract, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    // Tests that the amount of some token calculates correctly given a token and USD amount
    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // Say $2000 USD/ETH, how much eth is $100 usd?
        // = 100 USD / (2000 USD / ETH)  = 0.05 ETH
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(wethContract, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////////
    // Deposit Collateral Tests       //
    ////////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(user);
        //Not sure what the following is doing, why does the dscEngine need collateral for this test?
        ERC20Mock(wethContract).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(wethContract, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock newToken = new ERC20Mock("RAN", "RAN", user, STARTING_ERC20_BALANCE);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(newToken), STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }
    
    //Modifier to deposit collateral
    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethContract, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(wethContract, collateralValueInUsd);
        
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    //Test to ensure the s_collateralDeposited mapping updates correctly after depositing collateral
    //This is already tested implicitly in the testCanDepositCollateralAndGetAccountInfo test
    function testDepositCollateral() public depositCollateral {
        uint256 expectedBalance = AMOUNT_COLLATERAL;
        uint256 actualBalance = dscEngine.getCollateralDepositedInTokenAmount(user, address(wethContract));
        assertEq(expectedBalance, actualBalance);
    }

    // Do not use deposit modifier, we set this up manually
    // Followed the example here: https://book.getfoundry.sh/cheatcodes/expect-emit
    // This test is to ensure that the CollateralDeposited event is emitted when collateral is deposited
    // We had to import define the CollateralDeposited event in this contract.abi
    // The vm.expectEmit() function takes arguments indicating which events we want to check for, along with an address we expect the events to be emitted by
    function testEmitsEventOnDeposit() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false, address(dscEngine));
        emit CollateralDeposited(user, wethContract, AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(wethContract, AMOUNT_COLLATERAL);
    }

    // this test needs it's own setup
    // The MockFailedTransferFrom contract is used to mock a failed transferFrom call because it won't fail earlier like the original contract. The original contract fails earlier due to checking if an address has enough of a token token to send, which means we can never reach our expected revert: DSCEngine.DSCEngine__TransferFailed
    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        //Setup new DSCEngine with mockDsc
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(user, amountCollateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

    function testCanDepositCollateralWithoutMinting() public depositCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

    // Modifier to depositCollateralAndMintDsc
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }    

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), AMOUNT_COLLATERAL);

        //We need to calculate an amount of Dsc to mint that will break the health factor
        //In order to do that we need to determine USD value of collateral
        uint256 collateralValueUsd = dscEngine.getUsdValue(wethContract, AMOUNT_COLLATERAL);

        //This needs to break the health factor, so try 1:1 ratio
        uint256 amountDscToMint = collateralValueUsd;

        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(amountDscToMint, collateralValueUsd);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.depositCollateralAndMintDsc(wethContract, AMOUNT_COLLATERAL, amountDscToMint);
        vm.stopPrank();
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////


    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [wethContract];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(mockDsce), amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositCollateral {
        vm.prank(user);
        dscEngine.mintDsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        dscEngine.burnDsc(1);
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), amountToMint);
        console.log(amountToMint);
        console.log(dsc.balanceOf(user));
        dscEngine.burnDsc(amountToMint);
        console.log(dsc.balanceOf(user));
        vm.stopPrank();

        assertEq(dsc.balanceOf(user), 0);
    }


    ///////////////////////////////////
    // redeemCollateral Tests        //
    ///////////////////////////////////

    function testRevertsIfTransferFails() public {
        // Arrange - Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.mint(user, amountCollateral);

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce), amountCollateral);
        // Act / Assert
        mockDsce.depositCollateral(address(mockDsc), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc), amountCollateral);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(wethContract, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositCollateral {
        vm.startPrank(user);
        dscEngine.redeemCollateral(wethContract, amountCollateral);
        uint256 userBalance = ERC20Mock(wethContract).balanceOf(user);
        assertEq(userBalance, amountCollateral);
        vm.stopPrank();
    }

    function testEmitCollateralRedeemedEventWithCorrectArgs() public depositCollateral {
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(user, user, wethContract, amountCollateral);
        vm.startPrank(user);
        dscEngine.redeemCollateral(wethContract, amountCollateral);
        vm.stopPrank();
    }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dscEngine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateralForDsc(wethContract, 0, amountToMint);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.redeemCollateralForDsc(wethContract, amountCollateral, amountToMint);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.getHealthFactor(user);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Rememeber, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) = 0.9
        assert(userHealthFactor == 0.9 ether);
    }



    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    // This test needs it's own setup
    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
        tokenAddresses = [wethContract];
        priceFeedAddresses = [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(mockDsce), amountCollateral);
        mockDsce.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.stopPrank();

        // Arrange - Liquidator
        collateralToCover = 1 ether;
        ERC20Mock(wethContract).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(wethContract).approve(address(mockDsce), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockDsce.depositCollateralAndMintDsc(wethContract, collateralToCover, amountToMint);
        mockDsc.approve(address(mockDsce), debtToCover);
        // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(wethContract, user, debtToCover);
        vm.stopPrank();
    }


    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(wethContract).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(wethContract).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(wethContract, collateralToCover, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        // We try to liquidate a user who has a good health factor based on setup done in depositedCollateralAndMintedDsc
        dscEngine.liquidate(wethContract, user, amountToMint);
        vm.stopPrank();
    }

    modifier liquidated() {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.stopPrank();
        //Simulate ETH decreasing in price significantlys
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);

        ERC20Mock(wethContract).mint(liquidator, collateralToCover);

        console.log(liquidator);
        vm.startPrank(liquidator);
        ERC20Mock(wethContract).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(wethContract, collateralToCover, amountToMint);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.liquidate(wethContract, user, amountToMint); // We are covering their whole debt
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        console.log(dscEngine.getHealthFactor(liquidator));

        uint256 liquidatorWethBalance = ERC20Mock(wethContract).balanceOf(liquidator);
        uint256 expectedWeth = dscEngine.getTokenAmountFromUsd(wethContract, amountToMint)
            + (dscEngine.getTokenAmountFromUsd(wethContract, amountToMint) / dscEngine.getLiquidationBonus());
        uint256 hardCodedExpected = 6111111111111111110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }


    function testLiquidated() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateralAndMintDsc(wethContract, amountCollateral, amountToMint);
        vm.stopPrank();
        //Simulate ETH decreasing in price significantlys
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dscEngine.getHealthFactor(user);
        console.log(userHealthFactor); // 0.9
        ERC20Mock(wethContract).mint(liquidator, collateralToCover);

        console.log(address(liquidator));
        vm.startPrank(liquidator);
        ERC20Mock(wethContract).approve(address(dscEngine), collateralToCover);
        dscEngine.depositCollateralAndMintDsc(wethContract, collateralToCover, amountToMint);
        // DSC balance of liquidator
        console.log(dsc.balanceOf(liquidator)/1 ether);
        dsc.approve(address(dscEngine), amountToMint);
        console.log(wethContract);
        console.log(user);
        console.log(amountToMint);
        dscEngine.liquidate(wethContract, user, amountToMint); // We are covering their whole debt
        //vm.stopPrank();
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dscEngine.getTokenAmountFromUsd(wethContract, amountToMint)
            + (dscEngine.getTokenAmountFromUsd(wethContract, amountToMint) / dscEngine.getLiquidationBonus());

        uint256 usdAmountLiquidated = dscEngine.getUsdValue(wethContract, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dscEngine.getUsdValue(wethContract, amountCollateral) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = dscEngine.getAccountInformation(user);
        uint256 hardCodedExpectedValue = 70000000000000000020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dscEngine.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dscEngine.getAccountInformation(user);
        assertEq(userDscMinted, 0);
    }


    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////
    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(wethContract);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], wethContract);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositCollateral {
        (, uint256 collateralValue) = dscEngine.getAccountInformation(user);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(wethContract, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(wethContract, amountCollateral);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(user, wethContract);
        assertEq(collateralBalance, amountCollateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(wethContract).approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(wethContract, amountCollateral);
        vm.stopPrank();
        uint256 collateralValue = dscEngine.getAccountCollateralValue(user);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(wethContract, amountCollateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public {
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dscEngine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }

}
