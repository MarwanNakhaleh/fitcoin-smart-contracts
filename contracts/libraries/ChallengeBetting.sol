// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "../interfaces/IVault.sol";
import "./ChallengeData.sol";

/**
 * @title ChallengeBetting
 * @notice Library containing challenge betting functions with optimized stack usage.
 */
library ChallengeBetting {
    // Flattened storage mappings to avoid nesting
    struct BettingStorage {
        // Simple non-nested mappings
        mapping(uint256 => uint256) challengeToNumberOfBettorsFor;
        mapping(uint256 => uint256) challengeToNumberOfBettorsAgainst;
        mapping(uint256 => uint256) challengeToTotalAmountBetFor;
        mapping(uint256 => uint256) challengeToTotalAmountBetAgainst;
        mapping(uint256 => address[]) challengeToBettors;
        
        // Single flattened mapping for all bets (replaces the nested mappings)
        // Key format: keccak256(abi.encodePacked(challengeId, bettor, isBettingFor))
        mapping(bytes32 => uint256) bets;
    }

    /**
     * @notice Generates a unique key for storing bet information
     */
    function _getBetKey(uint256 _challengeId, address _bettor, bool _isBettingFor) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_challengeId, _bettor, _isBettingFor));
    }

    /**
     * @notice Gets the bet amount for a specific bettor
     */
    function getBetAmount(
        uint256 _challengeId, 
        address _bettor, 
        bool _isBettingFor,
        BettingStorage storage bs
    ) internal view returns (uint256) {
        bytes32 key = _getBetKey(_challengeId, _bettor, _isBettingFor);
        return bs.bets[key];
    }

    /**
     * @notice Checks if the bet amount meets the minimum USD value requirement.
     */
    function isBetAmountValid(
        uint256 _betAmount,
        uint256 _ethPrice, 
        uint256 _minimumUsdValueOfBet
    ) internal pure returns (bool) {
        return (_betAmount * _ethPrice) / 1e8 >= _minimumUsdValueOfBet;
    }

    /**
     * @notice Processes a bet for or against a challenge.
     */
    function processBet(
        uint256 _challengeId,
        bool _bettingFor,
        uint256 _betAmount,
        address _bettor,
        IVault _vault,
        BettingStorage storage bs
    ) internal {
        _vault.depositETH{value: _betAmount}();

        bytes32 betKey = _getBetKey(_challengeId, _bettor, _bettingFor);
        bs.bets[betKey] = _betAmount;
        
        if (_bettingFor) {
            bs.challengeToNumberOfBettorsFor[_challengeId] += 1;
            bs.challengeToTotalAmountBetFor[_challengeId] += _betAmount;
        } else {
            bs.challengeToNumberOfBettorsAgainst[_challengeId] += 1;
            bs.challengeToTotalAmountBetAgainst[_challengeId] += _betAmount;
        }

        bs.challengeToBettors[_challengeId].push(_bettor);
    }

    /**
     * @notice Validates that a bet can be cancelled.
     */
    function validateBetCancellation(
        uint256 _challengeId,
        address _bettor,
        uint8 _challengeStatus,
        BettingStorage storage bs
    ) internal view {
        uint256 betAmountFor = getBetAmount(_challengeId, _bettor, true, bs);
        uint256 betAmountAgainst = getBetAmount(_challengeId, _bettor, false, bs);
        
        if (betAmountFor == 0 && betAmountAgainst == 0) {
            revert ChallengeData.BettorCannotUpdateBet();
        }
        if (_challengeStatus != ChallengeData.STATUS_INACTIVE) {
            revert ChallengeData.ChallengeCannotBeModified();
        }
    }

    /**
     * @notice Validates that a bet can be changed.
     */
    function validateBetChange(
        uint256 _challengeId,
        address _bettor,
        uint256 _newBetAmount,
        uint256 _minimumUsdValueOfBet,
        uint8 _challengeStatus,
        BettingStorage storage bs
    ) internal view {
        uint256 betAmountFor = getBetAmount(_challengeId, _bettor, true, bs);
        uint256 betAmountAgainst = getBetAmount(_challengeId, _bettor, false, bs);
        
        if (betAmountFor == 0 && betAmountAgainst == 0) {
            revert ChallengeData.BettorCannotUpdateBet();
        }
        if (_newBetAmount < _minimumUsdValueOfBet) {
            revert ChallengeData.MinimumBetAmountTooSmall();
        }
        if (_challengeStatus != ChallengeData.STATUS_INACTIVE) {
            revert ChallengeData.ChallengeCannotBeModified();
        }
    }

    /**
     * @notice Determines if a challenge was won or lost based on metrics.
     */
    function determineChallengeOutcome(
        uint256 _challengeId,
        mapping(uint256 => uint8[]) storage _challengeToIncludedMetrics,
        mapping(uint256 => mapping(uint8 => uint256)) storage _challengeToFinalMetricMeasurements,
        mapping(uint256 => mapping(uint8 => uint256)) storage _challengeToTargetMetricMeasurements
    ) internal view returns (bool) {
        uint8[] memory metrics = _challengeToIncludedMetrics[_challengeId];
        for (uint8 i = 0; i < metrics.length; i++) {
            uint8 metricType = metrics[i];
            if (_challengeToFinalMetricMeasurements[_challengeId][metricType] < 
                _challengeToTargetMetricMeasurements[_challengeId][metricType]) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Updates the challenge status based on the outcome.
     */
    function updateChallengeStatus(
        uint256 _challengeId,
        bool _challengeWon,
        mapping(uint256 => uint8) storage _challengeToChallengeStatus
    ) internal {
        _challengeToChallengeStatus[_challengeId] = _challengeWon ? 
            ChallengeData.STATUS_CHALLENGER_WON : 
            ChallengeData.STATUS_CHALLENGER_LOST;
    }

    /**
     * @notice Calculates the distribution amounts.
     */
    function calculateDistributionAmounts(
        uint256 _challengeId,
        bool _challengeWon,
        BettingStorage storage bs
    ) internal view returns (uint256 winningPool, uint256 totalCorrectBets, bool shouldDistribute) {
        if (_challengeWon) {
            winningPool = bs.challengeToTotalAmountBetAgainst[_challengeId];
            totalCorrectBets = bs.challengeToTotalAmountBetFor[_challengeId];
        } else {
            winningPool = bs.challengeToTotalAmountBetFor[_challengeId];
            totalCorrectBets = bs.challengeToTotalAmountBetAgainst[_challengeId];
        }
        shouldDistribute = (totalCorrectBets > 0);
    }

    /**
     * @notice Gets the total number of bettors for a given challenge.
     */
    function getBettorsCount(
        uint256 _challengeId,
        BettingStorage storage bs
    ) internal view returns (uint256) {
        return bs.challengeToBettors[_challengeId].length;
    }

    /**
     * @notice Processes a single bettor's winnings.
     */
    function processSingleBettor(
        uint256 _challengeId,
        uint256 _bettorIndex,
        bool _challengeWon,
        uint256 _winningPool, 
        uint256 _totalCorrectBets,
        IVault _vault,
        BettingStorage storage bs
    ) internal returns (address processedBettor) {
        address[] storage bettors = bs.challengeToBettors[_challengeId];
        if (_bettorIndex >= bettors.length) {
            return address(0);
        }
        
        address bettor = bettors[_bettorIndex];
        uint256 betAmount = getBetAmount(_challengeId, bettor, _challengeWon, bs);
        
        if (betAmount > 0) {
            uint256 share = (betAmount * _winningPool) / _totalCorrectBets;
            try _vault.withdrawFunds(payable(bettor), betAmount + share, false) {} catch {}
        }
        return bettor;
    }

    /**
     * @notice Processes a small batch of bettors.
     */
    function processSmallBatch(
        uint256 _challengeId,
        uint256 _startIndex,
        uint256 _count,
        bool _challengeWon,
        uint256 _winningPool, 
        uint256 _totalCorrectBets,
        IVault _vault,
        BettingStorage storage bs
    ) internal returns (uint256 lastProcessedIndex) {
        address[] storage bettors = bs.challengeToBettors[_challengeId];
        uint256 bettorsLength = bettors.length;
        uint256 endIndex = _startIndex + _count;
        if (endIndex > bettorsLength) {
            endIndex = bettorsLength;
        }
        
        for (uint256 i = _startIndex; i < endIndex;) {
            address bettor = bettors[i];
            uint256 betAmount = getBetAmount(_challengeId, bettor, _challengeWon, bs);
            
            if (betAmount > 0) {
                uint256 share = (betAmount * _winningPool) / _totalCorrectBets;
                try _vault.withdrawFunds(payable(bettor), betAmount + share, false) {} catch {}
            }
            unchecked { i++; }
        }
        
        return endIndex - 1;
    }
}
