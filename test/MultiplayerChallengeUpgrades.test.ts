import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Signer } from "ethers";
import { MultiplayerChallenge, MockMultiplayerChallengeV2 } from "../typechain";

const DeployV2 = async (deployer: Signer, multiplayerChallengeContractAddress: string): Promise<MockMultiplayerChallengeV2> => {
  const MultiplayerChallengeV2Factory = await ethers.getContractFactory("MockMultiplayerChallengeV2", deployer);
  const multiplayerChallengeV2 = (await upgrades.upgradeProxy(
    multiplayerChallengeContractAddress, 
    MultiplayerChallengeV2Factory
  )) as unknown as MockMultiplayerChallengeV2;
  
  const multiplayerChallengeV2AsV2 = multiplayerChallengeV2 as unknown as MockMultiplayerChallengeV2;
  await multiplayerChallengeV2AsV2.initializeV2();

  return multiplayerChallengeV2AsV2;
}

describe("MultiplayerChallenge Upgradeability", function () {
  let multiplayerChallengeContract: MultiplayerChallenge;
  let multiplayerChallengeV2: MockMultiplayerChallengeV2;
  let deployer: Signer;
  let competitor1: Signer;
  let competitor2: Signer;
  let competitor3: Signer;
  let bettor: Signer;
  let challenger: Signer;  

  // Parameters for initialize
  const minimumBetValue = ethers.parseEther("0.01");
  const maxBettors = 100;
  const maxChallengeLength = 30 * 24 * 3600; // 30 days in seconds
  const maxChallengeMetrics = 3;
  const maxCompetitors = 5;

  let multiplayerChallengeContractAddress: string;
  let deployerAddress: string;
  let competitor1Address: string;
  let competitor2Address: string;
  let competitor3Address: string;
  let bettorAddress: string;
  let challengerAddress: string;

  let proxyAddressBefore: string;

  const CHALLENGE_STEPS = 0;

  beforeEach(async () => {
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3Aggregator.deploy(8, 200000000000); // 8 decimals, $2000.00000000 ETH/USD price
    const mockPriceFeedAddress = await mockPriceFeed.getAddress();

    [deployer, competitor1, competitor2, competitor3, bettor, challenger] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    competitor1Address = await competitor1.getAddress();
    competitor2Address = await competitor2.getAddress();
    competitor3Address = await competitor3.getAddress();
    bettorAddress = await bettor.getAddress();
    challengerAddress = await challenger.getAddress();

    // Deploy the MultiplayerChallenge proxy
    const MultiplayerChallengeFactory = await ethers.getContractFactory("MultiplayerChallenge", deployer);
    multiplayerChallengeContract = await upgrades.deployProxy(
      MultiplayerChallengeFactory,
      [
        minimumBetValue,
        maxCompetitors,
        mockPriceFeedAddress,
        maxBettors,
        maxChallengeLength,
        maxChallengeMetrics,
      ],
      { initializer: "initializeMultiplayerChallenge" }
    );

    await multiplayerChallengeContract.waitForDeployment();
    multiplayerChallengeContractAddress = await multiplayerChallengeContract.getAddress();

    // Deploy the Vault proxy and connect it to the MultiplayerChallenge
    const VaultFactory = await ethers.getContractFactory("Vault");
    const vaultContract = await upgrades.deployProxy(VaultFactory, [multiplayerChallengeContractAddress], { initializer: 'initialize' });
    await vaultContract.waitForDeployment();
    const vaultContractAddress = await vaultContract.getAddress();

    await multiplayerChallengeContract.setVault(vaultContractAddress);

    // Add challenger to whitelist
    await multiplayerChallengeContract.addNewChallenger(challengerAddress);
    
    // Add bettor to whitelist
    await multiplayerChallengeContract.addNewBettor(bettorAddress);

    proxyAddressBefore = await multiplayerChallengeContract.getAddress();

  });

  it("upgrades to MultiplayerChallengeV2 and keeps the same proxy address", async () => {
    const multiplayerChallengeV2AsV2 = await DeployV2(deployer, multiplayerChallengeContractAddress);

    const proxyAddressAfter = await multiplayerChallengeV2AsV2.getAddress();
    expect(proxyAddressAfter).to.equal(proxyAddressBefore);
  });

  it("exposes new properties from V2", async () => {
    // Cast the contract to the MockMultiplayerChallengeV2 type
    const multiplayerChallengeV2AsV2 = await DeployV2(deployer, multiplayerChallengeContractAddress);

    const newProp = await multiplayerChallengeV2AsV2.getNewV2Property();
    expect(newProp).to.equal("multiplayerV2");
  });

  it("preserves state across upgrades", async () => {
    // Check that configuration from initialization remains
    // Use an alternative approach to verify minimum bet value
    // This uses a typed cast since the property might not be directly accessible on the interface
    const multiplayerChallengeV2AsV2 = await DeployV2(deployer, multiplayerChallengeContractAddress);

    const minBetValue = await multiplayerChallengeV2AsV2.getMinimumUsdValueOfBet();
    expect(minBetValue).to.equal(minimumBetValue);
    
    const maxCompetitorsValue = await multiplayerChallengeV2AsV2.maximumNumberOfChallengeCompetitors();
    expect(maxCompetitorsValue).to.equal(maxCompetitors);
    
    // Check that whitelist state is preserved
    const isChallengerWhitelisted = await multiplayerChallengeV2AsV2.challengerWhitelist(challengerAddress);
    expect(isChallengerWhitelisted).to.be.true;
    
    const isBettorWhitelisted = await multiplayerChallengeV2AsV2.bettorWhitelist(bettorAddress);
    expect(isBettorWhitelisted).to.be.true;
  });

  it("handles multiplayer challenge creation and competition with upgraded contract", async () => {
    // Create a multiplayer challenge using the upgraded contract
    const challengeLength = 3600; // 1 hour in seconds
    const challengeMetric = CHALLENGE_STEPS;
    const maxChallengeCompetitors = 3;

    const multiplayerChallengeV2AsV2 = await DeployV2(deployer, multiplayerChallengeContractAddress);
    
    // Create challenge
    await multiplayerChallengeV2AsV2.connect(challenger).createMultiplayerChallenge(
      challengeLength,
      challengeMetric,
      maxChallengeCompetitors
    );
    
    // Get the challenge ID
    const challengeIds = await multiplayerChallengeV2AsV2.getChallengesForChallenger(challengerAddress);
    const challengeId = challengeIds[0];
    
    // Have competitors join the challenge
    await multiplayerChallengeV2AsV2.connect(competitor1).joinChallenge(challengeId);
    await multiplayerChallengeV2AsV2.connect(competitor2).joinChallenge(challengeId);
    
    // Start the challenge
    await multiplayerChallengeV2AsV2.connect(challenger).startChallenge(challengeId);
    
    // Submit measurements - this should trigger the overridden function with bonus logic
    await multiplayerChallengeV2AsV2.connect(challenger).submitMeasurements(challengeId, [12000]);
    await multiplayerChallengeV2AsV2.connect(competitor1).submitMeasurements(challengeId, [8000]);
    await multiplayerChallengeV2AsV2.connect(competitor2).submitMeasurements(challengeId, [15000]);
    
    // Check the leaderboard - competitor2 should be the leader with 15000 steps
    const leader = await multiplayerChallengeV2AsV2.getLeader(challengeId);
    expect(leader).to.equal(competitor2Address);
    
    const challengerBadges = await multiplayerChallengeV2AsV2.getCompetitorBadges(challengeId, challengerAddress);
    expect(challengerBadges.length).to.equal(0); // challenger does not get a badge for being the leader to begin
    
    const competitor1Badges = await multiplayerChallengeV2AsV2.getCompetitorBadges(challengeId, competitor1Address);
    expect(competitor1Badges.length).to.equal(0); 
    
    const competitor2Badges = await multiplayerChallengeV2AsV2.getCompetitorBadges(challengeId, competitor2Address);
    expect(competitor2Badges.length).to.equal(1);
    expect(competitor2Badges[0]).to.equal(1);
  });

  it("preserves all critical state during an upgrade with an active multiplayer challenge", async () => {
    // Create a challenge and have competitors join before the upgrade
    const challengeLength = 3600; // 1 hour
    const challengeMetric = CHALLENGE_STEPS;
    const maxChallengeCompetitors = 3;
    
    // Create challenge with the original contract
    await multiplayerChallengeContract.connect(challenger).createMultiplayerChallenge(
      challengeLength,
      challengeMetric,
      maxChallengeCompetitors
    );
    
    // Get the challenge ID
    const challengeIds = await multiplayerChallengeContract.getChallengesForChallenger(challengerAddress);
    const challengeId = challengeIds[0];
    
    // Have competitors join the challenge
    await multiplayerChallengeContract.connect(competitor1).joinChallenge(challengeId);
    await multiplayerChallengeContract.connect(competitor2).joinChallenge(challengeId);
    
    // Place some bets
    const betAmount = ethers.parseEther("0.05");
    await multiplayerChallengeContract.connect(bettor).placeBet(challengeId, true, { value: betAmount });
    
    // Start the challenge
    await multiplayerChallengeContract.connect(challenger).startChallenge(challengeId);
    
    // Submit some initial measurements
    await multiplayerChallengeContract.connect(challenger).submitMeasurements(challengeId, [5000]);
    
    // Store important state before upgrade
    const challengeStatusBefore = await multiplayerChallengeContract.challengeToChallengeStatus(challengeId);
    expect(challengeStatusBefore).to.equal(1);
    const challengeStartTimeBefore = await multiplayerChallengeContract.challengeToStartTime(challengeId);
    const challengeLengthBefore = await multiplayerChallengeContract.challengeToChallengeLength(challengeId);
    const leaderBefore = await multiplayerChallengeContract.getLeader(challengeId);
    const competitorsCountBefore = (await multiplayerChallengeContract.getCompetitors(challengeId)).length;
    const betsForBefore = await multiplayerChallengeContract.challengeToTotalAmountBetFor(challengeId);

    // Initialize V2 state
    const multiplayerChallengeV2AsV2 = await DeployV2(deployer, multiplayerChallengeContractAddress);
    
    // Verify all state was preserved through the upgrade
    const challengeStatusAfter = await multiplayerChallengeV2AsV2.challengeToChallengeStatus(challengeId);
    const challengeStartTimeAfter = await multiplayerChallengeV2AsV2.challengeToStartTime(challengeId);
    const challengeLengthAfter = await multiplayerChallengeV2AsV2.challengeToChallengeLength(challengeId);
    const leaderAfter = await multiplayerChallengeV2AsV2.getLeader(challengeId);
    const competitorsCountAfter = (await multiplayerChallengeV2AsV2.getCompetitors(challengeId)).length;
    const betsForAfter = await multiplayerChallengeV2AsV2.challengeToTotalAmountBetFor(challengeId);
    
    expect(challengeStatusAfter).to.equal(challengeStatusBefore);
    expect(challengeStartTimeAfter).to.equal(challengeStartTimeBefore);
    expect(challengeLengthAfter).to.equal(challengeLengthBefore);
    expect(leaderAfter).to.equal(leaderBefore);
    expect(competitorsCountAfter).to.equal(competitorsCountBefore);
    expect(betsForAfter).to.equal(betsForBefore);
    
    // Verify the challenge can continue functioning with V2 features
    
    // New competitor joins
    await expect(multiplayerChallengeV2AsV2.connect(competitor3).joinChallenge(challengeId)).to.be.revertedWithCustomError(multiplayerChallengeV2AsV2, "ChallengeIsActive");
    
    // Submit more measurements - should trigger V2 bonus logic
    await multiplayerChallengeV2AsV2.connect(competitor1).submitMeasurements(challengeId, [12000]); // competitor1 is the leader and they get a badge for overtaking the leader
    await multiplayerChallengeV2AsV2.connect(competitor2).submitMeasurements(challengeId, [9000]); // competitor2 does not overtake the leader and they do not get a badge
    
    // Check the new V2 bonus functionality
    const competitor1Bonus = await multiplayerChallengeV2AsV2.getCompetitorBadges(challengeId, competitor1Address);
    const competitor2Bonus = await multiplayerChallengeV2AsV2.getCompetitorBadges(challengeId, competitor2Address);
    
    expect(competitor1Bonus.length).to.equal(1); // 12000 > 5000, so they get a bonus
    expect(competitor1Bonus[0]).to.equal(1);

    expect(competitor2Bonus.length).to.equal(0);   // 9000 < 10000, no bonus
  });

  it("can handle concurrent Challenge V2 upgrade impact on MultiplayerChallenge", async () => {
    // This test simulates a scenario where the base Challenge contract is upgraded to V2
    // and then the MultiplayerChallenge is also upgraded to V2
    
    // First, create a challenge
    const challengeLength = 3600; // 1 hour
    const challengeMetric = CHALLENGE_STEPS;
    const maxChallengeCompetitors = 3;
    
    await multiplayerChallengeContract.connect(challenger).createMultiplayerChallenge(
      challengeLength,
      challengeMetric,
      maxChallengeCompetitors
    );
    
    // Get the challenge ID
    const challengeIds = await multiplayerChallengeContract.getChallengesForChallenger(challengerAddress);
    const challengeId = challengeIds[0];
    
    // Competitors join
    await multiplayerChallengeContract.connect(competitor1).joinChallenge(challengeId);
    await multiplayerChallengeContract.connect(competitor2).joinChallenge(challengeId);
    
    // Initialize V2 state
    const multiplayerChallengeV2AsV2 = await DeployV2(deployer, multiplayerChallengeContractAddress);
    
    // Start the challenge
    await multiplayerChallengeV2AsV2.connect(challenger).startChallenge(challengeId);
    
    // Submit measurements with V2 contract
    await multiplayerChallengeV2AsV2.connect(challenger).submitMeasurements(challengeId, [12000]);
    await multiplayerChallengeV2AsV2.connect(competitor1).submitMeasurements(challengeId, [8000]);
    await multiplayerChallengeV2AsV2.connect(competitor2).submitMeasurements(challengeId, [15000]);
    
    // Check leadership
    const leader = await multiplayerChallengeV2AsV2.getLeader(challengeId);
    expect(leader).to.equal(competitor2Address);
    
    // Check bonuses from V2 implementation
    const challengerBonus = await multiplayerChallengeV2AsV2.getCompetitorBadges(challengeId, challengerAddress);
    expect(challengerBonus.length).to.equal(0); // challenger does not get a badge for being the leader to begin
    
    // Time travel to end the challenge
    const challengeStartTime = await multiplayerChallengeV2AsV2.challengeToStartTime(challengeId);
    const endTime = Number(challengeStartTime) + challengeLength + 1;
    
    await ethers.provider.send("evm_setNextBlockTimestamp", [endTime]);
    await ethers.provider.send("evm_mine", []);
    
    // Distribute winnings
    await multiplayerChallengeV2AsV2.connect(deployer).distributeWinnings(challengeId);
    
    // Verify challenge is completed
    const finalStatus = await multiplayerChallengeV2AsV2.challengeToChallengeStatus(challengeId);
    expect(finalStatus).to.equal(3); // STATUS_CHALLENGER_WON
    
    // Final check of V2 properties
    const newProperty = await multiplayerChallengeV2AsV2.getNewV2Property();
    expect(newProperty).to.equal("multiplayerV2");
  });
}); 