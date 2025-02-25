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
    uint256 public maxNumChallengeCompetitors;
    
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
    
    /**
     * @notice Sets the global maximum number of competitors allowed per challenge.
     * @param _maxNum The new maximum number.
     */
    function setMaxNumChallengeCompetitors(uint256 _maxNum) external override onlyOwner {
        uint256 oldValue = maxNumChallengeCompetitors;
        maxNumChallengeCompetitors = _maxNum;
        emit MaxNumChallengeCompetitorsUpdated(oldValue, _maxNum);
    }

    // ============================ //
    //         Initializer          //
    // ============================ //
    function initializeMultiplayerChallenge(
        uint256 _minimumBetValue,
        uint256 _maxNumChallengeCompetitors,
        address _dataFeedAddress
    ) external initializer {
        // Call the parent's initialize function
        super.initialize(_minimumBetValue, _dataFeedAddress);
        
        // Set multiplayer-specific state
        maxNumChallengeCompetitors = _maxNumChallengeCompetitors;
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
        require(_maxCompetitors > 0, "Max competitors must be > 0");
        require(_maxCompetitors <= maxNumChallengeCompetitors, "Exceeds global max competitors");
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
        require(challengeToChallengeStatus[_challengeId] == STATUS_INACTIVE, "Challenge already started");
        // Ensure there is room for more competitors.
        require(challengeCompetitors[_challengeId].length < challengeToMaxCompetitors[_challengeId], "Challenge is full");
        address competitor = msg.sender;
        // Ensure the caller has not already joined.
        require(!challengeHasCompetitor[_challengeId][competitor], "Already joined");
        
        challengeCompetitors[_challengeId].push(competitor);
        challengeHasCompetitor[_challengeId][competitor] = true;
        
        emit ChallengeCompetitorJoined(_challengeId, competitor);
    }

    /**
     * @notice Allows a user to join an existing challenge as a competitor.
     * @param _challengeId The ID of the challenge.
     */
    function leaveChallenge(uint256 _challengeId) external override {
        if(challengeToChallengeStatus[_challengeId] == STATUS_INACTIVE) {
            revert ChallengeIsActive(_challengeId);
        }
        
        address competitor = msg.sender;
        
        uint256 length = challengeCompetitors[_challengeId].length;
        for (uint256 i = 0; i < length; i++) {
            if (challengeCompetitors[_challengeId][i] == competitor) {
                // Move the last element to the position being deleted
                challengeCompetitors[_challengeId][i] = challengeCompetitors[_challengeId][length - 1];
                // Remove the last element
                challengeCompetitors[_challengeId].pop();
                break;
            }
        }
        challengeHasCompetitor[_challengeId][competitor] = false;
        
        emit ChallengeCompetitorLeft(_challengeId, competitor);
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
        require(challengeHasCompetitor[_challengeId][msg.sender], "Not a competitor in this challenge");
        
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
        challengeCompetitorScores[_challengeId][msg.sender] = newScore;
        
        // If the new score beats the current leader's score, update the leader.
        if (newScore > challengeLeaderScore[_challengeId]) {
            challengeLeader[_challengeId] = msg.sender;
            challengeLeaderScore[_challengeId] = newScore;
            emit LeaderUpdated(_challengeId, msg.sender, newScore);
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
