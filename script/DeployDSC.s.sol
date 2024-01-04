// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralisedStableCoin} from "../src/DecentralisedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";


contract DeployDSC is Script {

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    
    function run() external 
    returns (
        DecentralisedStableCoin, 
        DSCEngine)
    {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, 
        address wbtcUsdPriceFeed, 
        address wethContract, 
        address wbtcContract,
        uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [wethContract, wbtcContract];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        DecentralisedStableCoin dsc = new DecentralisedStableCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        dsc.transferOwnership(address(engine)); // By default, the caller of the DeployDSC contract will be the owner of the DSC contract. We want to transfer this to the engine address

        vm.stopBroadcast();

        return (dsc, engine);
    }
}