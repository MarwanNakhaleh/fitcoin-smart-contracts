// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/**
 * @title Challenge contract interface
 * @notice Interface for allowing users to start health challenges.
 */
interface IChallengeContract {
    /// @dev Enum representing the status of a challenge.
    enum ChallengeType { StepCount, MileageCount }

    /// @dev Enum representing the status of a challenge.
    enum ChallengeStatus { Inactive, Active, Expired, NotStarted }

    /// @notice Struct representing any challenge
    struct Challenge {
        uint256 id;
        uint256 startTime;
        uint256 challengeLength;
        bytes description;
        uint256 initialMeasurement;
        uint256 finalMeasurement;
        uint256 targetMeasurement;
        uint256 totalAmountBetFor;
        uint256 totalAmountBetAgainst;
        bool won;
        uint256 numberOfBettorsFor;
        uint256 numberOfBettorsAgainst;
        mapping(address => uint256) betsFor;
        mapping(address => uint256) betsAgainst;
        address[] bettors;
        ChallengeStatus status;
        ChallengeType challengeType;
    }

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
     * @dev Emitted when a challenger creates a challenge.
     * @param challenger The address of challenger who created the challenge.
     */
    event ChallengeCreated(address indexed challenger);

    /**
     * @dev Emitted when a challenger starts a challenge.
     * @param challenger The address of challenger who created the challenge.
     * @param challengeType The type of challenge.
     * @param targetMeasurement The targeted number to reach.
     */
    event ChallengeStarted(address indexed challenger, ChallengeType indexed challengeType, uint256 startMeasurement, uint256 targetMeasurement);

    function addNewChallenger(address challenger) external;

    function removeChallenger(address challenger) external;
}