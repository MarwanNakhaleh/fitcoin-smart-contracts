import { ethers, upgrades } from "hardhat";
import { Signer, parseEther, BigNumberish } from "ethers";
import { expect } from "chai";
import { MultiplayerChallenge, MultiplayerChallenge__factory, Vault } from "../typechain";

describe("MultiplayerChallenge Tests", function () {
  let multiplayerChallenge: MultiplayerChallenge;
  let vaultContract: Vault;
  let owner: Signer;
  let competitor1: Signer;
  let competitor2: Signer;
  let nonCompetitor: Signer;
  let challenger: Signer;
  let challengerAddress: string;

  // Add mock price feed
  const DECIMALS = 8;
  const INITIAL_ANSWER = BigInt(200000000000); // $2000.00000000 with 8 decimals
  const ethPriceFactorConversionUnits: bigint = BigInt(1e14); // number of wei in one ETH
  const minimumUsdBetValue: bigint = BigInt(10) * ethPriceFactorConversionUnits;
  
  
  const CHALLENGE_STEPS: BigNumberish = 0;
  const CHALLENGE_MILEAGE: BigNumberish = 1;

  beforeEach(async function () {
    [owner, competitor1, competitor2, nonCompetitor, challenger] = await ethers.getSigners();
    challengerAddress = await challenger.getAddress();

    // Deploy the mock price feed.
    const MockV3AggregatorFactory = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3AggregatorFactory.deploy(DECIMALS, INITIAL_ANSWER);
    await mockPriceFeed.waitForDeployment();

    // Deploy the MultiplayerChallenge proxy.
    const MultiplayerChallengeFactory: MultiplayerChallenge__factory = await ethers.getContractFactory("MultiplayerChallenge");
    const mockPriceFeedAddress = await mockPriceFeed.getAddress();

    multiplayerChallenge = await upgrades.deployProxy(
      MultiplayerChallengeFactory,
      [minimumUsdBetValue, 3, mockPriceFeedAddress],
      { initializer: 'initializeMultiplayerChallenge' }
    );
    await multiplayerChallenge.waitForDeployment();
    const multiplayerChallengeAddress = await multiplayerChallenge.getAddress();

    // Deploy the Vault proxy.
    const VaultFactory = await ethers.getContractFactory("Vault");
    vaultContract = await upgrades.deployProxy(VaultFactory, [multiplayerChallengeAddress], { initializer: "initialize" });
    await vaultContract.waitForDeployment();
    const vaultContractAddress = await vaultContract.getAddress();

    // Set the vault in the MultiplayerChallenge contract.
    await multiplayerChallenge.connect(owner).setVault(vaultContractAddress);

    // Add the challenger to the whitelist.
    await multiplayerChallenge.connect(owner).addNewChallenger(challengerAddress);
  });

  describe("Global settings", function () {
    it("should allow the owner to set the global maximum number of competitors", async function () {
      await multiplayerChallenge.connect(owner).setMaxNumChallengeCompetitors(10);
      expect(await multiplayerChallenge.maxNumChallengeCompetitors()).to.equal(10);
    });
  });

  describe("Creating a multiplayer challenge", function () {
    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5;
    const targetMeasurements = [targetNumberOfSteps, targetNumberOfMiles];
    // 1-hour challenge duration.
    const challengeLength = BigInt(60 * 60);
    let challengeId: bigint;

    beforeEach(async function () {
      // Set a global maximum.
      await multiplayerChallenge.connect(owner).setMaxNumChallengeCompetitors(5);
      // Create a challenge with a maximum of 3 competitors.
      const tx = await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        targetMeasurements,
        3
      );
      await tx.wait();
      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];
    });

    it("should create a challenge with the correct competitor cap and add the creator as the initial competitor", async function () {
      expect(await multiplayerChallenge.challengeToMaxCompetitors(challengeId)).to.equal(3);
      const competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors.length).to.equal(1);
      expect(competitors[0]).to.equal(challengerAddress);
    });

    it("should allow new competitors to join until the cap is reached", async function () {
      // competitor1 joins.
      await multiplayerChallenge.connect(competitor1).joinChallenge(challengeId);
      let competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors.length).to.equal(2);

      // competitor2 joins.
      await multiplayerChallenge.connect(competitor2).joinChallenge(challengeId);
      competitors = await multiplayerChallenge.getCompetitors(challengeId);
      expect(competitors.length).to.equal(3);

      // A fourth competitor cannot join as the cap is reached.
      await expect(multiplayerChallenge.connect(nonCompetitor).joinChallenge(challengeId))
        .to.be.revertedWith("Challenge is full");
    });

    it("should revert when a non-participant tries to submit measurements", async function () {
      await expect(multiplayerChallenge.connect(nonCompetitor).submitMeasurements(challengeId, [10000, 5]))
        .to.be.revertedWith("Not a competitor in this challenge");
    });
  });

  describe("Multiplayer challenge leader updates", function () {
    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5;
    const targetMeasurements = [targetNumberOfSteps, targetNumberOfMiles];
    const challengeLength = BigInt(60 * 60); // 1 hour
    let challengeId: bigint;

    beforeEach(async function () {
      // Set a global maximum.
      await multiplayerChallenge.connect(owner).setMaxNumChallengeCompetitors(5);
      // Create a challenge with a cap of 3 competitors.
      const tx = await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        targetMeasurements,
        3
      );
      await tx.wait();
      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];

      // Add two more competitors.
      await multiplayerChallenge.connect(competitor1).joinChallenge(challengeId);
      await multiplayerChallenge.connect(competitor2).joinChallenge(challengeId);
    });

    it("should revert starting the challenge if there are not enough competitors", async function () {
      // In this test, create a new challenge where only the creator is a competitor.
      const tx = await multiplayerChallenge.connect(challenger).createMultiplayerChallenge(
        challengeLength,
        challengeMetrics,
        targetMeasurements,
        2
      );
      await tx.wait();
      const challengeIds = await multiplayerChallenge.getChallengesForChallenger(challengerAddress);
      const newChallengeId = challengeIds[challengeIds.length - 1];
      await expect(multiplayerChallenge.connect(challenger).startChallenge(newChallengeId))
        .to.be.revertedWithCustomError(multiplayerChallenge, "NotEnoughCompetitors");
    });

    it("should update the leader when a competitor submits a higher aggregated score", async function () {
      expect(await multiplayerChallenge.connect(challenger).startChallenge(challengeId)).to.be.revertedWithCustomError(multiplayerChallenge, "ChallengeIsActive");

      // Challenger submits measurements: aggregated score = 10000 + 5 = 10005.
      await multiplayerChallenge.connect(challenger).submitMeasurements(challengeId, [10000, 5]);
      let leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(challengerAddress);

      // competitor1 submits measurements: aggregated score = 15000 + 10 = 15010.
      await multiplayerChallenge.connect(competitor1).submitMeasurements(challengeId, [15000, 10]);
      leader = await multiplayerChallenge.getLeader(challengeId);
      const competitor1Address = await competitor1.getAddress();
      expect(leader).to.equal(competitor1Address);

      // competitor2 submits a lower score (e.g., 12000 + 5 = 12005) so leader remains competitor1.
      await multiplayerChallenge.connect(competitor2).submitMeasurements(challengeId, [12000, 5]);
      leader = await multiplayerChallenge.getLeader(challengeId);
      expect(leader).to.equal(competitor1Address);
    });
  });
});
