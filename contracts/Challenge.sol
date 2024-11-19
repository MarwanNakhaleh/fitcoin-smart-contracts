// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IChallenge.sol";

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
    uint8 constant CHALLENGE_CYCLING = 2;
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

    /// @notice the minimum number of total bettors on a challenge
    uint256 constant MINIMUM_NUMBER_OF_BETTORS_AGAINST = 1;
    
    /// @notice ETH/USD exchange rate on Base Mainnet
    // address internal dataFeedAddress = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    /// @notice the minimum value in USD of a bet on a challenge, either from the challenger or someone betting against him
    /// TODO: match the USD number coming in to the actual amount of ETH needed at the time of calculation
    uint256 internal minimumUsdValueOfBet;

    uint32 constant internal maximumNumberOfBettorsPerChallenge = 100;

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
    mapping(uint256 => uint8) public challengeToWinningsPaid;

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
    mapping(uint256 => mapping(address => uint256)) public challengeToBetsAgainst;
    mapping(uint256 => address[]) public challengeToBettors;

    // ============================ //
    //           Errors             //
    // ============================ //

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
    error ChallengeCanOnlyBeModifiedByChallenger(uint256 challengeId, address caller, address challenger);

    /// @dev Error thrown when a challenge is already active when it must be inactive for the action requested
    error ChallengeIsActive(uint256 activeChallengeId);

    /// @dev Error thrown when a challenge is not active when it must be active for the action requested
    error ChallengeIsNotActive(uint256 challengeId);

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

    modifier betIsGreaterThanOrEqualToMinimumBetValue()  {
        require(msg.value >= minimumUsdValueOfBet, "Amount is less than minimum bet!");
        _;
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
        address _dataFeedAddress
    ) external initializer {
        if (_minimumBetValue == 0) revert MinimumBetAmountTooSmall();
        __Ownable_init(msg.sender);
        transferOwnership(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        minimumUsdValueOfBet = _minimumBetValue;
        dataFeed = AggregatorV3Interface(_dataFeedAddress);
        latestChallengeId = 0;

        emit MinimumBetValueSet(0, _minimumBetValue);
    }

    // ============================ //
    //      Interface Functions     //
    // ============================ //

    /**
     * @inheritdoc IChallenge
     */
    function getChallengesForChallenger(address challenger) external view returns (uint256[] memory) {
        return challengerToChallenges[challenger];
    }

    /**
     * @inheritdoc IChallenge
     */
    function addNewChallenger(address challenger) external onlyOwner {
        if (challengerWhitelist[challenger]) revert ChallengerAlreadyInWhitelist();

        challengerWhitelist[challenger] = true;
        bettorWhitelist[challenger] = true;
        
        emit ChallengerJoined(challenger);
        emit BettorJoined(challenger); // a user allowed to create challenges is also by default allowed to bet
    }

    /**
     * @inheritdoc IChallenge
     */
    function addNewBettor(address bettor) external onlyOwner {
        if (bettorWhitelist[bettor]) revert BettorAlreadyInWhitelist();
        
        bettorWhitelist[bettor] = true;
        
        emit BettorJoined(bettor);
    }

    /**
     * @inheritdoc IChallenge
     */
    function removeChallenger(address challenger) external onlyOwner {
        if (!challengerWhitelist[challenger]) revert ChallengerNotInWhitelist();

        challengerWhitelist[challenger] = false;

        emit ChallengerRemoved(challenger);
    }

    /**
     * @inheritdoc IChallenge
     */
    function changeMinimumBetValue(uint256 _newMinimumValue) external onlyOwner {
        if (_newMinimumValue == 0) revert MinimumBetAmountTooSmall();

        minimumUsdValueOfBet = _newMinimumValue;
    }

    /**
     * @inheritdoc IChallenge
     */
    function createChallenge(uint256 _lengthOfChallenge, uint8[] calldata _challengeMetrics, uint256[] calldata _targetMeasurementsForEachMetric)
        external
        override
        nonReentrant
        onlyChallengers(msg.sender)
        returns(uint256)
    {
        address challenger = msg.sender;

        if (_challengeMetrics.length != _targetMeasurementsForEachMetric.length) revert MalformedChallengeMetricsProvided();

        uint256 currentChallengeId = latestChallengeId;
        unchecked {
            latestChallengeId++;
        }

        challengeToChallenger[currentChallengeId] = challenger;
        challengerToChallenges[challenger].push(currentChallengeId);
        
        for (uint256 i = 0; i < _challengeMetrics.length; ) {
            challengeToTargetMetricMeasurements[currentChallengeId][_challengeMetrics[i]] = _targetMeasurementsForEachMetric[i];
            challengeToIncludedMetrics[currentChallengeId].push(_challengeMetrics[i]);
            unchecked {
                i++;
            }
        }
        challengeToChallengeLength[currentChallengeId] = _lengthOfChallenge;
        challengeToChallengeStatus[currentChallengeId] = STATUS_INACTIVE;
        
        return currentChallengeId;
    }

    /**
     * @inheritdoc IChallenge
     */
    function startChallenge(uint256 _challengeId)
        external
        override
        nonReentrant
        onlyChallengers(msg.sender)
    {
        address challenger = msg.sender;

        if (challengeToChallengeStatus[_challengeId] != STATUS_INACTIVE) revert ChallengeIsActive(_challengeId);
        if (challengeToTotalAmountBetAgainst[_challengeId] == 0) revert NobodyBettingAgainstChallenger();
        if (challengeToTotalAmountBetFor[_challengeId] == 0) revert NobodyBettingForChallenger();

        challengeToChallengeStatus[_challengeId] = STATUS_ACTIVE;
        challengeToStartTime[_challengeId] = block.timestamp;
        challengerToActiveChallenge[challenger] = _challengeId;
    }

    // TODO: Refactor so that the value is locked in a vault rather than paid to the contract
    /**
     * @inheritdoc IChallenge
     */
    function placeBet(uint256 _challengeId, bool _bettingFor) 
        external 
        payable 
        nonReentrant
        onlyBettors(msg.sender)
    {
        if (challengeToChallengeStatus[_challengeId] == STATUS_ACTIVE) revert ChallengeIsActive(_challengeId);
        unchecked {
            uint256 totalBettorsOnChallenge = challengeToNumberOfBettorsFor[_challengeId] + challengeToNumberOfBettorsAgainst[_challengeId];
            if (totalBettorsOnChallenge >= maximumNumberOfBettorsPerChallenge) revert TooManyBettors();
        }
        
        address caller = msg.sender;
        if (challengeToChallenger[_challengeId] == caller && !_bettingFor) revert ChallengerCannotBetAgainstHimself();
        if (challengeToBetsFor[_challengeId][caller] != 0 || challengeToBetsAgainst[_challengeId][caller] != 0) revert BettorCannotUpdateBet();
        
        uint256 value = msg.value;

        if(_bettingFor) {
            unchecked {
                challengeToNumberOfBettorsFor[_challengeId] += 1;
                challengeToTotalAmountBetFor[_challengeId] += uint256(value);
            }
            challengeToBetsFor[_challengeId][caller] = uint256(value);
        } else {
            unchecked {
                challengeToNumberOfBettorsAgainst[_challengeId] += 1;
                challengeToTotalAmountBetAgainst[_challengeId] += uint256(value);
            }
            challengeToBetsAgainst[_challengeId][caller] = uint256(value);
        }

        challengeToBettors[_challengeId].push(caller);
        
        emit BetPlaced(_challengeId, caller, _bettingFor, value);
    }

    /**
     * @inheritdoc IChallenge
     */
    function changeBet(uint256 _challengeId, bool _bettingFor) 
        external 
        payable 
        nonReentrant
        onlyBettors(msg.sender)
    {
        address caller = msg.sender;
        if (challengeToBetsFor[_challengeId][caller] == 0 && challengeToBetsAgainst[_challengeId][caller] == 0) revert BettorCannotUpdateBet();
    }

    /**
     * @inheritdoc IChallenge
     */
    function submitMeasurements(uint256 _challengeId, uint256[] calldata _submittedMeasurements)
        external
        onlyChallengers(msg.sender)
        nonReentrant 
    {
        if (challengeToIncludedMetrics[_challengeId].length != _submittedMeasurements.length) revert MalformedChallengeMetricsProvided();
        if (challengeToChallengeStatus[_challengeId] != STATUS_ACTIVE) revert ChallengeIsNotActive(_challengeId);

        uint256 timestamp = block.timestamp;
        unchecked {
            if (challengeToStartTime[_challengeId] + challengeToChallengeLength[_challengeId] >= timestamp){
                challengeToChallengeStatus[_challengeId] = STATUS_EXPIRED;
                revert ChallengeIsNotActive(_challengeId);
            }
        }

        for (uint256 i = 0; i < _submittedMeasurements.length; ) {
            uint8 currentMetric = challengeToIncludedMetrics[_challengeId][i];
            challengeToTargetMetricMeasurements[_challengeId][currentMetric] = _submittedMeasurements[i];
            unchecked {
                i++;
            }
        }
    }

    function distributeWinnings(uint256 _challengeId) external onlyOwner {
        if (challengeToChallengeStatus[_challengeId] == STATUS_ACTIVE) revert ChallengeIsActive(_challengeId);
        if (challengeToWinningsPaid[_challengeId] > 0) revert WinningsAlreadyPaid(_challengeId);

        challengeToChallengeStatus[_challengeId] == STATUS_EXPIRED;

        bool challengeWon = true;
        for(uint8 i = 0; i < challengeToIncludedMetrics[_challengeId].length; ) {
            if (challengeToFinalMetricMeasurements[_challengeId][i] < challengeToTargetMetricMeasurements[_challengeId][i]) {
                challengeWon = false;
                break;
            }
            unchecked {
                i++;
            }
        }
        
        // TODO: Distribute winnings from the vault
    }
    
    // ============================ //
    //      Contract Functions      //
    // ============================ //

    function getLatestPrice() public view returns (uint256) {
        (, int price,,,) = dataFeed.latestRoundData();
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
    function pause() external onlyOwner {
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
    function unpause() external onlyOwner {
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
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
