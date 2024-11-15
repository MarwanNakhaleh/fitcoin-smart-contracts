// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IChallengeContract.sol";

contract ChallengeContract is Ownable, ReentrancyGuard, IChallengeContract {
    // the 
    AggregatorV3Interface internal dataFeed;

    /// @notice ETH/USD exchange rate on Base Mainnet
    address internal dataFeedAddress = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    /// @notice the minimum number of betters on a challenge
    uint256 constant MINIMUM_NUMBER_OF_BETTERS = 1;

    /// @notice the minimum value in USD of a bet on a challenge, either from the challenger or someone betting against him
    /// TODO: match the USD number coming in to the actual amount of ETH needed at the time of calculation
    uint256 public minimumUsdValueOfBet;

    /// @notice Mapping of challenger addresses to the challenge they have live
    mapping(address => Challenge) public challenges;
    
    /// @notice Whitelisted challengers who can participate in challenges
    mapping(address => bool) public challengerWhitelist;

    /// @notice Whitelisted bettors who can bet on challenges
    mapping(address => bool) public bettorWhitelist;

    uint256 newestChallengeId;

    modifier onlyChallengers() {
        require(challengerWhitelist[msg.sender], "You are not an eligible challenger!");
        _;
    }

    modifier onlyBettors() {
        require(bettorWhitelist[msg.sender], "You are not eligible to bet on challenges!");
        _;
    }

    modifier challengeCanBeModified() {
        require(challenges[msg.sender].status != ChallengeStatus.Active, "The challenger already has an active challenge!");
        require(challenges[msg.sender].numberOfBettorsAgainst == 0, "People are already betting, there's no stopping the show!");
        _;
    }

    modifier betIsGreaterThanOrEqualToMinimumBetValue()  {
        require(msg.value >= minimumUsdValueOfBet, "Amount is less than minimum bet!");
        _;
    }

    constructor(uint256 _minimumBetValue) Ownable(msg.sender) {
        minimumUsdValueOfBet = _minimumBetValue;
        dataFeed = AggregatorV3Interface(dataFeedAddress);
    }

    function addNewChallenger(address challenger) external onlyOwner {
        require(challengerWhitelist[challenger] == false, "User is already a challenger!");
        challengerWhitelist[challenger] = true;
        bettorWhitelist[challenger] = true;
    }

    function addNewBettor(address challenger) external onlyOwner {
        require(bettorWhitelist[challenger] == false, "User is already a bettor!");
        bettorWhitelist[challenger] = true;
    }

    function removeChallenger(address challenger) external onlyOwner {
        require(challengerWhitelist[challenger] == true, "Non-existent challenger cannot be removed!");
        challengerWhitelist[challenger] = false;
    }

    function changeMinimumBetValue(uint256 newMinimumValue) external onlyOwner {
        minimumUsdValueOfBet = newMinimumValue;
    }

    /// @notice Creates a new challenge for a whitelisted challenger, but does not start a challenge until requirements are met
    /// @param _lengthOfChallenge The time length of the challenge in seconds
    /// @param _challengeType The type of challenge the challenger wants to complete
    /// @param _targetMeasurement the goal for the challenger to reach
    function createChallenge(uint256 _lengthOfChallenge, ChallengeType _challengeType, uint256 _targetMeasurement) 
        external 
        onlyChallengers
        challengeCanBeModified
    {
        challenges[msg.sender].challengeLength = _lengthOfChallenge;
        challenges[msg.sender].challengeType = _challengeType;
        challenges[msg.sender].targetMeasurement = _targetMeasurement;
        challenges[msg.sender].status = ChallengeStatus.NotStarted;
    }

    /// @notice Provides the information necessary to start a challenge
    /// @param _initialMeasurement An initial value on top of which the challenger will have to add his challenge information 
    function startChallenge(uint256 _initialMeasurement)
        external
        onlyChallengers
    {
        require(challenges[msg.sender].betsFor[msg.sender] > 0, "Challenger has not bet on his challenge yet!");
        require(challenges[msg.sender].numberOfBettorsAgainst >= MINIMUM_NUMBER_OF_BETTERS, "Not enough people have bet on the challenge for it to start!");

        challenges[msg.sender].status = ChallengeStatus.Active;
        challenges[msg.sender].initialMeasurement = _initialMeasurement;
        challenges[msg.sender].startTime = block.timestamp;
    }

    /// @notice Place a bet for or against a challenge
    /// @param _challenger The address of the challenger whose challenge to bet on
    /// @param _bettingFor A boolean to indicate betting for (true) or against (false) the challenger
    function placeBet(address _challenger, bool _bettingFor) 
        public 
        payable 
        onlyBettors 
        betIsGreaterThanOrEqualToMinimumBetValue
        nonReentrant
    {
        require(challenges[_challenger].status == ChallengeStatus.NotStarted, "Challenge has already been started");
        require(challenges[_challenger].betsFor[msg.sender] == 0 && challenges[_challenger].betsAgainst[msg.sender] == 0, "Bettor has already placed a bet on this challenge!");

        if(_bettingFor) {
            challenges[_challenger].numberOfBettorsFor += 1;
            challenges[_challenger].betsFor[msg.sender] = uint256(msg.value);
            challenges[_challenger].totalAmountBetFor += uint256(msg.value);
        } else {
            challenges[_challenger].numberOfBettorsAgainst += 1;
            challenges[_challenger].betsAgainst[msg.sender] = uint256(msg.value);
            challenges[_challenger].totalAmountBetAgainst += uint256(msg.value);
        }

        challenges[_challenger].bettors.push(msg.sender);
    }

    /// @notice Provides data to determine if a challenger has succeeded
    /// @param _challenger The challenger for whom the measurement applies
    /// @param _submittedMeasurement A submitted value to show progress on a challenge
    function submitMeasurement(address _challenger, uint256 _submittedMeasurement)
        external
        onlyOwner
        nonReentrant 
    {
        require(challenges[_challenger].status == ChallengeStatus.Active, "Challenge is not eligible to receive measurements!");
        require(challenges[_challenger].startTime + challenges[_challenger].challengeLength >= block.timestamp, "Challenge time window has expired.");

        challenges[_challenger].finalMeasurement = _submittedMeasurement;
    }
    
    function getLatestPrice() public view returns (uint256) {
        (, int price,,,) = dataFeed.latestRoundData();
        return uint256(price) * 1e6;
    }

    function distributeWinnings(address payable challenger) external onlyOwner {
        require(challenges[challenger].status == ChallengeStatus.Active, "Challenge is not eligible for distribution!");
        require(block.timestamp >= challenges[challenger].startTime + challenges[challenger].challengeLength, "Challenge time has not elapsed!");

        challenges[challenger].status = ChallengeStatus.Expired;

        bool challengerWon = challenges[challenger].finalMeasurement >= challenges[challenger].targetMeasurement;
        uint256 totalLosingSideAmount = challengerWon ? challenges[challenger].totalAmountBetAgainst : challenges[challenger].totalAmountBetFor;

        for (uint256 i = 0; i < challenges[challenger].bettors.length; i++) {
            address bettor = challenges[challenger].bettors[i];
            uint256 bettorAmount = challengerWon ? challenges[challenger].betsFor[bettor] : challenges[challenger].betsAgainst[bettor];

            if (bettorAmount > 0) {
                uint256 winnings = bettorAmount + (totalLosingSideAmount * bettorAmount / (challengerWon ? challenges[challenger].totalAmountBetFor : challenges[challenger].totalAmountBetAgainst));
                payable(bettor).transfer(winnings);
            }
        }
    }
}
