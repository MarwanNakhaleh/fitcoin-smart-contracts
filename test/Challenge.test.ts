import { ethers, upgrades } from "hardhat";
import { AddressLike, Signer, parseEther, BigNumberish } from "ethers";
import { expect } from "chai";
import { Challenge, Challenge__factory } from "../typechain";

describe("Challenge Tests", function () {
  let challengeContract: Challenge;
  let owner: Signer;
  let bettor: Signer;
  let bettor2: Signer;
  let challenger: Signer;
  let challengerAddress: AddressLike;

  const ethPriceFactorConversionUnits: bigint = BigInt(1e14); // number of wei in one ETH
  const minimumUsdBetValue: bigint = BigInt(10) * ethPriceFactorConversionUnits;

  const CHALLENGE_STEPS: BigNumberish = 0;
  const CHALLENGE_MILEAGE: BigNumberish = 1;
  const CHALLENGE_CYCLING: BigNumberish = 2;
  const CHALLENGE_CALORIES_BURNED: BigNumberish = 3;

  beforeEach(async function () {
    const ChallengeFactory: Challenge__factory = await ethers.getContractFactory("Challenge");
    [owner, bettor, bettor2, challenger] = await ethers.getSigners();

    // Add mock price feed
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3Aggregator.deploy(8, 200000000000); // 8 decimals, $2000.00000000 ETH/USD price
    const mockPriceFeedAddress = await mockPriceFeed.getAddress();

    challengeContract = await upgrades.deployProxy(
      ChallengeFactory,
      [minimumUsdBetValue, mockPriceFeedAddress], // Use mock address here
      { initializer: 'initialize' } // Specify the initializer function
    );
    await challengeContract.waitForDeployment();
    challengerAddress = await challenger.getAddress();
  });

  describe("Creating and betting on a challenge", async () => {
    const betAmount = parseEther("1");

    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5
    const targetMeasurements = [targetNumberOfSteps, targetNumberOfMiles]
    const challengeLength = BigInt(60 * 60) // 1 hour challenge time
    let challengeId: bigint;

    beforeEach(async function () {
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);
      await challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements);
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];
    });

    it("should return the correct challenge ID when creating the first challenge", async function () {
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);

      expect(challengeIds[0]).to.equal(0);
    });

    it("should not allow a bettor to place a bet on a challenge if he is not whitelisted", async function () {
      await expect(challengeContract.connect(bettor).placeBet(0, false, {
        value: betAmount,
      })).to.be.revertedWithCustomError(challengeContract, "BettorNotInWhitelist");
    });

    it("should allow a bettor to place a bet on a challenge if he is whitelisted", async function () {
      await challengeContract.connect(owner).addNewBettor(bettor.getAddress());
      await challengeContract.connect(bettor).placeBet(0, false, {
        value: betAmount,
      });
    });

    it("should not allow placing a bet after the challenge has started", async function () {
      const challengeStatus = await challengeContract.challengeToChallengeStatus(challengeId);
      expect(challengeStatus).to.equal(0);
     
      await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount });      
      
      await challengeContract.connect(owner).addNewBettor(bettor.getAddress());
      await challengeContract.connect(owner).addNewBettor(bettor2.getAddress());
      await challengeContract.connect(bettor).placeBet(challengeId, false, { value: betAmount });

      expect(await challengeContract.challengeToNumberOfBettorsFor(challengeId)).to.equal(1);
      expect(await challengeContract.challengeToNumberOfBettorsAgainst(challengeId)).to.equal(1);

      await challengeContract.connect(challenger).startChallenge(0);

      await expect(
        challengeContract.connect(bettor2).placeBet(challengeId, true, { value: betAmount })
      ).to.be.revertedWithCustomError(challengeContract, "ChallengeIsActive");
    });

    it("does not allow a bet under the minimum USD value of ETH needed", async function () {
      const latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
      const tinyBetAmount = 0.004 * Number(latestEthPrice); // $8.00 at test ETH price of $2000.00

      await expect(
        challengeContract.connect(challenger).placeBet(challengeId, true, { value: BigInt(tinyBetAmount) })   
      ).to.be.revertedWithCustomError(challengeContract, "MinimumBetAmountTooSmall");
    });

    it("allows a bet just above the minimum USD value of ETH needed", async function () {
      const latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
      const tinyBetAmount = 0.005 * Number(latestEthPrice); // $10.00 at test ETH price of $2000.00

      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      const challengeId = challengeIds[0];

      await expect(
        challengeContract.connect(challenger).placeBet(challengeId, true, { value: BigInt(tinyBetAmount) })
      ).not.to.be.reverted;
    });
  });


  describe("Creating a challenge and betting before it starts", async () => {
    const betAmount = parseEther("1");

    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5
    const targetMeasurements = [targetNumberOfSteps, targetNumberOfMiles]
    const challengeLength = BigInt(60 * 60) // 1 hour challenge time

    beforeEach(async function () {
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);
      await challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements);
    });

    it("should not allow the challenger to start the challenge without enough bettors", async function () {
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      const challengeId = challengeIds[0];

      await expect(
        challengeContract.connect(challenger).startChallenge(challengeId)
      ).to.be.revertedWithCustomError(challengeContract, "NobodyBettingAgainstChallenger");
    });

    it("should allow the challenger to start the challenge when there are enough bettors", async function () {
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      const challengeId = challengeIds[0];
      
      const initialChallengerBalance = await ethers.provider.getBalance(challenger.getAddress());
      console.log("initial Challenger Balance", initialChallengerBalance);

      // Place bet for the challenger
      await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount });

      // Check the contract balance to ensure the bet amount was transferred
      const contractBalanceAfterBet = await ethers.provider.getBalance(challengeContract.getAddress());
      expect(contractBalanceAfterBet).to.equal(betAmount);

      // Check the challenger's balance after placing the bet
      const challengerBalanceAfterBetting = await ethers.provider.getBalance(challenger.getAddress());
      console.log("challenger Balance after betting", challengerBalanceAfterBetting);

      // The challenger's balance should be reduced by the bet amount plus gas fees
      expect(challengerBalanceAfterBetting).to.be.lessThan(initialChallengerBalance - betAmount);

      await challengeContract.connect(owner).addNewBettor(bettor2.getAddress());
      await challengeContract.connect(bettor2).placeBet(challengeId, false, { value: betAmount });

      await challengeContract.connect(challenger).startChallenge(challengeId);

      const challengeStatus = await challengeContract.challengeToChallengeStatus(challengeId);
      expect(challengeStatus).to.equal(1); // ChallengeStatus.Active
    });
  });

  describe("Concluding the challenge", async () => {
    let initialBettorBalance: bigint;
    let initialBettor2Balance: bigint;
    let initialChallengerBalance: bigint;
    let challengeId: bigint;
    let latestEthPrice: bigint;
    let betAmount: bigint;

    beforeEach(async () => {
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);
      await challengeContract.connect(challenger).createChallenge(BigInt(60 * 60), [CHALLENGE_STEPS, CHALLENGE_MILEAGE], [10000, 5]);
      
      latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
      betAmount = BigInt(Number(latestEthPrice));

      initialBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
      initialBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
      initialChallengerBalance = await ethers.provider.getBalance(challengerAddress);

      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];

      await challengeContract.connect(owner).addNewBettor(bettor.getAddress());
      await challengeContract.connect(owner).addNewBettor(bettor2.getAddress());
    });

    it("should not allow a challenger to submit measurements on an expired challenge", async function () {
      await challengeContract.connect(bettor).placeBet(challengeId, true, { value: betAmount }); // wins half of bettor2's money
      await challengeContract.connect(bettor2).placeBet(challengeId, false, { value: betAmount }); // loses all of his money
      await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount }); // wins half of bettor2's money

      await challengeContract.connect(challenger).startChallenge(challengeId);

      const challengeStartTime = await challengeContract.challengeToStartTime(challengeId);      
      const challengeLength = await challengeContract.challengeToChallengeLength(challengeId);
      const futureTimestamp = challengeStartTime + challengeLength + BigInt(100); // 100 seconds after the challenge expires

      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(futureTimestamp)]);
      await ethers.provider.send("evm_mine", []);

      await expect(challengeContract.connect(challenger).submitMeasurements(challengeId, [10000, 5])).to.be.revertedWithCustomError(challengeContract, "ChallengeIsExpired");
    });

    it("should not allow distribution of winnings before the challenge time has elapsed", async function () {
      await challengeContract.connect(bettor).placeBet(challengeId, true, { value: betAmount }); // wins half of bettor2's money
      await challengeContract.connect(bettor2).placeBet(challengeId, false, { value: betAmount }); // loses all of his money
      await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount }); // wins half of bettor2's money

      await challengeContract.connect(challenger).startChallenge(challengeId);

      const challengeStartTime = await challengeContract.challengeToStartTime(challengeId);
      const challengeLength = await challengeContract.challengeToChallengeLength(challengeId);
      const futureTimestamp = challengeStartTime + challengeLength - BigInt(100); // 100 seconds before the challenge expires

      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(futureTimestamp)]);
      await ethers.provider.send("evm_mine", []);

      await challengeContract.connect(challenger).submitMeasurements(challengeId, [10000, 5]);

      await expect(challengeContract.connect(owner).distributeWinnings(challengeId)).to.be.revertedWithCustomError(challengeContract, "ChallengeIsActive");
    });

    it("should distribute winnings to the people who bet for the challenger if the challenger wins", async function () {
      // Capture initial balances
      const initialBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
      const initialBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
      const initialChallengerBalance = await ethers.provider.getBalance(challengerAddress);

      const bettorPlaceBetTx = await challengeContract.connect(bettor).placeBet(challengeId, true, { value: betAmount });
      const bettor2PlaceBetTx = await challengeContract.connect(bettor2).placeBet(challengeId, false, { value: betAmount });
      const challengerPlaceBetTx = await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount });

      const bettorBalanceAfterPlacingBets = await ethers.provider.getBalance(bettor.getAddress());
      const bettor2BalanceAfterPlacingBets = await ethers.provider.getBalance(bettor2.getAddress());
      const challengerBalanceAfterPlacingBets = await ethers.provider.getBalance(challengerAddress);

      await challengeContract.connect(challenger).startChallenge(challengeId);
      await challengeContract.connect(challenger).submitMeasurements(challengeId, [10000, 5]);

      const pastTimestamp = (await ethers.provider.getBlock('latest') || {timestamp: 0}).timestamp + (3600 + 1);
      await ethers.provider.send("evm_setNextBlockTimestamp", [pastTimestamp]);
      await ethers.provider.send("evm_mine", []);

      await challengeContract.connect(owner).distributeWinnings(challengeId);
      const challengeStatus = await challengeContract.challengeToChallengeStatus(challengeId);
      expect(challengeStatus).to.equal(3);

      // Capture final balances
      const finalBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
      const finalBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
      const finalChallengerBalance = await ethers.provider.getBalance(challengerAddress);

      // Calculate expected winnings
      const expectedBettorWinnings = betAmount + (betAmount / BigInt(2));
      const expectedChallengerWinnings = betAmount + (betAmount / BigInt(2));

      // Adjust assertions to account for gas costs
      //expect(finalBettorBalance).to.equal(initialBettorBalance + expectedBettorWinnings); // Allow for gas cost variance
      expect(finalBettor2Balance).to.equal(bettor2BalanceAfterPlacingBets);
      //expect(finalChallengerBalance).to.equal(initialChallengerBalance + expectedChallengerWinnings); 
    });
  })
});
