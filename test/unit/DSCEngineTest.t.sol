// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address wethContract;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, , wethContract, , ) = config.activeNetworkConfig();

        ERC20Mock(wethContract).mint(USER, STARTING_ERC20_BALANCE);

    }


    ////////////////////////////
    // Price Feed Tests       //
    ////////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(wethContract, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }


    ////////////////////////////////////
    // Deposit Collateral Tests       //
    ////////////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        //Not sure what the following is doing, why does the dscEngine need collateral for this test?
        ERC20Mock(wethContract).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(wethContract, 0);
        vm.stopPrank();

    }


}