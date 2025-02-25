// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "./Challenge.sol";
import "./interfaces/IMultiplayerChallenge.sol";

/**
 * @title MultiplayerChallenge
 * @notice An extension of Challenge that supports multiple competitors, each of whom can submit performance measurements.
 * The contract owner can set a global maximum number of competitors. At creation, the challenge creator selects a cap
 * (up to the global maximum) and is automatically added as the first competitor. Competitors can join until the cap is reached.
 * When any competitor submits their measurements, their aggregated score is compared against the current leader's score
 * and the leader is updated if they have a higher score.
 */
contract MultiplayerChallenge is Challenge, IMultiplayerChallenge {
    /// @notice Contract-level maximum allowed competitors per challenge.
    uint256 public maximumNumberOfChallengeCompetitors;
    
    /// @notice Mapping from challenge ID to the maximum competitors allowed (chosen at creation).
    mapping(uint256 => uint256) public challengeToMaxCompetitors;
    
    /// @notice Mapping from challenge ID to list of competitor addresses.
    mapping(uint256 => address[]) public challengeCompetitors;
    
    /// @notice Mapping from challenge ID to a competitor's participation flag.
    mapping(uint256 => mapping(address => bool)) public challengeHasCompetitor;
    
    /// @notice Mapping from challenge ID to competitor's aggregated score.
    mapping(uint256 => mapping(address => uint256)) public challengeCompetitorScores;
    
    /// @notice Mapping from challenge ID to the current leader's address.
    mapping(uint256 => address) public challengeLeader;
    
    /// @notice Mapping from challenge ID to the current leader's score.
    mapping(uint256 => uint256) public challengeLeaderScore;

    // ============================ //
    //           Errors             //
    // ============================ //
    
    /// @dev Error thrown when a caller attempts to start a challenge with less than 2 competitors.
    error NotEnoughCompetitors();
    
    /// @dev Error thrown when a caller attempts to start a challenge with more competitors than the global maximum.
    error ExceedsGlobalMaxCompetitors();

    /// @dev Error thrown when a caller attempts to join a challenge that is not active.
    error ChallengeCompetitorNotJoined(uint256 challengeId, address competitor);

    /// @dev Error thrown when a caller attempts to join a challenge that is full.
    error ChallengeIsFull(uint256 challengeId);

    /// @dev Error thrown when a caller attempts to join a challenge they have already joined.
    error ChallengeCompetitorAlreadyJoined(uint256 challengeId);

    /**
     * @notice Sets the global maximum number of competitors allowed per challenge.
     * @param _maxNum The new maximum number.
     */
    function setMaximumNumberOfChallengeCompetitors(uint256 _maxNum) external override onlyOwner {
        uint256 oldValue = maximumNumberOfChallengeCompetitors;
        maximumNumberOfChallengeCompetitors = _maxNum;
        emit MaximumNumberOfChallengeCompetitorsUpdated(oldValue, _maxNum);
    }

    // ============================ //
    //         Initializer          //
    // ============================ //
    function initializeMultiplayerChallenge(
        uint256 _minimumBetValue,
        uint256 _maximumNumberOfChallengeCompetitors,
        address _dataFeedAddress,
        uint32 _maximumNumberOfBettorsPerChallenge,
        uint32 _maximumChallengeLengthInSeconds,
        uint8 _maximumNumberOfChallengeMetrics
    ) external initializer {
        super.initialize(_minimumBetValue, _dataFeedAddress, _maximumNumberOfBettorsPerChallenge, _maximumChallengeLengthInSeconds, _maximumNumberOfChallengeMetrics);
        
        maximumNumberOfChallengeCompetitors = _maximumNumberOfChallengeCompetitors;
    }
    
    /**
     * @notice Creates a new multiplayer challenge.
     * The creator selects the challenge length, metrics, target measurements, and the maximum number of competitors allowed.
     * The creator is automatically added as the first competitor and set as the initial leader with a score of 0.
     * @param _lengthOfChallenge The challenge duration in seconds.
     * @param _challengeMetrics The metrics for the challenge.
     * @param _targetMeasurementsForEachMetric The target values for each metric.
     * @param _maxCompetitors The maximum number of competitors for this challenge.
     * @return challengeId The newly created challenge's ID.
     */
    function createMultiplayerChallenge(
        uint256 _lengthOfChallenge, 
        uint8[] calldata _challengeMetrics, 
        uint256[] calldata _targetMeasurementsForEachMetric,
        uint256 _maxCompetitors
    ) external override onlyChallengers(msg.sender) returns(uint256) {
        if (_maxCompetitors <= 1) {
            revert NotEnoughCompetitors();
        }
        if (_maxCompetitors > maximumNumberOfChallengeCompetitors) {
            revert ExceedsGlobalMaxCompetitors();
        }
        address challenger = msg.sender;
        // Call parent createChallenge (which emits events and initializes common challenge data)
        uint256 challengeId = super.createChallenge(_lengthOfChallenge, _challengeMetrics, _targetMeasurementsForEachMetric);
        
        // Set the maximum number of competitors for this challenge.
        challengeToMaxCompetitors[challengeId] = _maxCompetitors;
        
        // Add the creator as the first competitor.
        challengeCompetitors[challengeId].push(challenger);
        challengeHasCompetitor[challengeId][challenger] = true;
        
        // Set the initial leader to the creator with an initial score of 0.
        challengeLeader[challengeId] = challenger;
        challengeLeaderScore[challengeId] = 0;
        
        return challengeId;
    }
    
    /**
     * @notice Allows a user to join an existing challenge as a competitor.
     * @param _challengeId The ID of the challenge.
     */
    function joinChallenge(uint256 _challengeId) external override {
        // Ensure the challenge is still inactive (i.e. has not started yet).
        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) {
            revert ChallengeIsActive(_challengeId);
        }
        // Ensure there is room for more competitors.
        if (challengeCompetitors[_challengeId].length >= challengeToMaxCompetitors[_challengeId]) {
            revert ChallengeIsFull(_challengeId);
        }
        address caller = msg.sender;
        // Ensure the caller has not already joined.
        if (challengeHasCompetitor[_challengeId][caller]) {
            revert ChallengeCompetitorAlreadyJoined(_challengeId);
        }
        
        challengeCompetitors[_challengeId].push(caller);
        challengeHasCompetitor[_challengeId][caller] = true;
        
        emit ChallengeCompetitorJoined(_challengeId, caller);
    }

    /**
     * @notice Allows a user to join an existing challenge as a competitor.
     * @param _challengeId The ID of the challenge.
     */
    function leaveChallenge(uint256 _challengeId) external override {
        if(challengeToChallengeStatus[_challengeId] == STATUS_INACTIVE) {
            revert ChallengeIsActive(_challengeId);
        }
        
        address caller = msg.sender;
        
        uint256 length = challengeCompetitors[_challengeId].length;
        for (uint256 i = 0; i < length; i++) {
            if (challengeCompetitors[_challengeId][i] == caller) {
                // Move the last element to the position being deleted
                challengeCompetitors[_challengeId][i] = challengeCompetitors[_challengeId][length - 1];
                // Remove the last element
                challengeCompetitors[_challengeId].pop();
                break;
            }
        }
        challengeHasCompetitor[_challengeId][caller] = false;
        
        emit ChallengeCompetitorLeft(_challengeId, caller);
    }
    
    /**
     * @notice Allows any competitor to submit their measurements.
     * The submitted measurements are summed to produce a score. If this new score exceeds the current leader's score,
     * the caller becomes the new leader.
     * @param _challengeId The ID of the challenge.
     * @param _submittedMeasurements An array of measurements corresponding to the challenge metrics.
     */
    function submitMeasurements(uint256 _challengeId, uint256[] calldata _submittedMeasurements) 
        external override(Challenge, IMultiplayerChallenge) nonReentrant {
        // Ensure the sender is a competitor in this challenge.
        address caller = msg.sender;
        if (!challengeHasCompetitor[_challengeId][caller]) {
            revert ChallengeCompetitorNotJoined(_challengeId, caller);
        }
        
        // Verify that the challenge is active.
        if (challengeToChallengeStatus[_challengeId] != STATUS_ACTIVE) {
            revert ChallengeIsNotActive(_challengeId, challengeToChallengeStatus[_challengeId]);
        }
        // Check that the challenge has not expired.
        uint256 timestamp = block.timestamp;
        if (timestamp >= (challengeToStartTime[_challengeId] + challengeToChallengeLength[_challengeId])) {
            challengeToChallengeStatus[_challengeId] = STATUS_EXPIRED;
            revert ChallengeIsExpired(_challengeId);
        }
        
        // Calculate the aggregated score; for simplicity, we sum the measurements.
        uint256 newScore = 0;
        for (uint256 i = 0; i < _submittedMeasurements.length; i++) {
            newScore += _submittedMeasurements[i];
        }
        
        // Update the competitor's score.
        challengeCompetitorScores[_challengeId][caller] = newScore;
        
        // If the new score beats the current leader's score, update the leader.
        if (newScore > challengeLeaderScore[_challengeId]) {
            challengeLeader[_challengeId] = caller;
            challengeLeaderScore[_challengeId] = newScore;
            emit LeaderUpdated(_challengeId, caller, newScore);
        }
    }
    
    /**
     * @notice Returns the list of competitors for a given challenge.
     * @param _challengeId The challenge ID.
     * @return An array of competitor addresses.
     */
    function getCompetitors(uint256 _challengeId) external view override returns (address[] memory) {
        return challengeCompetitors[_challengeId];
    }
    
    /**
     * @notice Returns the current leader's address for a challenge.
     * @param _challengeId The challenge ID.
     * @return The leader's address.
     */
    function getLeader(uint256 _challengeId) external view override returns (address) {
        return challengeLeader[_challengeId];
    }
    
    /**
     * @notice Optionally override startChallenge if multiplayer-specific requirements are needed.
     * Here we require that at least two competitors are present before starting.
     * @param _challengeId The challenge ID.
     */
    function startChallenge(uint256 _challengeId) public override(Challenge, IChallenge) onlyChallengers(msg.sender) {
        if(challengeCompetitors[_challengeId].length < 2) {
            revert NotEnoughCompetitors();
        }
        challengeToChallengeStatus[_challengeId] = STATUS_ACTIVE;
        challengeToStartTime[_challengeId] = block.timestamp;
        challengerToActiveChallenge[msg.sender] = _challengeId;
        for (uint8 i = 0; i < challengeCompetitors[_challengeId].length; i++) {
            challengerToActiveChallenge[challengeCompetitors[_challengeId][i]] = _challengeId;
        }
    }
    
    /**
     * @dev Authorizes contract upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
