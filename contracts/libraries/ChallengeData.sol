// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @title ChallengeData
 * @notice Library containing challenge constants and custom errors
 */
library ChallengeData {
    // ============================ //
    //             Enums            //
    // ============================ //

    /**
     * @dev Enumerated values representing the type of health challenges available
     */
    uint8 constant CHALLENGE_STEPS = 0;
    uint8 constant CHALLENGE_MILEAGE = 1;
    uint8 constant CHALLENGE_CYCLING_MILEAGE = 2;
    uint8 constant CHALLENGE_CALORIES_BURNED = 3;

    /**
     * @dev Enumerated values representing the status of a challenge
     */
    uint8 constant STATUS_INACTIVE = 0;
    uint8 constant STATUS_ACTIVE = 1;
    uint8 constant STATUS_EXPIRED = 2;
    uint8 constant STATUS_CHALLENGER_WON = 3;
    uint8 constant STATUS_CHALLENGER_LOST = 4;

    /// @notice the minimum number of total bettors on a challenge
    uint256 constant MINIMUM_NUMBER_OF_BETTORS_AGAINST = 1;

    // ============================ //
    //           Errors             //
    // ============================ //

    // errors for owner
    /// @dev error thrown when the vault is not set
    error VaultNotSet();

    /// @dev error thrown when the challenge length is too short
    error ChallengeLengthTooShort();

    /// @dev error thrown when the maximum number of bettors per challenge is too small
    error MaximumNumberOfBettorsPerChallengeTooSmall();

    /// @dev error thrown when the maximum number of challenge metrics is too small
    error MaximumNumberOfChallengeMetricsTooSmall();

    /// @dev error thrown when the minimum USD value of a bet is too small
    error MinimumUsdValueOfBetTooSmall();

    // errors for challengers
    /// @dev Error thrown when a non-whitelisted address attempts to do a challenger action
    error ChallengerNotInWhitelist();

    /// @dev Error thrown when attempting to whitelist an address already whitelisted as a challenger
    error ChallengerAlreadyInWhitelist();

    /// @dev Error thrown when a non-whitelisted address attempts to do a bettor action
    error BettorNotInWhitelist();

    /// @dev Error thrown when attempting to whitelist an address already whitelisted as a bettor
    error BettorAlreadyInWhitelist();

    /// @dev Error thrown when attempting to set a zero amount for the minimum USD value of a bet
    error MinimumBetAmountTooSmall();

    /// @dev Error thrown when a challenge is no longer allowed to be modified
    error ChallengeCannotBeModified();

    /// @dev Error thrown when a challenge is no longer allowed to be modified
    error ChallengeCanOnlyBeModifiedByChallenger(
        uint256 challengeId,
        address caller,
        address challenger
    );

    /// @dev Error thrown when a challenge is already active when it must be inactive for the action requested
    error ChallengeIsActive(uint256 activeChallengeId);

    /// @dev Error thrown when a challenge is not active when it must be active for the action requested
    error ChallengeIsNotActive(uint256 challengeId, uint8 challengeStatus);

    /// @dev Error thrown when a challenge is expired when it must not be expired for the action requested
    error ChallengeIsExpired(uint256 challengeId);

    /// @dev Error thrown when a challenge has not yet started when it must be active or complete for the action requested
    error ChallengeNotYetStarted(uint256 challengeId);

    /// @dev Error thrown when there is a mismatch between the number of challenge metrics and the number of measurements provided
    error MalformedChallengeMetricsProvided();

    /// @dev Error thrown when a challenge doesn't have anyone betting against it yet
    error NobodyBettingAgainstChallenger();

    /// @dev Error thrown when a challenge doesn't have anyone betting for it yet
    error NobodyBettingForChallenger();

    /// @dev Error thrown when a challenger attempts to bet against himself
    error ChallengerCannotBetAgainstHimself();

    /// @dev Error thrown when someone attempts to place a new bet when not allowed to do so
    error BettorCannotUpdateBet();

    /// @dev Error thrown when someone attempts to place a bet on a challenge that already has the maximum number of bettors
    error TooManyBettors();

    /// @dev Error thrown when the contract attempts to distribute winnings for a challenge from which the winnings have already been distributed
    error WinningsAlreadyPaid(uint256 challengeId);

    /// @dev Error thrown when a caller attempts to start someone else's challenge
    error OnlyChallengerCanStartChallenge();

    /// @dev Error thrown when a caller attempts to start a challenge with a length greater than the maximum allowed
    error ChallengeLengthTooLong();

    /// @dev Error thrown when a caller attempts to start a challenge with a greater number of metrics than the maximum allowed
    error TooManyChallengeMetrics();

    // price feed errors
    /// @dev Error thrown when the price feed round is not complete
    error PriceFeedRoundNotComplete();

    /// @dev Error thrown when the price feed is stale
    error StalePrice();

    /// @dev Error thrown when the price feed is too old
    error PriceFeedTooOld();

    /// @dev Error thrown when the price feed is invalid
    error InvalidPrice(); 
} 
