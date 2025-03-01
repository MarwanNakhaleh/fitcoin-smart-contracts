import { ethers, upgrades } from "hardhat";
import { Signer, BigNumberish, parseEther } from "ethers";
import { expect } from "chai";
import { MultiplayerChallenge, MultiplayerChallenge__factory, Vault } from "../typechain";

const findEventArgs = (logs: any, eventName: string) => {
  let _event = null;

  for (const event of logs) {
    if (event.fragment && event.fragment.name === eventName) {
      _event = event.args;
    }
  }
  return _event
}

describe("MultiplayerChallenge Tests", function () {
  let multiplayerChallenge: MultiplayerChallenge;
  let vaultContract: Vault;
  let owner: Signer;
  let competitor1: Signer;
  let competitor2: Signer;
  let competitor3: Signer;
  let nonCompetitor: Signer;
  let challenger: Signer;
  let challengerAddress: string;
  let betAmount: bigint = ethers.parseEther("0.05");

  let competitor1Address: string;
  let competitor2Address: string;

  // Add mock price feed
  const DECIMALS = 8;
  const INITIAL_ANSWER = BigInt(200000000000); // $2000.00000000 with 8 decimals
  const ethPriceFactorConversionUnits: bigint = BigInt(1e14); // number of wei in one ETH
  const minimumUsdBetValue: bigint = BigInt(10) * ethPriceFactorConversionUnits;
  const maximumNumberOfChallengeCompetitors = 3;

  const CHALLENGE_STEPS: BigNumberish = 0;
  const CHALLENGE_MILEAGE: BigNumberish = 1;

  beforeEach(async function () {
    [owner, competitor1, competitor2, competitor3, nonCompetitor, challenger] = await ethers.getSigners();
    challengerAddress = await challenger.getAddress();

    // Deploy the mock price feed.
    const MockV3AggregatorFactory = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3AggregatorFactory.deploy(DECIMALS, INITIAL_ANSWER);
    await mockPriceFeed.waitForDeployment();

    // Deploy the MultiplayerChallenge proxy.
    const PriceDataFeed = await ethers.getContractFactory("PriceDataFeed");
    const priceDataFeed = await PriceDataFeed.deploy();
    const priceDataFeedAddress = await priceDataFeed.getAddress();
    
    const MultiplayerChallengeFactory = await ethers.getContractFactory("MultiplayerChallenge", {
      libraries: {
        PriceDataFeed: priceDataFeedAddress
      },
    });
    const mockPriceFeedAddress = await mockPriceFeed.getAddress();
    const maximumNumberOfBettorsPerChallenge = 100;
    const maximumNumberOfChallengeCompetitors = 3;
    const maximumChallengeLengthInSeconds = 2592000;
    const maximumNumberOfChallengeMetrics = 3;

    multiplayerChallenge = await upgrades.deployProxy(
      MultiplayerChallengeFactory,
      [
        minimumUsdBetValue,
        maximumNumberOfChallengeCompetitors,
        mockPriceFeedAddress,
        maximumNumberOfBettorsPerChallenge,
        maximumChallengeLengthInSeconds,
        maximumNumberOfChallengeMetrics
      ],
      { 
        initializer: 'initializeMultiplayerChallenge',
        unsafeAllow: ["external-library-linking"]
      }
    );
    await multiplayerChallenge.waitForDeployment();
    const multiplayerChallengeAddress = await multiplayerChallenge.getAddress();

    // Deploy the Vault proxy.
    const VaultFactory = await ethers.getContractFactory("Vault");
    vaultContract = await upgrades.deployProxy(VaultFactory, [multiplayerChallengeAddress], { 
      initializer: "initialize",
      unsafeAllow: ["external-library-linking"]
    });
    await vaultContract.waitForDeployment();
    const vaultContractAddress = await vaultContract.getAddress();

    // Set the vault in the MultiplayerChallenge contract.
    await multiplayerChallenge.connect(owner).setVault(vaultContractAddress);

    // Add the challenger to the whitelist.
    await multiplayerChallenge.connect(owner).addNewChallenger(challengerAddress);
    await multiplayerChallenge.connect(owner).addNewChallenger(await competitor1.getAddress());
    await multiplayerChallenge.connect(owner).addNewChallenger(await competitor2.getAddress());
  });

  describe("Global settings", function () {
    it("should allow the owner to set the global maximum number of competitors", async function () {
      await multiplayerChallenge.connect(owner).setMaximumNumberOfChallengeCompetitors(10);
      expect(await multiplayerChallenge.maximumNumberOfChallengeCompetitors()).to.equal(10);
    });
  });

  describe("Creating a multiplayer challenge", function () {
    const maximumNumberOfChallengeCompetitors = 3;
    const challengeMetrics: BigNumberish = CHALLENGE_STEPS;
    // 1-hour challenge duration
    const challengeLength = BigInt(60 * 60);
    let challengeId: bigint;

    beforeEach(async function () {
      await multiplayerChallenge.connect(owner).setMaximumNumberOfChallengeCompetitors(5);
      // Create a challenge with a maximum of 3 competitors.
      const tx = await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        maximumNumberOfChallengeCompetitors,
        { value: betAmount }
      );
      await tx.wait();
      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[challengeIds.length - 1];
    });

    it("should create a challenge with the correct competitor cap and add the creator as the initial competitor", async function () {
      expect(await multiplayerChallenge.challengeToMaxCompetitors(challengeId)).to.equal(3);
      const competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors.length).to.equal(1);
      expect(competitors[0]).to.equal(challengerAddress);
    });

    it("should not allow new competitors to join without payment", async function () {
      betAmount = ethers.parseEther("0.05");
      // competitor1 joins
      await expect(multiplayerChallenge.connect(competitor1).joinChallenge(challengeId)).to.be.revertedWithCustomError(multiplayerChallenge, "MinimumBetAmountTooSmall");
    });

    it("should allow new competitors to join until the cap is reached", async function () {
      betAmount = ethers.parseEther("0.05");
      // competitor1 joins
      await multiplayerChallenge.connect(competitor1).joinChallenge(challengeId, { value: betAmount });
      let competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors.length).to.equal(2);

      // competitor2 joins
      await multiplayerChallenge.connect(competitor2).joinChallenge(challengeId, { value: betAmount });
      competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors.length).to.equal(3);

      // A fourth competitor cannot join as the cap is reached.
      await expect(multiplayerChallenge.connect(nonCompetitor).joinChallenge(challengeId, { value: betAmount }))
        .to.be.revertedWithCustomError(multiplayerChallenge, "BettorNotInWhitelist");
      await multiplayerChallenge.connect(owner).addNewBettor(await nonCompetitor.getAddress());
      await expect(multiplayerChallenge.connect(nonCompetitor).joinChallenge(challengeId, { value: betAmount })).to.be.revertedWithCustomError(multiplayerChallenge, "ChallengeIsFull");
    });

    it("should revert when a non-participant tries to submit measurements", async function () {
      const numberOfSteps: BigNumberish = 10000;
      await expect(multiplayerChallenge.connect(nonCompetitor).submitMeasurements(challengeId, [numberOfSteps]))
        .to.be.revertedWithCustomError(multiplayerChallenge, "ChallengeCompetitorNotJoined");
    });
  });

  describe("Multiplayer challenge leader updates", () => {
    const challengeMetrics: BigNumberish = CHALLENGE_STEPS;
    const challengeLength = BigInt(60 * 60); // 1 hour
    let challengeId: bigint;

    beforeEach(async () => {
      await multiplayerChallenge.connect(owner).setMaximumNumberOfChallengeCompetitors(5);
      // Create a challenge with a cap of 3 competitors.
      const tx = await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        maximumNumberOfChallengeCompetitors,
        { value: betAmount }
      );
      await tx.wait();
      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];

      await multiplayerChallenge.connect(competitor1).joinChallenge(challengeId, { value: betAmount });
      competitor1Address = await competitor1.getAddress();

      await multiplayerChallenge.connect(competitor2).joinChallenge(challengeId, { value: betAmount });
      competitor2Address = await competitor2.getAddress();
    });

    it("should revert starting the challenge if there are not enough competitors", async () => {
      await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        2,
        { value: betAmount }
      );
      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      const newChallengeId = challengeIds[challengeIds.length - 1];
      await expect(multiplayerChallenge.connect(challenger).startChallenge(newChallengeId))
        .to.be.revertedWithCustomError(multiplayerChallenge, "NotEnoughCompetitors");
    });

    it("should update the leader when a competitor submits a higher aggregated value", async () => {
      await multiplayerChallenge.connect(challenger).startChallenge(challengeId);

      const challengerNumberOfSteps: BigNumberish = 10000;
      await multiplayerChallenge.connect(challenger)
        .submitMeasurements(
          challengeId,
          [challengerNumberOfSteps]
        );
      let leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(challengerAddress);

      expect(await multiplayerChallenge.challengeToCompetitorMeasurements(challengeId, challengerAddress)).to.equal(challengerNumberOfSteps);
      expect(await multiplayerChallenge.challengeToCompetitorMeasurements(challengeId, competitor1Address)).to.equal(0);
      expect(await multiplayerChallenge.challengeToCompetitorMeasurements(challengeId, competitor2Address)).to.equal(0);

      const competitor1NumberOfSteps: BigNumberish = 15000;
      await expect(
        multiplayerChallenge.connect(competitor1)
          .submitMeasurements(
            challengeId, [
            competitor1NumberOfSteps]
          )
      ).to.emit(multiplayerChallenge, "LeaderUpdated");

      expect(await multiplayerChallenge.challengeToCompetitorMeasurements(challengeId, competitor1Address)).to.equal(competitor1NumberOfSteps);

      leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(competitor1Address);

      const competitor2NumberOfSteps: BigNumberish = 12000;
      await multiplayerChallenge.connect(competitor2).submitMeasurements(challengeId, [competitor2NumberOfSteps]);
      leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(competitor1Address);
    });
  });

  describe("Multiplayer challenge edge cases", function () {
    const challengeMetrics: BigNumberish = CHALLENGE_STEPS;
    const challengeLength = BigInt(60 * 60); // 1 hour
    let challengeId: BigNumberish;

    let competitor1Address: string;
    let competitor2Address: string;

    beforeEach(async function () {
      // Set a global maximum.
      await multiplayerChallenge.connect(owner).setMaximumNumberOfChallengeCompetitors(5);

      await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        4,
        { value: betAmount }
      );

      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];

      // Add competitors
      await multiplayerChallenge.connect(competitor1).joinChallenge(challengeId, { value: betAmount });
      competitor1Address = await competitor1.getAddress();
      await multiplayerChallenge.connect(competitor2).joinChallenge(challengeId, { value: betAmount });
      competitor2Address = await competitor2.getAddress();
    });

    it("should handle ties by keeping the first leader when scores are equal", async function () {
      // Initial submission by challenger
      const numberOfSteps: BigNumberish = 10000;

      // Start the challenge
      await multiplayerChallenge.connect(challenger).startChallenge(challengeId);

      await multiplayerChallenge.connect(challenger).submitMeasurements(challengeId, [numberOfSteps]);

      let leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(challengerAddress);

      // Competitor1 submits the same score
      await multiplayerChallenge.connect(competitor1).submitMeasurements(challengeId, [numberOfSteps]);

      // The leader should still be the challenger (first submitter)
      leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(challengerAddress);

      // Competitor2 submits a higher score
      await multiplayerChallenge.connect(competitor2).submitMeasurements(challengeId, [numberOfSteps + 1]);

      // The leader should now be competitor2
      leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(await competitor2.getAddress());

      // Competitor1 submits the same score as competitor2
      await multiplayerChallenge.connect(competitor1).submitMeasurements(challengeId, [numberOfSteps + 1]);

      // The leader should still be competitor2 (first to reach that score)
      leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(await competitor2.getAddress());
    });

    it("should handle the challenger leaving their own created challenge", async function () {
      // Ensure the challenge is not yet started
      expect(await multiplayerChallenge.challengeToChallengeStatus(challengeId)).to.equal(0); // STATUS_INACTIVE

      // adding a third competitor to double triple check the logic for the challenger leaving the challenge
      await multiplayerChallenge.connect(owner).addNewBettor(await competitor3.getAddress());
      await multiplayerChallenge.connect(competitor3).joinChallenge(challengeId, { value: betAmount });

      // Challenger attempts to leave the challenge they created
      const challengeCreatorLeavesTx = await multiplayerChallenge.connect(challenger).leaveChallenge(challengeId);
      const result = await challengeCreatorLeavesTx.wait();

      const eventArgs = findEventArgs(result?.logs, "ChallengerChanged");

      // Challenge should have been passed to the first competitor
      expect(eventArgs.length).to.equal(3);
      expect(eventArgs[0]).to.equal(challengeId);
      expect(eventArgs[1]).to.equal(challengerAddress);
      expect(eventArgs[2]).to.equal(competitor1Address);
      expect(await multiplayerChallenge.challengeToChallenger(challengeId)).to.equal(competitor1Address);

      // Check the challenger is no longer in the competition
      const competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors).to.not.include(challengerAddress);

      // If the challenger leaves, they should not be able to submit measurements
      await expect(
        multiplayerChallenge.connect(challenger).submitMeasurements(challengeId, [10000])
      ).to.be.revertedWithCustomError(multiplayerChallenge, "ChallengeCompetitorNotJoined");

      // The challenge should still be valid and other competitors can interact with it
      await multiplayerChallenge.connect(competitor1).startChallenge(challengeId);
      await multiplayerChallenge.connect(competitor1).submitMeasurements(challengeId, [10000]);

      // Check that the leader is now competitor1
      const leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(await competitor1.getAddress());
    });

    it("should handle all competitors submitting a score of 0", async function () {
      // challenge needs to be started before submitting measurements
      await multiplayerChallenge.connect(challenger).startChallenge(challengeId);

      // All competitors submit a score of 0
      await multiplayerChallenge.connect(challenger).submitMeasurements(challengeId, [0]);
      await multiplayerChallenge.connect(competitor1).submitMeasurements(challengeId, [0]);
      await multiplayerChallenge.connect(competitor2).submitMeasurements(challengeId, [0]);

      // The first to submit (challenger) should be the leader in case of a tie at 0
      const leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(challengerAddress);
    });
  });

  describe("Ending a multiplayer challenge", function () {
    const challengeMetrics: BigNumberish = CHALLENGE_STEPS;
    const challengeLength = BigInt(60 * 60); // 1 hour
    let challengeId: BigNumberish;

    let initialChallengerBalance: bigint;
    let initialCompetitor1Balance: bigint;
    let initialCompetitor2Balance: bigint;

    beforeEach(async function () {
      initialChallengerBalance = await ethers.provider.getBalance(challengerAddress);
      initialCompetitor1Balance = await ethers.provider.getBalance(competitor1Address);
      initialCompetitor2Balance = await ethers.provider.getBalance(competitor2Address);

      await multiplayerChallenge.connect(owner).setMaximumNumberOfChallengeCompetitors(5);

      await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        4,
        { value: betAmount }
      );

      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];

      // Add competitors
      await multiplayerChallenge.connect(competitor1).joinChallenge(challengeId, { value: betAmount });
      competitor1Address = await competitor1.getAddress();
      await multiplayerChallenge.connect(competitor2).joinChallenge(challengeId, { value: betAmount });
      competitor2Address = await competitor2.getAddress();

      await multiplayerChallenge.connect(challenger).startChallenge(challengeId);
    });

    it("should not allow winnings distribution if the challenge is not expired", async function () {
      const challengeStartTime = await multiplayerChallenge.challengeToStartTime(challengeId);
      const futureTimestamp = challengeStartTime + challengeLength + BigInt(100); // 100 seconds after the challenge expires

      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(futureTimestamp)]);
      await ethers.provider.send("evm_mine", []);

      await expect(multiplayerChallenge.connect(challenger).submitMeasurements(challengeId, [10000])).to.be.revertedWithCustomError(multiplayerChallenge, "ChallengeIsExpired");
    });

    it("should handle winnings distribution", async function () {
      await multiplayerChallenge.connect(challenger)
        .submitMeasurements(
          challengeId,
          [10000]
        );
      await multiplayerChallenge.connect(competitor1)
        .submitMeasurements(
          challengeId,
          [12000]
        );
      await multiplayerChallenge.connect(competitor2)
        .submitMeasurements(
          challengeId,
          [5000]
        );
        
      const challengeStartTime = await multiplayerChallenge.challengeToStartTime(challengeId);
      const futureTimestamp = challengeStartTime + challengeLength + BigInt(100); // 100 seconds after the challenge expires

      await ethers.provider.send("evm_setNextBlockTimestamp", [Number(futureTimestamp)]);
      await ethers.provider.send("evm_mine", []);

      await multiplayerChallenge.connect(owner).distributeWinnings(challengeId);

      const winner = await multiplayerChallenge.getLeader(challengeId);
      expect(winner).to.equal(await competitor1.getAddress());

      const winnings = await multiplayerChallenge.challengeToWinningsPaid(challengeId);
      expect(winnings).to.equal(parseEther("0.15"));

      const challengerBalance = await ethers.provider.getBalance(challengerAddress);
      expect(challengerBalance).to.be.closeTo(initialChallengerBalance - parseEther("0.05"), parseEther("0.001"));
      const competitor1Balance = await ethers.provider.getBalance(await competitor1.getAddress());
      expect(competitor1Balance).to.be.closeTo(initialCompetitor1Balance + winnings - parseEther("0.05"), parseEther("0.001"));
      const competitor2Balance = await ethers.provider.getBalance(await competitor2.getAddress());
      expect(competitor2Balance).to.be.closeTo(initialCompetitor2Balance - parseEther("0.05"), parseEther("0.001"));
    });
  });
});