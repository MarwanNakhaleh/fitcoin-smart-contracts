// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IChallenge.sol";
import "./interfaces/IVault.sol";

contract Challenge is
    IChallenge,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable
{
    // ============================ //
    //             Enums            //
    // ============================ //

    /**
     * @dev Enumerated values representing the type of health challenges available, subject to change as capability expands.
     */
    uint8 constant CHALLENGE_STEPS = 0;
    uint8 constant CHALLENGE_MILEAGE = 1;
    uint8 constant CHALLENGE_CYCLING_MILEAGE = 2;
    uint8 constant CHALLENGE_CALORIES_BURNED = 3;

    /**
     * @dev Enumerated values representing the status of a challenge, subject to change as capability expands.
     */
    uint8 constant STATUS_INACTIVE = 0;
    uint8 constant STATUS_ACTIVE = 1;
    uint8 constant STATUS_EXPIRED = 2;
    uint8 constant STATUS_CHALLENGER_WON = 3;
    uint8 constant STATUS_CHALLENGER_LOST = 4;

    // ============================ //
    //      State Variables         //
    // ============================ //

    /// @notice the data feed allowing us to determine the current price of ETH to set a minimum amount of ETH required to fulfill the minimum USD value of the bet
    AggregatorV3Interface internal dataFeed;

    /// @notice the vault contract
    IVault internal vault;

    /// @notice the minimum number of total bettors on a challenge
    uint256 constant MINIMUM_NUMBER_OF_BETTORS_AGAINST = 1;

    /// @notice ETH/USD exchange rate on Base Mainnet
    // address internal dataFeedAddress = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    /// @notice the minimum value in USD of a bet on a challenge, either from the challenger or someone betting against them
    uint256 internal minimumUsdValueOfBet;

    /// @notice the maximum number of bettors per challenge, default set to 100
    uint32 internal maximumNumberOfBettorsPerChallenge;

    /// @notice the maximum length of a challenge in seconds, default set to 30 days
    uint32 internal maximumChallengeLengthInSeconds;

    /// @notice the maximum number of metrics per challenge, default set to 3
    uint8 internal maximumNumberOfChallengeMetrics;

    /// @notice Whitelisted challengers who can participate in challenges
    mapping(address => bool) public challengerWhitelist;

    /// @notice Whitelisted bettors who can bet on challenges
    mapping(address => bool) public bettorWhitelist;

    // ==================================== //
    // Challenger metadata data structures  //
    // ==================================== //

    /// @notice Mapping to get all of a challenger's challenges
    mapping(address => uint256[]) internal challengerToChallenges;

    /// @notice Mapping to get the challenge ID of a challenger's currently active challenge
    /// @dev When a challenge finishes, we will change the value in the mapping back to 0
    mapping(address => uint256) public challengerToActiveChallenge;

    // ==================================== //
    //  Challenge metadata data structures  //
    // ==================================== //

    uint256 public latestChallengeId;

    /// @notice Mapping to get a challenge's owner by challenge ID
    mapping(uint256 => address) public challengeToChallenger;

    /// @notice Mapping to get whether or not a challenge's winnings have been paid
    mapping(uint256 => uint256) public challengeToWinningsPaid;

    /// @notice Mapping to get the target measurements for a challenge by challenge ID
    mapping(uint256 => mapping(uint8 => uint256)) challengeToTargetMetricMeasurements;

    /// @notice Mapping to get the final measurements for a challenge by challenge ID
    mapping(uint256 => mapping(uint8 => uint256)) challengeToFinalMetricMeasurements;

    /// @notice Mapping to get all challenge metrics included in a particular challenge
    mapping(uint256 => uint8[]) challengeToIncludedMetrics;

    /// @notice Mapping to get the challenge start time from by challenge ID
    mapping(uint256 => uint256) public challengeToStartTime;

    /// @notice Mapping to get the challenge length from by challenge ID
    mapping(uint256 => uint256) public challengeToChallengeLength;

    /// @notice Mapping to get a challenge's status by ID
    mapping(uint256 => uint8) public challengeToChallengeStatus;

    // ==================================== //
    //  Challenge bet info data structures  //
    // ==================================== //
    mapping(uint256 => uint256) public challengeToTotalAmountBetFor;
    mapping(uint256 => uint256) public challengeToTotalAmountBetAgainst;
    mapping(uint256 => uint256) public challengeToNumberOfBettorsFor;
    mapping(uint256 => uint256) public challengeToNumberOfBettorsAgainst;

    mapping(uint256 => mapping(address => uint256)) public challengeToBetsFor;
    mapping(uint256 => mapping(address => uint256))
        public challengeToBetsAgainst;
    mapping(uint256 => address[]) public challengeToBettors;

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

    // ============================ //
    //          Modifiers           //
    // ============================ //

    modifier onlyChallengers(address _address) {
        if (!challengerWhitelist[_address]) revert ChallengerNotInWhitelist();
        _;
    }

    modifier onlyBettors(address _address) {
        if (!bettorWhitelist[_address]) revert BettorNotInWhitelist();
        _;
    }

    modifier betIsGreaterThanOrEqualToMinimumBetValue() {
        uint256 ethPrice = getLatestPrice();
        uint256 betValueInUsd = (msg.value * ethPrice) / 1e8; // Adjust for price feed decimals
        if (betValueInUsd < minimumUsdValueOfBet) revert MinimumBetAmountTooSmall();
        _;
    }

    modifier checkBettingEligibility(uint256 _challengeId) {
        if (!bettorWhitelist[msg.sender]) {
            revert BettorNotInWhitelist();
        }
        if (address(vault) == address(0)) {
            revert VaultNotSet();
        }
        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) {
            revert ChallengeCannotBeModified();
        }
        _;
    }

    // ============================ //
    //         Setters              //
    // ============================ //

    /// @notice Sets the vault contract
    function setVault(address _vault) external onlyOwner whenNotPaused {
        if (_vault == address(0)) revert VaultNotSet();
        vault = IVault(_vault);
    }

    /// @notice Sets the maximum number of bettors per challenge
    function setMaximumNumberOfBettorsPerChallenge(
        uint32 _maximumNumberOfBettorsPerChallenge
    ) external onlyOwner whenNotPaused {
        if (_maximumNumberOfBettorsPerChallenge < (MINIMUM_NUMBER_OF_BETTORS_AGAINST + 1)) revert MaximumNumberOfBettorsPerChallengeTooSmall();
        maximumNumberOfBettorsPerChallenge = _maximumNumberOfBettorsPerChallenge;
        emit MaximumNumberOfBettorsPerChallengeSet(maximumNumberOfBettorsPerChallenge, _maximumNumberOfBettorsPerChallenge);
    }

     /// @notice Sets the maximum number of bettors per challenge
    function setMaximumChallengeLength(
        uint32 _maximumChallengeLengthInSeconds
    ) external onlyOwner whenNotPaused {
        if (_maximumChallengeLengthInSeconds == 0) revert ChallengeLengthTooShort();
        maximumChallengeLengthInSeconds = _maximumChallengeLengthInSeconds;
        emit MaximumChallengeLengthSet(maximumChallengeLengthInSeconds, _maximumChallengeLengthInSeconds);
    }

    /// @notice Sets the maximum number of challenge metrics
    function setMaximumNumberOfChallengeMetrics(
        uint8 _maximumNumberOfChallengeMetrics
    ) external onlyOwner whenNotPaused {
        if (_maximumNumberOfChallengeMetrics == 0) revert MaximumNumberOfChallengeMetricsTooSmall();
        maximumNumberOfChallengeMetrics = _maximumNumberOfChallengeMetrics;
        emit MaximumNumberOfChallengeMetricsSet(maximumNumberOfChallengeMetrics, _maximumNumberOfChallengeMetrics);
    }

    /**
     * @inheritdoc IChallenge
     */
    function setMinimumBetValue(
        uint256 _newMinimumValue
    ) external virtual override onlyOwner whenNotPaused {
        if (_newMinimumValue == 0) revert MinimumBetAmountTooSmall();
        minimumUsdValueOfBet = _newMinimumValue;
        emit MinimumBetValueSet(minimumUsdValueOfBet, _newMinimumValue);
    }

    // ============================ //
    //         Getters              //
    // ============================ //

    /// @notice Gets the minimum USD value of a bet
    function getMinimumUsdValueOfBet() external view returns (uint256) {
        return minimumUsdValueOfBet;
    }

    /// @notice Gets the maximum number of bettors per challenge
    function getMaximumNumberOfBettorsPerChallenge() external view returns (uint32) {
        return maximumNumberOfBettorsPerChallenge;
    }

    /// @notice Gets the maximum challenge length
    function getMaximumChallengeLength() external view returns (uint32) {
        return maximumChallengeLengthInSeconds;
    }

    /// @notice Gets the maximum number of challenge metrics
    function getMaximumNumberOfChallengeMetrics() external view returns (uint8) {
        return maximumNumberOfChallengeMetrics;
    }

    // ============================ //
    //         Initializer          //
    // ============================ //

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Challenge contract to
     * @dev This function replaces the constructor for upgradeable contracts. It can only be called once.
     *
     * @param _minimumBetValue the minimum USD value for a bet for or against a challenger
     * @param _dataFeedAddress the smart contract address from which we want to get real-time cryptocurrency price information
     *
     * Requirements:
     *
     * - _minimumBetValue is greater than 0
     */
    function initialize(
        uint256 _minimumBetValue,
        address _dataFeedAddress,
        uint32 _maximumNumberOfBettorsPerChallenge,
        uint32 _maximumChallengeLengthInSeconds,
        uint8 _maximumNumberOfChallengeMetrics
    ) public initializer {
        if (_minimumBetValue == 0) revert MinimumBetAmountTooSmall();
        if (_maximumNumberOfBettorsPerChallenge < (MINIMUM_NUMBER_OF_BETTORS_AGAINST + 1)) revert MaximumNumberOfBettorsPerChallengeTooSmall();
        if (_maximumChallengeLengthInSeconds == 0) revert ChallengeLengthTooShort();
        if (_maximumNumberOfChallengeMetrics == 0) revert MaximumNumberOfChallengeMetricsTooSmall();
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);
        transferOwnership(msg.sender);
        __UUPSUpgradeable_init();

        minimumUsdValueOfBet = _minimumBetValue;
        maximumNumberOfBettorsPerChallenge = _maximumNumberOfBettorsPerChallenge;
        maximumChallengeLengthInSeconds = _maximumChallengeLengthInSeconds;
        maximumNumberOfChallengeMetrics = _maximumNumberOfChallengeMetrics;
        dataFeed = AggregatorV3Interface(_dataFeedAddress);
        latestChallengeId = 0;

        emit MinimumBetValueSet(0, _minimumBetValue);
        emit MaximumNumberOfBettorsPerChallengeSet(0, _maximumNumberOfBettorsPerChallenge);
        emit MaximumChallengeLengthSet(0, _maximumChallengeLengthInSeconds);
        emit MaximumNumberOfChallengeMetricsSet(0, _maximumNumberOfChallengeMetrics);
    }

    // ============================ //
    //      Interface Functions     //
    // ============================ //

    /**
     * @inheritdoc IChallenge
     */
    function getChallengesForChallenger(
        address challenger
    ) external view returns (uint256[] memory) {
        return challengerToChallenges[challenger];
    }

    /**
     * @inheritdoc IChallenge
     */
    function addNewChallenger(
        address challenger
    ) public virtual override onlyOwner whenNotPaused {
        if (challengerWhitelist[challenger])
            revert ChallengerAlreadyInWhitelist();

        challengerWhitelist[challenger] = true;
        bettorWhitelist[challenger] = true;

        emit ChallengerJoined(challenger);
        emit BettorJoined(challenger); // a user allowed to create challenges is also by default allowed to bet
    }

    /**
     * @inheritdoc IChallenge
     */
    function addNewBettor(address bettor) public virtual override onlyOwner whenNotPaused {
        if (bettorWhitelist[bettor]) revert BettorAlreadyInWhitelist();

        bettorWhitelist[bettor] = true;

        emit BettorJoined(bettor);
    }

    /**
     * @inheritdoc IChallenge
     */
    function removeChallenger(
        address challenger
    ) external virtual override onlyOwner whenNotPaused {
        if (!challengerWhitelist[challenger]) revert ChallengerNotInWhitelist();

        challengerWhitelist[challenger] = false;

        emit ChallengerRemoved(challenger);
    }

    /**
     * @notice Creates a new challenge for a whitelisted challenger, but does not start a challenge until requirements are met
     * @param _lengthOfChallenge The time length of the challenge in seconds
     * @param _challengeMetrics The set of metrics the challenger wants to reach in the challenge time frame
     * @param _targetMeasurementsForEachMetric The set of target measurements for each metric the challenger wants to achieve
     *
     * Requirements:
     * - The caller is on the challenger whitelist
     * - The challenger does not already have an active challenge
     */
    function createChallenge(
        uint256 _lengthOfChallenge,
        uint8[] memory _challengeMetrics,
        uint256[] memory _targetMeasurementsForEachMetric
    )
        public
        virtual
        nonReentrant
        onlyChallengers(msg.sender)
        whenNotPaused
        returns (uint256)
    {
        if (_lengthOfChallenge > maximumChallengeLengthInSeconds)
            revert ChallengeLengthTooLong();
        if (_challengeMetrics.length == 0)
            revert("At least one metric is required");
        if (_challengeMetrics.length != _targetMeasurementsForEachMetric.length)
            revert MalformedChallengeMetricsProvided();
        if (_challengeMetrics.length > maximumNumberOfChallengeMetrics)
            revert TooManyChallengeMetrics();

        address challenger = msg.sender;
        uint256 currentChallengeId = latestChallengeId;
        unchecked {
            latestChallengeId++;
        }

        challengeToChallenger[currentChallengeId] = challenger;
        challengerToChallenges[challenger].push(currentChallengeId);

        for (uint256 i = 0; i < _challengeMetrics.length; ) {
            challengeToTargetMetricMeasurements[currentChallengeId][
                _challengeMetrics[i]
            ] = _targetMeasurementsForEachMetric[i];
            challengeToIncludedMetrics[currentChallengeId].push(
                _challengeMetrics[i]
            );
            unchecked {
                i++;
            }
        }
        challengeToChallengeLength[currentChallengeId] = _lengthOfChallenge;
        challengeToChallengeStatus[currentChallengeId] = STATUS_INACTIVE;

        emit ChallengeCreated(
            challenger,
            currentChallengeId,
            _lengthOfChallenge,
            _challengeMetrics,
            _targetMeasurementsForEachMetric
        );

        return currentChallengeId;
    }

    /**
     * @inheritdoc IChallenge
     */
    function startChallenge(
        uint256 _challengeId
    ) public virtual nonReentrant onlyChallengers(msg.sender) whenNotPaused {
        address challenger = msg.sender;
        if (challengeToChallenger[_challengeId] != challenger) {
            revert OnlyChallengerCanStartChallenge();
        }
        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE)
            revert ChallengeIsActive(_challengeId);
        if (challengeToTotalAmountBetAgainst[_challengeId] == 0)
            revert NobodyBettingAgainstChallenger();
        if (challengeToTotalAmountBetFor[_challengeId] == 0)
            revert NobodyBettingForChallenger();

        challengeToChallengeStatus[_challengeId] = STATUS_ACTIVE;
        challengeToStartTime[_challengeId] = block.timestamp;
        challengerToActiveChallenge[challenger] = _challengeId;
    }

    // TODO: Refactor so that the value is locked in a vault rather than paid to the contract
    /**
     * @inheritdoc IChallenge
     */
    function placeBet(
        uint256 _challengeId,
        bool _bettingFor
    ) public payable virtual override nonReentrant checkBettingEligibility(_challengeId) betIsGreaterThanOrEqualToMinimumBetValue whenNotPaused {
        if (challengeToChallengeStatus[_challengeId] == STATUS_ACTIVE)
            revert ChallengeIsActive(_challengeId);
        if (msg.value < minimumUsdValueOfBet) revert MinimumBetAmountTooSmall();
        if (address(vault) == address(0)) revert VaultNotSet();

        unchecked {
            uint256 totalBettorsOnChallenge = challengeToNumberOfBettorsFor[
                _challengeId
            ] + challengeToNumberOfBettorsAgainst[_challengeId];
            if (totalBettorsOnChallenge >= maximumNumberOfBettorsPerChallenge)
                revert TooManyBettors();
        }

        address caller = msg.sender;
        if (challengeToChallenger[_challengeId] == caller && !_bettingFor)
            revert ChallengerCannotBetAgainstHimself();
        if (
            challengeToBetsFor[_challengeId][caller] != 0 ||
            challengeToBetsAgainst[_challengeId][caller] != 0
        ) revert BettorCannotUpdateBet();

        uint256 value = msg.value;
        vault.depositETH{value: msg.value}();

        if (_bettingFor) {
            unchecked {
                challengeToNumberOfBettorsFor[_challengeId] += 1;
                challengeToTotalAmountBetFor[_challengeId] += uint256(value);
            }
            challengeToBetsFor[_challengeId][caller] = uint256(value);
        } else {
            unchecked {
                challengeToNumberOfBettorsAgainst[_challengeId] += 1;
                challengeToTotalAmountBetAgainst[_challengeId] += uint256(
                    value
                );
            }
            challengeToBetsAgainst[_challengeId][caller] = uint256(value);
        }

        challengeToBettors[_challengeId].push(caller);

        emit BetPlaced(_challengeId, caller, _bettingFor, value);
    }

    /**
     * @inheritdoc IChallenge
     */
    function cancelBet(
        uint256 _challengeId
    ) public payable virtual override nonReentrant checkBettingEligibility(_challengeId) whenNotPaused {
        address caller = msg.sender;
        if (
            challengeToBetsFor[_challengeId][caller] == 0 &&
            challengeToBetsAgainst[_challengeId][caller] == 0
        ) revert BettorCannotUpdateBet();

        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) {
            revert ChallengeCannotBeModified();
        }
    }

    /**
     * @inheritdoc IChallenge
     */
    function changeBet(
        uint256 _challengeId,
        bool _bettingFor
    ) external payable virtual override nonReentrant onlyBettors(msg.sender) whenNotPaused {
        address caller = msg.sender;
        if (
            challengeToBetsFor[_challengeId][caller] == 0 &&
            challengeToBetsAgainst[_challengeId][caller] == 0
        ) revert BettorCannotUpdateBet();
        if (msg.value < minimumUsdValueOfBet) revert MinimumBetAmountTooSmall();

        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) {
            revert ChallengeCannotBeModified();
        }
    }

    /**
     * @inheritdoc IChallenge
     */
    function submitMeasurements(
        uint256 _challengeId,
        uint256[] calldata _submittedMeasurements
    ) external virtual override onlyChallengers(msg.sender) nonReentrant whenNotPaused {
        address caller = msg.sender;
        if (challengeToChallenger[_challengeId] != caller)
            revert ChallengeCanOnlyBeModifiedByChallenger(
                _challengeId,
                caller,
                challengeToChallenger[_challengeId]
            );

        if (
            challengeToIncludedMetrics[_challengeId].length !=
            _submittedMeasurements.length
        ) revert MalformedChallengeMetricsProvided();
        if (challengeToChallengeStatus[_challengeId] != STATUS_ACTIVE)
            revert ChallengeIsNotActive(
                _challengeId,
                challengeToChallengeStatus[_challengeId]
            );

        uint256 timestamp = block.timestamp;
        if (
            timestamp >=
            (challengeToStartTime[_challengeId] +
                challengeToChallengeLength[_challengeId])
        ) {
            challengeToChallengeStatus[_challengeId] = STATUS_EXPIRED;
            revert ChallengeIsExpired(_challengeId);
        }

        for (uint256 i = 0; i < _submittedMeasurements.length; ) {
            uint8 currentMetric = challengeToIncludedMetrics[_challengeId][i];
            challengeToFinalMetricMeasurements[_challengeId][
                currentMetric
            ] = _submittedMeasurements[i];
            unchecked {
                i++;
            }
        }
    }

    function distributeWinnings(uint256 _challengeId) public virtual override onlyOwner whenNotPaused {
        if (address(vault) == address(0)) revert VaultNotSet();

        uint256 timestamp = block.timestamp;
        if (
            timestamp <
            (challengeToStartTime[_challengeId] +
                challengeToChallengeLength[_challengeId])
        ) {
            revert ChallengeIsActive(_challengeId);
        }
        
        if (challengeToChallengeStatus[_challengeId] != STATUS_EXPIRED) {
            challengeToChallengeStatus[_challengeId] = STATUS_EXPIRED;
        }

        if (challengeToWinningsPaid[_challengeId] > 0)
            revert WinningsAlreadyPaid(_challengeId);

        bool challengeWon = true;
        
        // Use local variables to reduce SLOADs
        uint8[] memory metrics = challengeToIncludedMetrics[_challengeId];
        uint256 metricsLength = metrics.length;
        
        for (uint8 i = 0; i < metricsLength; ) {
            uint8 metricType = metrics[i];
            if (
                challengeToFinalMetricMeasurements[_challengeId][metricType] <
                challengeToTargetMetricMeasurements[_challengeId][metricType]
            ) {
                challengeWon = false;
                break;
            }
            unchecked {
                i++;
            }
        }

        uint256 totalAmountToSplit;
        uint256 totalAmountBetCorrectly;
        address[] memory bettors = challengeToBettors[_challengeId];
        uint256 bettorsLength = bettors.length;

        if (challengeWon) {
            challengeToChallengeStatus[_challengeId] = STATUS_CHALLENGER_WON;
            totalAmountToSplit = challengeToTotalAmountBetAgainst[_challengeId];
            totalAmountBetCorrectly = challengeToTotalAmountBetFor[
                _challengeId
            ];
        } else {
            challengeToChallengeStatus[_challengeId] = STATUS_CHALLENGER_LOST;
            totalAmountToSplit = challengeToTotalAmountBetFor[_challengeId];
            totalAmountBetCorrectly = challengeToTotalAmountBetAgainst[
                _challengeId
            ];
        }

        // Make sure we avoid division by zero
        if (totalAmountBetCorrectly == 0) {
            challengeToWinningsPaid[_challengeId] = totalAmountToSplit;
            return;
        }

        // Process bettors in batches to avoid hitting gas limits
        uint256 batchSize = 10; // Can be adjusted based on gas analysis
        uint256 numBatches = (bettorsLength + batchSize - 1) / batchSize;

        for (uint256 batch = 0; batch < numBatches; ) {
            uint256 startIdx = batch * batchSize;
            uint256 endIdx = startIdx + batchSize;
            if (endIdx > bettorsLength) {
                endIdx = bettorsLength;
            }

            for (uint256 i = startIdx; i < endIdx; ) {
                address bettor = bettors[i];
                uint256 betAmount = challengeWon
                    ? challengeToBetsFor[_challengeId][bettor]
                    : challengeToBetsAgainst[_challengeId][bettor];
                
                if (betAmount > 0) {
                    uint256 share = (betAmount * totalAmountToSplit) /
                        totalAmountBetCorrectly;
                    
                    // Use a try/catch to handle potential failures during withdrawal
                    try vault.withdrawFunds(payable(bettor), betAmount + share, false) {
                        emit WinningsDistributed(_challengeId, bettor, share);
                    } catch {
                        // Log the failure but continue processing other bettors
                        emit WinningsDistributionFailed(_challengeId, bettor, betAmount + share);
                    }
                }
                unchecked {
                    i++;
                }
            }
            unchecked {
                batch++;
            }
        }

        challengeToWinningsPaid[_challengeId] = totalAmountToSplit;
    }

    // ============================ //
    //      Contract Functions      //
    // ============================ //

    function getLatestPrice() public view returns (uint256) {
        (
            uint80 roundId,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = dataFeed.latestRoundData();
        
        // Check for stale data
        if(timeStamp <= 0) {
            revert PriceFeedRoundNotComplete();
        }
        if(answeredInRound < roundId) {
            revert StalePrice();
        }
        
        // Check if the price feed is stale (older than 24 hours)
        if(block.timestamp - timeStamp > 24 hours) {
            revert PriceFeedTooOld();
        }
        
        // Price must be positive
        if(price < 0) {
            revert InvalidPrice();
        }
        
        return uint256(price) * 1e6;
    }

    // ============================ //
    //          Pausable            //
    // ============================ //

    /**
     * @notice Pauses the contract, disabling all state-changing functions.
     * @dev Can only be called by an account with the admin role.
     *
     * @dev Pausing mechanisms are useful in emergency scenarios to prevent further interactions.
     *
     * Requirements:
     * - The caller must have the admin role.
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    /**
     * @notice Unpauses the contract, enabling all state-changing functions.
     * @dev Can only be called by an account with the admin role.
     *
     * @dev Unpausing restores normal contract functionality after an emergency pause.
     *
     * Requirements:
     * - The caller must have the admin role.
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    // ============================ //
    //          Overrides           //
    // ============================ //

    /**
     * @dev Authorizes contract upgrades by restricting them to admin accounts.
     * @param newImplementation The address of the new contract implementation.
     *
     * Requirements:
     * - The caller must have the admin role.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
