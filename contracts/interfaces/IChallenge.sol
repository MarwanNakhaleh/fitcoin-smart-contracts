// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @title Challenge contract interface
 * @author Branson Solutions LLC
 * @notice Interface for allowing users to start health challenges.
 */
interface IChallenge {
    /**
     * @dev Emitted when the maximum number of bettors per challenge is set.
     * @param oldValue The previous maximum number of bettors per challenge.
     * @param newValue The new maximum number of bettors per challenge.
     */
    event MaximumNumberOfBettorsPerChallengeSet(uint256 oldValue, uint256 newValue);

    /**
     * @dev Emitted when the maximum challenge length is set.
     * @param oldValue The previous maximum challenge length.
     * @param newValue The new maximum challenge length.
     */
    event MaximumChallengeLengthSet(uint256 oldValue, uint256 newValue);
    
    /**
     * @dev Emitted when the maximum number of challenge metrics is set.
     * @param oldValue The previous maximum number of challenge metrics.
     * @param newValue The new maximum number of challenge metrics.
     */
    event MaximumNumberOfChallengeMetricsSet(uint256 oldValue, uint256 newValue);

    /**
     * @dev Emitted when the minimum bet value is set.
     * @param oldValue The previous minimum bet value.
     * @param newValue The new minimum bet value.
     */
    event MinimumBetValueSet(uint256 oldValue, uint256 newValue);

    /**
     * @dev Emitted when a new challenger is allowed to create challenges.
     * @param challenger The address of the eligible challenger.
     */
    event ChallengerJoined(address indexed challenger);

    /**
     * @dev Emitted when a new bettor is allowed to bet on challenges.
     * @param bettor The address of the eligible bettor.
     */
    event BettorJoined(address indexed bettor);

    /**
     * @dev Emitted when a new challenger is blocked from creating challenges.
     * @param challenger The address of the removed challenger.
     */
    event ChallengerRemoved(address indexed challenger);

    /**
     * @dev Emitted when a challenger creates a challenge.
     * @param challenger The address of challenger who created the challenge.
     * @param challengeId The ID of the challenge
     * @param lengthOfChallenge The length of the challenge in seconds
     * @param challengeMetrics The metrics of the challenge
     * @param targetMeasurementsForEachMetric The target measurements for each metric
     */
    event ChallengeCreated(address indexed challenger, uint256 indexed challengeId, uint256 lengthOfChallenge, uint8[] challengeMetrics, uint256[] targetMeasurementsForEachMetric);

    /**
     * @dev Emitted when a challenger starts a challenge.
     * @param challenger The address of challenger who created the challenge.
     * @param challengeId The ID of the challenge
     */
    event ChallengeStarted(address indexed challenger, uint256 indexed challengeId);

    /**
     * @dev Emitted when a user makes a bet
     * @param challengeId The challenge ID
     * @param bettor The address that placed the bet
     * @param bettingForChallenger true if the bet was placed in hopes that the challenger will win
     * @param betAmount the amount of money bet for the challenger
     */
    event BetPlaced(uint256 challengeId, address bettor, bool bettingForChallenger, uint256 betAmount);

    /**
     * @dev Emitted when the gas used to distribute winnings is logged
     * @param gasUsed The amount of gas used to distribute winnings
     */
    event GasUsed(address indexed bettor, uint256 gasUsed);

    /**
     * @dev Emitted when the winnings are distributed
     * @param challengeId The challenge ID
     * @param bettor The address that received the winnings
     * @param share The amount of winnings received
     */
    event WinningsDistributed(uint256 challengeId, address bettor, uint256 share);

    /**
     * @dev Emitted when a winnings distribution fails for a particular bettor
     * @param challengeId The challenge ID
     * @param bettor The address that failed to receive winnings
     * @param amount The amount of winnings that failed to be distributed
     */
    event WinningsDistributionFailed(uint256 indexed challengeId, address indexed bettor, uint256 amount);

    /**
    * @notice Retrieves all challenge IDs for a specific challenger.
    * @param challenger The address of the challenger.
    * @return An array of challenge IDs created by the challenger.
    */
    function getChallengesForChallenger(address challenger) external view returns (uint256[] memory);

    /**
     * @notice Whitelists an address to begin creating challenges.
     * @param _challenger The address that wants to start creating challenges.
     *
     * Requirements:
     * - The caller is not already on the challenger whitelist.
     */
    function addNewChallenger(address _challenger) external;

    /**
     * @notice Removes an address' access to create challenges.
     * @param _challenger The address that needs to be prevented from creating challenges.
     *
     * Requirements:
     * - The caller exists in the challenger whitelist.
     */
    function removeChallenger(address _challenger) external;

    /**
     * @notice Whitelists an address to begin betting on challenges.
     * @param _bettor The address that wants to start betting on challenges.
     *
     * Requirements:
     * - The caller is not already on the bettor whitelist.
     */
    function addNewBettor(address _bettor) external;

    /**
     * @notice Updates the minimum USD value of a bet on a fitness challenge.
     * @param _newMinimumValue The new minimum USD value of a bet for or against someone in a challenge.
     *
     * Requirements:
     * - The caller owns the contract
     * - The value is greater than 0
     */
    function setMinimumBetValue(uint256 _newMinimumValue) external;

    
    /** 
     * @notice Provides the information necessary to start a challenge once requirements are met
     * @param _challengeId The ID of the challenge to start
     *
     * Requirements:
     * - The caller is on the challenger whitelist
     * - The challenger does not already have an active challenge
     * - There is at least one person betting against the challenger
     */
    function startChallenge(uint256 _challengeId) external;

    /** 
     * @notice Place a bet for or against a challenge
     * @param _challengeId The challenge on which you want to bet
     * @param _bettingFor A boolean to indicate betting for (true) or against (false) the challenger
     *
     * Requirements:
     * - The caller is on the bettor whitelist
     * - The challenge on which the caller wants to bet exists and has not yet started
     * - The maximum number of bettors per bet has not been reached
     * - If the caller is the challenger, he is not betting against himself
     * - The caller has not already placed a bet
     */
    function placeBet(uint256 _challengeId, bool _bettingFor) external payable;

    /** 
     * @notice Allows someone who has already bet to modify his existing bet
     * @param _challengeId The challenge on which you want to bet
     * @param _bettingFor A boolean to indicate betting for (true) or against (false) the challenger
     *
     * Requirements:
     * - The caller is on the bettor whitelist
     * - The challenge on which the caller wants to change his bet exists and has not yet started
     * - If the caller is the challenger, he is not betting against himself
     */
    function changeBet(uint256 _challengeId, bool _bettingFor) external payable;

    /**
     * @notice Allows someone who has already bet to cancel their bet
     * @param _challengeId The challenge on which you want to cancel your bet
     *
     * Requirements:
     * - The caller is on the bettor whitelist 
     */
    function cancelBet(uint256 _challengeId) external payable;

     /** 
     * @notice Provides data to determine if a challenger has succeeded
     * @param _challengeId The challenge to which the measurements apply
     * @param _submittedMeasurements A set of values to show progress against the challenge
     *
     * Requirements:
     * - The caller is on the bettor whitelist
     * - The challenge on which the caller wants to change his bet exists and has not yet started
     * - If the caller is the challenger, he is not betting against himself
     */
    function submitMeasurements(uint256 _challengeId, uint256[] calldata _submittedMeasurements) external;
}