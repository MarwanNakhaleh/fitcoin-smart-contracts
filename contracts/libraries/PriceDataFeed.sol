// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "./ChallengeData.sol";

/**
 * @title PriceDataFeed
 * @notice Library containing price data feed functions
 */
library PriceDataFeed {
    using ChallengeData for *;
    // ============================ //
    //      Contract Functions      //
    // ============================ //

    function getLatestPrice(AggregatorV3Interface dataFeed) public view returns (uint256) {
        (
            uint80 roundId,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = dataFeed.latestRoundData();

        // Check for stale data
        if (timeStamp <= 0) {
            revert ChallengeData.PriceFeedRoundNotComplete();
        }
        if (answeredInRound < roundId) {
            revert ChallengeData.StalePrice();
        }

        // Check if the price feed is stale (older than 24 hours)
        if (block.timestamp - timeStamp > 24 hours) {
            revert ChallengeData.PriceFeedTooOld();
        }

        // Price must be positive
        if (price < 0) {
            revert ChallengeData.InvalidPrice();
        }

        return uint256(price) * 1e6;
    }
}
