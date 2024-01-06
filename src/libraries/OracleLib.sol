// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/*
 * @title OracleLib
 * @author Nihavent
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable, this is by design
 * We want the DSCEngine to freeze if prices become stale.
 */

library OracleLib {
    error OracleLib__StalePriceFeed();

    uint256 private constant TIMEOUT = 3 hours;

    function stalePriceCheckLatestRound(AggregatorV3Interface priceFeed) 
    public 
    view 
    returns(uint80, int256, uint256, uint256, uint80) 
    {
        (uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // time between last price feed update and latest block
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePriceFeed();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);

    }

}