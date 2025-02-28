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

    /// @notice Mapping from challenge ID to the current leader's address.
    mapping(uint256 => address) public challengeLeader;

    /// @notice Mapping from challenge ID to the current leader's score.
    mapping(uint256 => mapping(address => uint256)) public challengeToCompetitorMeasurements;

    // ============================ //
    //           Errors             //
    // ============================ //

    /// @dev Error thrown when a caller attempts to start a challenge with less than 2 competitors.
    error NotEnoughCompetitors();

    /// @dev Error thrown when a caller attempts to start a challenge with more competitors than the global maximum.
    error ExceedsGlobalMaxCompetitors();

    /// @dev Error thrown when a caller attempts to join a challenge that is not active.
    error ChallengeCompetitorNotJoined(uint256 challengeId, address competitor);

    /// @dev Error when a challenger leaves a challenge with only one competitor
    error ChallengeHasOnlyOneCompetitor(uint256 challengeId);

    /// @dev Error thrown when a caller attempts to join a challenge that is full.
    error ChallengeIsFull(uint256 challengeId);

    /// @dev Error thrown when a caller attempts to join a challenge they have already joined.
    error ChallengeCompetitorAlreadyJoined(uint256 challengeId);

    /// @dev Error thrown when a caller attempts to submit an invalid number of measurements.
    error InvalidNumberOfMeasurements();

    /**
     * @notice Sets the global maximum number of competitors allowed per challenge.
     * @param _maxNum The new maximum number.
     */
    function setMaximumNumberOfChallengeCompetitors(
        uint256 _maxNum
    ) external override onlyOwner {
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
        super.initialize(
            _minimumBetValue,
            _dataFeedAddress,
            _maximumNumberOfBettorsPerChallenge,
            _maximumChallengeLengthInSeconds,
            _maximumNumberOfChallengeMetrics
        );

        maximumNumberOfChallengeCompetitors = _maximumNumberOfChallengeCompetitors;
    }

    /**
     * @notice Creates a new multiplayer challenge.
     * The creator selects the challenge length, metrics, target measurements, and the maximum number of competitors allowed.
     * The creator is automatically added as the first competitor and set as the initial leader with a score of 0.
     * @param _lengthOfChallenge The challenge duration in seconds.
     * @param _challengeMetric The metric for the challenge, there can only be one due to potential differences and weights of values.
     * @param _maxCompetitors The maximum number of competitors for this challenge.
     * @return challengeId The newly created challenge's ID.
     */
    function createMultiplayerChallenge(
        uint256 _lengthOfChallenge,
        uint8 _challengeMetric,
        uint256 _maxCompetitors
    ) external override onlyChallengers(msg.sender) returns (uint256) {
        if (_maxCompetitors <= 1) {
            revert NotEnoughCompetitors();
        }
        if (_maxCompetitors > maximumNumberOfChallengeCompetitors) {
            revert ExceedsGlobalMaxCompetitors();
        }
        uint8[] memory challengeMetrics = new uint8[](1);
        challengeMetrics[0] = _challengeMetric;
        // the target in multiplayer challenges is not used, so we can set it to 0
        uint256 placeholderTargetMeasurement = 0;
        uint256[] memory targetMeasurements = new uint256[](1);
        targetMeasurements[0] = placeholderTargetMeasurement;

        uint256 challengeId = super.createChallenge(
            _lengthOfChallenge,
            challengeMetrics,
            targetMeasurements
        );

        challengeToMaxCompetitors[challengeId] = _maxCompetitors;

        address challenger = msg.sender;
        challengeCompetitors[challengeId].push(challenger);
        challengeHasCompetitor[challengeId][challenger] = true;

        challengeLeader[challengeId] = challenger;

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
        if (
            challengeCompetitors[_challengeId].length >=
            challengeToMaxCompetitors[_challengeId]
        ) {
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
        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) {
            revert ChallengeIsActive(_challengeId);
        }
        if (challengeCompetitors[_challengeId].length == 1) {
            revert ChallengeHasOnlyOneCompetitor(_challengeId);
        }

        address caller = msg.sender;
        bool removed = false;
        uint256 length = challengeCompetitors[_challengeId].length;
        for (uint256 i = 0; i < length; i++) {
            if (challengeCompetitors[_challengeId][i] == caller) {
                if (i != length - 1) {
                    address followingCompetitor = challengeCompetitors[_challengeId][i + 1];
                    challengeCompetitors[_challengeId][length - 1] = challengeCompetitors[_challengeId][i];
                    challengeCompetitors[_challengeId][i] = followingCompetitor;
                }
                challengeCompetitors[_challengeId].pop();
                
                removed = true;
                break;
            }
        }
        if (!removed) {
            revert ChallengeCompetitorNotJoined(_challengeId, caller);
        }
        challengeHasCompetitor[_challengeId][caller] = false;

        emit ChallengeCompetitorLeft(_challengeId, caller);
        
        // if the challenger leaves, we need to set the first competitor as the new challenger
        if(challengeToChallenger[_challengeId] == caller) {
            address newChallenger = challengeCompetitors[_challengeId][0];
            challengeToChallenger[_challengeId] = newChallenger;
            emit ChallengerChanged(_challengeId, caller, newChallenger);
        }
    }

    /**
     * @inheritdoc IMultiplayerChallenge
     */
    function submitMeasurements(
        uint256 _challengeId,
        uint256[] calldata _submittedMeasurements
    ) public virtual override(Challenge, IMultiplayerChallenge) nonReentrant {
        // Ensure the sender is a competitor in this challenge.
        address caller = msg.sender;
        if (!challengeHasCompetitor[_challengeId][caller]) {
            revert ChallengeCompetitorNotJoined(_challengeId, caller);
        }

        // For multiplayer, we only use the first measurement
        if (_submittedMeasurements.length != 1) {
            revert InvalidNumberOfMeasurements();
        }

        if (challengeToChallengeStatus[_challengeId] != STATUS_ACTIVE) {
            revert ChallengeIsNotActive(
                _challengeId,
                challengeToChallengeStatus[_challengeId]
            );
        }

        uint256 timestamp = block.timestamp;
        if (
            timestamp >=
            (challengeToStartTime[_challengeId] +
                challengeToChallengeLength[_challengeId])
        ) {
            challengeToChallengeStatus[_challengeId] = STATUS_EXPIRED;
            revert ChallengeIsExpired(_challengeId);
        }
        
        challengeToCompetitorMeasurements[_challengeId][caller] = _submittedMeasurements[0];
        address incumbentLeader = challengeLeader[_challengeId];

        if (challengeToCompetitorMeasurements[_challengeId][incumbentLeader] < _submittedMeasurements[0]) {
            challengeLeader[_challengeId] = caller;
            emit LeaderUpdated(_challengeId, caller, _submittedMeasurements[0]);
        } else {
            uint256 measurementToBeat = challengeToCompetitorMeasurements[_challengeId][incumbentLeader];
            emit LeaderNotUpdated(_challengeId, caller, incumbentLeader, measurementToBeat);
        }
    }

    /**
     * @notice Returns the list of competitors for a given challenge.
     * @param _challengeId The challenge ID.
     * @return An array of competitor addresses.
     */
    function getCompetitors(
        uint256 _challengeId
    ) external view override returns (address[] memory) {
        return challengeCompetitors[_challengeId];
    }

    /**
     * @notice Returns the current leader's address for a challenge.
     * @param _challengeId The challenge ID.
     * @return The leader's address.
     */
    function getLeader(
        uint256 _challengeId
    ) public view override returns (address) {
        return challengeLeader[_challengeId];
    }

    /**
     * @notice Returns the current leader's score for a challenge.
     * @param _challengeId The challenge ID.
     * @return The leader's score.
     */
    function getLeaderScore(
        uint256 _challengeId
    ) external view returns (uint256) {
        address leader = challengeLeader[_challengeId];
        return challengeToCompetitorMeasurements[_challengeId][leader];
    }

    /**
     * @notice Gets a specific competitor's score
     * @param _challengeId The challenge ID
     * @param _competitor The competitor's address
     * @return The competitor's score
     */
    function getCompetitorScore(
        uint256 _challengeId, 
        address _competitor
    ) external view returns (uint256) {
        if(challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) {
            revert ChallengeNotYetStarted(_challengeId);
        }
        if (!challengeHasCompetitor[_challengeId][_competitor]) {
            revert ChallengeCompetitorNotJoined(_challengeId, _competitor);
        }
        return challengeToCompetitorMeasurements[_challengeId][_competitor];
    }

    /**
     * @notice Optionally override startChallenge if multiplayer-specific requirements are needed.
     * Here we require that at least two competitors are present before starting.
     * @param _challengeId The challenge ID.
     */
    function startChallenge(
        uint256 _challengeId
    ) public override(Challenge, IChallenge) onlyChallengers(msg.sender) {
        if (challengeToChallenger[_challengeId] != msg.sender) {
            revert ChallengeCanOnlyBeModifiedByChallenger(_challengeId, msg.sender, challengeToChallenger[_challengeId]);
        }
        if (challengeCompetitors[_challengeId].length < 2) {
            revert NotEnoughCompetitors();
        }
        challengeToChallengeStatus[_challengeId] = STATUS_ACTIVE;
        challengeToStartTime[_challengeId] = block.timestamp;
        challengerToActiveChallenge[msg.sender] = _challengeId;
        for (uint8 i = 0; i < challengeCompetitors[_challengeId].length; ) {
            challengerToActiveChallenge[
                challengeCompetitors[_challengeId][i]
            ] = _challengeId;
            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Authorizes contract upgrades.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
