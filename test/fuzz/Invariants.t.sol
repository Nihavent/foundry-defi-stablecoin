// SPDX-License-Identifier: MIT

// Have our invariant properties

// What are our invariants?
// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralisedStableCoin} from "../../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    Handler handler;

    address wethContract;
    address wbtcContract;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (, , wethContract, wbtcContract, ) = config.activeNetworkConfig();

        //targetContract(address(dscEngine)); //In our open invariants test the target was the dscEngine contract address
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler)); //Now the target is the handler contract address
    }

    function invariant_protocolMustHaveMoreValueThanTotalsupply() public view {
        // Get value of all the collateral in protocol
        // compare it to all the debt (dsc)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(wethContract).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtcContract).balanceOf(address(dscEngine));

        //Get USD value of collateral
        uint256 totalWethCollateralValue = dscEngine.getUsdValue(wethContract, totalWethDeposited);
        uint256 totalWbtcCollateralValue = dscEngine.getUsdValue(wbtcContract, totalWbtcDeposited);
        
        console.log("totalWethCollateralValue: ", totalWethCollateralValue);
        console.log("totalWbtcCollateralValue: ", totalWbtcCollateralValue);
        console.log("totalSupply: ", totalSupply);
        console.log("timesMintIsCalled: ", handler.timesMintIsCalled());

        assert(totalWethCollateralValue + totalWbtcCollateralValue >= totalSupply);
    }

    function invariant_gettersShouldNotRever() public view {
        dscEngine.getPrecision();
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getLiquidationThreshold();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationPrecision();
        dscEngine.getMinHealthFactor();
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
        dscEngine.getCollateralTokenPriceFeed(wethContract);
        dscEngine.getCollateralTokenPriceFeed(wbtcContract);
        dscEngine.getCollateralBalanceOfUser(msg.sender, wethContract);
        dscEngine.getCollateralBalanceOfUser(msg.sender, wbtcContract);
        dscEngine.getHealthFactor(msg.sender);
        dscEngine.getPrecision();
        dscEngine.getPrecision();
        dscEngine.getPrecision();
        dscEngine.getPrecision();
    }

}
