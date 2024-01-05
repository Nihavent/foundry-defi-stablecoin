// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
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

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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




}
