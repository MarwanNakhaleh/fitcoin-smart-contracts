// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IChallenge.sol";
import "./interfaces/IVault.sol";

import "./libraries/ChallengeData.sol";
import "./libraries/ChallengeBetting.sol";
import "./libraries/PriceDataFeed.sol";

contract Challenge is
    IChallenge,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable
{
    using ChallengeData for *;
    using ChallengeBetting for *;
    using PriceDataFeed for *;

    // Instead of trying to use a struct with mappings, let's use the flattened bets mapping directly
    mapping(bytes32 => uint256) internal flattenedBets;


     // ============================ //
    //      State Variables         //
    // ============================ //

    /// @notice the minimum number of total bettors on a challenge
    uint256 constant MINIMUM_NUMBER_OF_BETTORS_AGAINST = 1;

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

    mapping(uint256 => address[]) public challengeToBettors;

    /// @notice the data feed allowing us to determine the current price of ETH to set a minimum amount of ETH required to fulfill the minimum USD value of the bet
    AggregatorV3Interface internal dataFeed;

    /// @notice the vault contract
    IVault internal vault;

    // ============================ //
    //          Modifiers           //
    // ============================ //

    modifier onlyChallengers(address _address) {
        if (!challengerWhitelist[_address])
            revert ChallengeData.ChallengerNotInWhitelist();
        _;
    }

    modifier onlyBettors(address _address) {
        if (!bettorWhitelist[_address])
            revert ChallengeData.BettorNotInWhitelist();
        _;
    }

    modifier betIsGreaterThanOrEqualToMinimumBetValue() {
        uint256 ethPrice = PriceDataFeed.getLatestPrice(dataFeed);
        if (!ChallengeBetting.isBetAmountValid(msg.value, ethPrice, minimumUsdValueOfBet))
            revert ChallengeData.MinimumBetAmountTooSmall();
        _;
    }

    modifier checkBettingEligibility(uint256 _challengeId) {
        if (!bettorWhitelist[msg.sender]) {
            revert ChallengeData.BettorNotInWhitelist();
        }
        if (address(vault) == address(0)) {
            revert ChallengeData.VaultNotSet();
        }
        if (
            challengeToChallengeStatus[_challengeId] !=
            ChallengeData.STATUS_INACTIVE
        ) {
            revert ChallengeData.ChallengeCannotBeModified();
        }
        _;
    }

    // ============================ //
    //         Setters              //
    // ============================ //

    /// @notice Sets the vault contract
    function setVault(address _vault) external onlyOwner whenNotPaused {
        if (_vault == address(0)) revert ChallengeData.VaultNotSet();
        vault = IVault(_vault);
    }

    /// @notice Sets the maximum number of bettors per challenge
    function setMaximumNumberOfBettorsPerChallenge(
        uint32 _maximumNumberOfBettorsPerChallenge
    ) external onlyOwner whenNotPaused {
        if (
            _maximumNumberOfBettorsPerChallenge <
            (ChallengeData.MINIMUM_NUMBER_OF_BETTORS_AGAINST + 1)
        ) revert ChallengeData.MaximumNumberOfBettorsPerChallengeTooSmall();
        maximumNumberOfBettorsPerChallenge = _maximumNumberOfBettorsPerChallenge;
        emit MaximumNumberOfBettorsPerChallengeSet(
            maximumNumberOfBettorsPerChallenge,
            _maximumNumberOfBettorsPerChallenge
        );
    }

    /// @notice Sets the maximum number of bettors per challenge
    function setMaximumChallengeLength(
        uint32 _maximumChallengeLengthInSeconds
    ) external onlyOwner whenNotPaused {
        if (_maximumChallengeLengthInSeconds == 0)
            revert ChallengeData.ChallengeLengthTooShort();
        maximumChallengeLengthInSeconds = _maximumChallengeLengthInSeconds;
        emit MaximumChallengeLengthSet(
            maximumChallengeLengthInSeconds,
            _maximumChallengeLengthInSeconds
        );
    }

    /// @notice Sets the maximum number of challenge metrics
    function setMaximumNumberOfChallengeMetrics(
        uint8 _maximumNumberOfChallengeMetrics
    ) external onlyOwner whenNotPaused {
        if (_maximumNumberOfChallengeMetrics == 0)
            revert ChallengeData.MaximumNumberOfChallengeMetricsTooSmall();
        maximumNumberOfChallengeMetrics = _maximumNumberOfChallengeMetrics;
        emit MaximumNumberOfChallengeMetricsSet(
            maximumNumberOfChallengeMetrics,
            _maximumNumberOfChallengeMetrics
        );
    }

    /**
     * @inheritdoc IChallenge
     */
    function setMinimumBetValue(
        uint256 _newMinimumValue
    ) external virtual override onlyOwner whenNotPaused {
        if (_newMinimumValue == 0)
            revert ChallengeData.MinimumBetAmountTooSmall();
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
    function getMaximumNumberOfBettorsPerChallenge()
        external
        view
        returns (uint32)
    {
        return maximumNumberOfBettorsPerChallenge;
    }

    /// @notice Gets the maximum challenge length
    function getMaximumChallengeLength() external view returns (uint32) {
        return maximumChallengeLengthInSeconds;
    }

    /// @notice Gets the maximum number of challenge metrics
    function getMaximumNumberOfChallengeMetrics()
        external
        view
        returns (uint8)
    {
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
        if (_minimumBetValue == 0)
            revert ChallengeData.MinimumBetAmountTooSmall();
        if (
            _maximumNumberOfBettorsPerChallenge <
            (ChallengeData.MINIMUM_NUMBER_OF_BETTORS_AGAINST + 1)
        ) revert ChallengeData.MaximumNumberOfBettorsPerChallengeTooSmall();
        if (_maximumChallengeLengthInSeconds == 0)
            revert ChallengeData.ChallengeLengthTooShort();
        if (_maximumNumberOfChallengeMetrics == 0)
            revert ChallengeData.MaximumNumberOfChallengeMetricsTooSmall();
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
        // The flattened bets mapping doesn't need initialization
        
        emit MinimumBetValueSet(0, _minimumBetValue);
        emit MaximumNumberOfBettorsPerChallengeSet(
            0,
            _maximumNumberOfBettorsPerChallenge
        );
        emit MaximumChallengeLengthSet(0, _maximumChallengeLengthInSeconds);
        emit MaximumNumberOfChallengeMetricsSet(
            0,
            _maximumNumberOfChallengeMetrics
        );
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
            revert ChallengeData.ChallengerAlreadyInWhitelist();

        challengerWhitelist[challenger] = true;
        bettorWhitelist[challenger] = true;

        emit ChallengerJoined(challenger);
        emit BettorJoined(challenger); // a user allowed to create challenges is also by default allowed to bet
    }

    /**
     * @inheritdoc IChallenge
     */
    function addNewBettor(
        address bettor
    ) public virtual override onlyOwner whenNotPaused {
        if (bettorWhitelist[bettor])
            revert ChallengeData.BettorAlreadyInWhitelist();

        bettorWhitelist[bettor] = true;

        emit BettorJoined(bettor);
    }

    /**
     * @inheritdoc IChallenge
     */
    function removeChallenger(
        address challenger
    ) external virtual override onlyOwner whenNotPaused {
        if (!challengerWhitelist[challenger])
            revert ChallengeData.ChallengerNotInWhitelist();

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
            revert ChallengeData.ChallengeLengthTooLong();
        if (
            _challengeMetrics.length == 0 ||
            _challengeMetrics.length != _targetMeasurementsForEachMetric.length
        ) revert ChallengeData.MalformedChallengeMetricsProvided();
        if (_challengeMetrics.length > maximumNumberOfChallengeMetrics)
            revert ChallengeData.TooManyChallengeMetrics();

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
        challengeToChallengeStatus[currentChallengeId] = ChallengeData
            .STATUS_INACTIVE;

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
            revert ChallengeData.OnlyChallengerCanStartChallenge();
        }
        if (
            challengeToChallengeStatus[_challengeId] !=
            ChallengeData.STATUS_INACTIVE
        ) revert ChallengeData.ChallengeIsActive(_challengeId);
        if (challengeToTotalAmountBetAgainst[_challengeId] == 0)
            revert ChallengeData.NobodyBettingAgainstChallenger();
        if (challengeToTotalAmountBetFor[_challengeId] == 0)
            revert ChallengeData.NobodyBettingForChallenger();

        challengeToChallengeStatus[_challengeId] = ChallengeData.STATUS_ACTIVE;
        challengeToStartTime[_challengeId] = block.timestamp;
        challengerToActiveChallenge[challenger] = _challengeId;
    }

    /**
     * @inheritdoc IChallenge
     */
    function placeBet(
        uint256 _challengeId,
        bool _bettingFor
    )
        public
        payable
        virtual
        override
        nonReentrant
        checkBettingEligibility(_challengeId)
        betIsGreaterThanOrEqualToMinimumBetValue
        whenNotPaused
    {
        if (
            challengeToChallengeStatus[_challengeId] ==
            ChallengeData.STATUS_ACTIVE
        ) revert ChallengeData.ChallengeIsActive(_challengeId);
        if (msg.value < minimumUsdValueOfBet)
            revert ChallengeData.MinimumBetAmountTooSmall();
        if (address(vault) == address(0)) revert ChallengeData.VaultNotSet();

        unchecked {
            uint256 totalBettorsOnChallenge = challengeToNumberOfBettorsFor[
                _challengeId
            ] + challengeToNumberOfBettorsAgainst[_challengeId];
            if (totalBettorsOnChallenge >= maximumNumberOfBettorsPerChallenge)
                revert ChallengeData.TooManyBettors();
        }

        address caller = msg.sender;
        if (challengeToChallenger[_challengeId] == caller && !_bettingFor)
            revert ChallengeData.ChallengerCannotBetAgainstHimself();
        
        // Check if bettor already has a bet
        if (
            getBetAmount(_challengeId, caller, true) != 0 ||
            getBetAmount(_challengeId, caller, false) != 0
        ) revert ChallengeData.BettorCannotUpdateBet();

        // Process the bet
        vault.depositETH{value: msg.value}();

        // Store bet in flattened mapping
        bytes32 betKey = _getBetKey(_challengeId, caller, _bettingFor);
        flattenedBets[betKey] = msg.value;
        
        if (_bettingFor) {
            challengeToNumberOfBettorsFor[_challengeId] += 1;
            challengeToTotalAmountBetFor[_challengeId] += msg.value;
        } else {
            challengeToNumberOfBettorsAgainst[_challengeId] += 1;
            challengeToTotalAmountBetAgainst[_challengeId] += msg.value;
        }

        challengeToBettors[_challengeId].push(caller);

        emit BetPlaced(_challengeId, caller, _bettingFor, msg.value);
    }

    /**
     * @inheritdoc IChallenge
     */
    function submitMeasurements(
        uint256 _challengeId,
        uint256[] calldata _submittedMeasurements
    )
        external
        virtual
        override
        onlyChallengers(msg.sender)
        nonReentrant
        whenNotPaused
    {
        address caller = msg.sender;
        if (challengeToChallenger[_challengeId] != caller)
            revert ChallengeData.ChallengeCanOnlyBeModifiedByChallenger(
                _challengeId,
                caller,
                challengeToChallenger[_challengeId]
            );

        if (
            challengeToIncludedMetrics[_challengeId].length !=
            _submittedMeasurements.length
        ) revert ChallengeData.MalformedChallengeMetricsProvided();
        if (
            challengeToChallengeStatus[_challengeId] !=
            ChallengeData.STATUS_ACTIVE
        )
            revert ChallengeData.ChallengeIsNotActive(
                _challengeId,
                challengeToChallengeStatus[_challengeId]
            );

        uint256 timestamp = block.timestamp;
        if (
            timestamp >=
            (challengeToStartTime[_challengeId] +
                challengeToChallengeLength[_challengeId])
        ) {
            challengeToChallengeStatus[_challengeId] = ChallengeData
                .STATUS_EXPIRED;
            revert ChallengeData.ChallengeIsExpired(_challengeId);
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

    function distributeWinnings(
        uint256 _challengeId
    ) public virtual override onlyOwner whenNotPaused {
        if (address(vault) == address(0)) revert ChallengeData.VaultNotSet();

        uint256 timestamp = block.timestamp;
        if (
            timestamp <
            (challengeToStartTime[_challengeId] +
                challengeToChallengeLength[_challengeId])
        ) {
            revert ChallengeData.ChallengeIsActive(_challengeId);
        }

        if (
            challengeToChallengeStatus[_challengeId] !=
            ChallengeData.STATUS_EXPIRED
        ) {
            challengeToChallengeStatus[_challengeId] = ChallengeData
                .STATUS_EXPIRED;
        }

        if (challengeToWinningsPaid[_challengeId] > 0)
            revert ChallengeData.WinningsAlreadyPaid(_challengeId);

        // Determine if challenge was won
        bool challengeWon = ChallengeBetting.determineChallengeOutcome(
            _challengeId,
            challengeToIncludedMetrics,
            challengeToFinalMetricMeasurements,
            challengeToTargetMetricMeasurements
        );

        // Update status
        if (challengeWon) {
            challengeToChallengeStatus[_challengeId] = ChallengeData.STATUS_CHALLENGER_WON;
        } else {
            challengeToChallengeStatus[_challengeId] = ChallengeData.STATUS_CHALLENGER_LOST;
        }

        // Calculate distribution amounts
        uint256 winningPool;
        uint256 totalCorrectBets;
        
        if (challengeWon) {
            winningPool = challengeToTotalAmountBetAgainst[_challengeId];
            totalCorrectBets = challengeToTotalAmountBetFor[_challengeId];
        } else {
            winningPool = challengeToTotalAmountBetFor[_challengeId];
            totalCorrectBets = challengeToTotalAmountBetAgainst[_challengeId];
        }
        
        // Skip if no correct bets
        if (totalCorrectBets == 0) return;

        // Process distributions
        address[] memory bettors = challengeToBettors[_challengeId];
        uint256 bettorsCount = bettors.length;
        
        // Process in small batches
        uint256 batchSize = 3;
        for (uint256 i = 0; i < bettorsCount;) {
            uint256 endIdx = i + batchSize;
            if (endIdx > bettorsCount) {
                endIdx = bettorsCount;
            }
            
            _processBatch(
                _challengeId,
                i,
                endIdx,
                challengeWon,
                winningPool,
                totalCorrectBets,
                bettors
            );
            
            i = endIdx;
        }

        challengeToWinningsPaid[_challengeId] = challengeWon 
            ? challengeToTotalAmountBetAgainst[_challengeId] 
            : challengeToTotalAmountBetFor[_challengeId];
    }
    
    /**
     * @notice Processes a batch of bettors for winnings distribution
     */
    function _processBatch(
        uint256 _challengeId,
        uint256 _startIdx,
        uint256 _endIdx,
        bool _challengeWon,
        uint256 _winningPool,
        uint256 _totalCorrectBets,
        address[] memory _bettors
    ) private {
        for (uint256 i = _startIdx; i < _endIdx;) {
            address bettor = _bettors[i];
            uint256 betAmount = getBetAmount(_challengeId, bettor, _challengeWon);
            
            if (betAmount > 0) {
                uint256 share = (betAmount * _winningPool) / _totalCorrectBets;
                try vault.withdrawFunds(payable(bettor), betAmount + share, false) {} catch {}
            }
            unchecked { i++; }
        }
    }

    function getLatestPrice() public view returns (uint256) {
        return PriceDataFeed.getLatestPrice(dataFeed);
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

    /**
     * @notice Gets a unique key for storing bet information
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
        bool _isBettingFor
    ) public view returns (uint256) {
        bytes32 key = _getBetKey(_challengeId, _bettor, _isBettingFor);
        return flattenedBets[key];
    }
}
