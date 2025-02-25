// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "./IChallenge.sol";

/**
 * @title MultiplayerChallenge interface
 * @notice Extends IChallenge to allow multiplayer competition with a leader board.
 */
interface IMultiplayerChallenge is IChallenge {
    /// @dev Emitted when the global maximum number of competitors is updated.
    event MaxNumChallengeCompetitorsUpdated(uint256 oldValue, uint256 newValue);
    
    /// @dev Emitted when a competitor (other than the creator) joins a challenge.
    event ChallengeCompetitorJoined(uint256 indexed challengeId, address indexed competitor);

    /// @dev Emitted when a competitor leaves a challenge.
    event ChallengeCompetitorLeft(uint256 indexed challengeId, address indexed competitor);
    
    /// @dev Emitted when the leader for a challenge is updated.
    event LeaderUpdated(uint256 indexed challengeId, address indexed newLeader, uint256 newScore);
    
    /**
     * @notice Sets the contract-wide maximum number of competitors allowed per challenge.
     * @param _maxNum The new maximum number.
     */
    function setMaxNumChallengeCompetitors(uint256 _maxNum) external;
    
    /**
     * @notice Creates a new multiplayer challenge.
     * @param _lengthOfChallenge The challenge duration in seconds.
     * @param _challengeMetrics An array of metric identifiers for the challenge.
     * @param _targetMeasurementsForEachMetric The target measurement for each metric.
     * @param _maxCompetitors The number of competitors that can join this challenge (must be > 0 and no more than the global maximum).
     * @return The challenge ID.
     */
    function createMultiplayerChallenge(
        uint256 _lengthOfChallenge, 
        uint8[] calldata _challengeMetrics, 
        uint256[] calldata _targetMeasurementsForEachMetric,
        uint256 _maxCompetitors
    ) external returns(uint256);
    
    /**
     * @notice Allows a user to join an existing challenge as a competitor.
     * @param _challengeId The ID of the challenge to join.
     */
    function joinChallenge(uint256 _challengeId) external;

    /**
     * @notice Allows a user to leave a challenge he joined before it starts.
     * @param _challengeId The ID of the challenge to join.
     */
    function leaveChallenge(uint256 _challengeId) external;
    
    /**
     * @notice Submits measurements for a competitor. If the submitted (aggregated) measurements exceed the current leader's score,
     * the caller becomes the new leader.
     * @param _challengeId The challenge ID.
     * @param _submittedMeasurements An array of measurements corresponding to the challenge metrics.
     */
    function submitMeasurements(uint256 _challengeId, uint256[] calldata _submittedMeasurements) external;
    
    /**
     * @notice Returns the list of competitors for a given challenge.
     * @param _challengeId The challenge ID.
     * @return An array of competitor addresses.
     */
    function getCompetitors(uint256 _challengeId) external view returns (address[] memory);
    
    /**
     * @notice Returns the address of the current leader for a challenge.
     * @param _challengeId The challenge ID.
     * @return The leader’s address.
     */
    function getLeader(uint256 _challengeId) external view returns (address);
}
