import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Signer } from "ethers";
import { Challenge, MockChallengeV2 } from "../typechain";

describe("Challenge Upgradeability", function () {
  let challengeContact: Challenge;
  let challengeV2: Challenge;
  let deployer: Signer;
  let user: Signer;

  // Parameters for initialize
  const minimumBetValue = ethers.parseEther("0.01");
  const maxBettors = 100;
  const maxChallengeLength = 30 * 24 * 3600; // 30 days in seconds
  const maxChallengeMetrics = 3;

  let ChallengeV2Factory: any;
  let challengeContractAddress: string;
  let deployerAddress: string;
  let userAddress: string;

  beforeEach(async () => {
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3Aggregator.deploy(8, 200000000000); // 8 decimals, $2000.00000000 ETH/USD price
    const mockPriceFeedAddress = await mockPriceFeed.getAddress();

    [deployer, user] = await ethers.getSigners();
    deployerAddress = await deployer.getAddress();
    userAddress = await user.getAddress();

    const PriceDataFeed = await ethers.getContractFactory("PriceDataFeed");
    const priceDataFeed = await PriceDataFeed.deploy(); // 8 decimals, $2000.00000000 ETH/USD price
    const priceDataFeedAddress = await priceDataFeed.getAddress();

    const ChallengeFactory = await ethers.getContractFactory("Challenge", {
      libraries: {
        PriceDataFeed: priceDataFeedAddress
      },
    });
    challengeContact = await upgrades.deployProxy(
      ChallengeFactory,
      [
        minimumBetValue,
        mockPriceFeedAddress,
        maxBettors,
        maxChallengeLength,
        maxChallengeMetrics,
      ],
      {
        initializer: "initialize",
        unsafeAllow: ["external-library-linking"]
      }
    );
    await challengeContact.waitForDeployment();
    challengeContractAddress = await challengeContact.getAddress();

    const VaultFactory = await ethers.getContractFactory("Vault");
    const vaultContract = await upgrades.deployProxy(VaultFactory, [challengeContractAddress], {
      initializer: 'initialize',
      unsafeAllow: ["external-library-linking"]
    });
    await vaultContract.waitForDeployment();
    const vaultContractAddress = await vaultContract.getAddress();

    await challengeContact.setVault(vaultContractAddress);

    ChallengeV2Factory = await ethers.getContractFactory("MockChallengeV2", {
      libraries: {
        PriceDataFeed: priceDataFeedAddress
      },
    }, deployer);
  });

  it("upgrades to ChallengeV2 and keeps the same proxy address", async () => {
    const proxyAddressBefore = await challengeContact.getAddress();
    // Upgrade the proxy to the V2 implementation.
    challengeV2 = (await upgrades.upgradeProxy(challengeContractAddress, ChallengeV2Factory, {
      unsafeAllow: ["external-library-linking"]
    })) as MockChallengeV2;
    const challengeV2AsV2 = challengeV2 as unknown as MockChallengeV2;

    await challengeV2AsV2.initializeV2();

    const proxyAddressAfter = await challengeV2AsV2.getAddress();
    expect(proxyAddressAfter).to.equal(proxyAddressBefore);
  });

  it("exposes new properties from V2", async () => {
    // Cast the contract to the MockChallengeV2 type
    challengeV2 = (await upgrades.upgradeProxy(challengeContractAddress, ChallengeV2Factory, {
      unsafeAllow: ["external-library-linking"]
    } )) as MockChallengeV2;
    const challengeV2AsV2 = challengeV2 as unknown as MockChallengeV2;
    await challengeV2AsV2.initializeV2();

    const newProp = await challengeV2AsV2.getNewProperty();
    expect(newProp).to.equal("v2");
  });

  it("does not allow setting any properties if the contract is paused", async () => {
    challengeV2 = (await upgrades.upgradeProxy(challengeContractAddress, ChallengeV2Factory, {
      unsafeAllow: ["external-library-linking"]
    })) as MockChallengeV2;
    const challengeV2AsV2 = challengeV2 as unknown as MockChallengeV2;
    await challengeV2AsV2.initializeV2();

    await challengeV2AsV2.connect(deployer).pause();

    await expect(challengeV2AsV2.connect(deployer).setNewProperty("v3")).to.be.revertedWithCustomError(challengeV2AsV2, "EnforcedPause()");

    await challengeV2AsV2.connect(deployer).unpause();
    await challengeV2AsV2.setNewProperty("v3");
    const newProp = await challengeV2AsV2.getNewProperty();
    expect(newProp).to.equal("v3");
  });

  it("overrides functions and works as intended in V2", async () => {
    // For example, test that the addNewChallenger function works as expected.
    // Use the deployer (who is owner) to add a new challenger.
    await challengeV2.addNewChallenger(userAddress);

    // Verify that the challenger was added.
    const isChallenger = await challengeV2.challengerWhitelist(userAddress);
    expect(isChallenger).to.be.true;

    // Next, test createChallenge.
    // Here we have the user (now whitelisted as a challenger) create a challenge.
    const tx = await challengeV2.connect(user).createChallenge(
      1000,    // Challenge length in seconds
      [0],     // Array of metrics (using the V1 constant CHALLENGE_STEPS, which equals 0)
      [100]    // Array of target measurements
    );
    await tx.wait();

    // Retrieve the list of challenges for the user.
    const challenges = await challengeV2.getChallengesForChallenger(userAddress);
    expect(challenges.length).to.equal(1);

    // Check that the active challenge has not been started yet (remains at its default 0).
    const activeChallenge = await challengeV2.challengerToActiveChallenge(userAddress);
    expect(activeChallenge).to.equal(0);
  });

  it("preserves state across upgrades", async () => {
    // Verify that state variables from V1 are still intact.
    // For example, latestChallengeId should be greater than 0 because a challenge was created.
    const latestChallengeId = await challengeV2.latestChallengeId();
    expect(latestChallengeId).to.be.gt(0);
  });

  it("preserves all critical state during an upgrade with an active challenge", async () => {
    // Create a new challenger and bettor
    await challengeContact.addNewChallenger(userAddress);

    // Get initial state before upgrade
    const isUserChallengerBefore = await challengeContact.challengerWhitelist(userAddress);
    expect(isUserChallengerBefore).to.be.true;

    // Create challenge and place bets
    const betAmount = ethers.parseEther("0.05");
    await challengeContact.connect(user).createChallenge(
      3600, // 1 hour in seconds
      [0], // CHALLENGE_STEPS
      [10000] // 10k steps
    );

    // Retrieve the challenge ID
    const challengeIds = await challengeContact.getChallengesForChallenger(userAddress);
    const challengeId = challengeIds[0];

    // Have user place a bet on their own challenge
    await challengeContact.connect(user).placeBet(challengeId, true, { value: betAmount });

    // Have deployer place a bet against the user
    await challengeContact.addNewBettor(deployerAddress);
    await challengeContact.connect(deployer).placeBet(challengeId, false, { value: betAmount });

    // Start the challenge
    await challengeContact.connect(user).startChallenge(challengeId);

    // Store the state before upgrade
    const challengeStatusBefore = await challengeContact.challengeToChallengeStatus(challengeId);
    const challengeStartTimeBefore = await challengeContact.challengeToStartTime(challengeId);
    const challengeLengthBefore = await challengeContact.challengeToChallengeLength(challengeId);
    const betsForBefore = await challengeContact.challengeToTotalAmountBetFor(challengeId);
    const betsAgainstBefore = await challengeContact.challengeToTotalAmountBetAgainst(challengeId);
    const challengerBetBefore = await challengeContact.getBetAmount(challengeId, userAddress, true);
    const deployerBetBefore = await challengeContact.getBetAmount(challengeId, deployerAddress, false);

    // Now perform the upgrade
    const PriceDataFeed = await ethers.getContractFactory("PriceDataFeed");
    const priceDataFeed = await PriceDataFeed.deploy();
    const priceDataFeedAddress = await priceDataFeed.getAddress();
    
    const ChallengeV2Factory = await ethers.getContractFactory("MockChallengeV2", {
      libraries: {
        PriceDataFeed: priceDataFeedAddress
      },
    }, deployer);
    challengeV2 = (await upgrades.upgradeProxy(challengeContractAddress, ChallengeV2Factory, {
      unsafeAllow: ["external-library-linking"]
    })) as MockChallengeV2;
    const challengeV2AsV2 = challengeV2 as unknown as MockChallengeV2;

    // Initialize V2 state
    await challengeV2AsV2.initializeV2();

    // Verify all state was preserved through the upgrade
    const challengeStatusAfter = await challengeV2.challengeToChallengeStatus(challengeId);
    const challengeStartTimeAfter = await challengeV2.challengeToStartTime(challengeId);
    const challengeLengthAfter = await challengeV2.challengeToChallengeLength(challengeId);
    const betsForAfter = await challengeV2.challengeToTotalAmountBetFor(challengeId);
    const betsAgainstAfter = await challengeV2.challengeToTotalAmountBetAgainst(challengeId);
    const challengerBetAfter = await challengeV2.getBetAmount(challengeId, userAddress, true);
    const deployerBetAfter = await challengeV2.getBetAmount(challengeId, deployerAddress, false);

    expect(challengeStatusAfter).to.equal(challengeStatusBefore);
    expect(challengeStartTimeAfter).to.equal(challengeStartTimeBefore);
    expect(challengeLengthAfter).to.equal(challengeLengthBefore);
    expect(betsForAfter).to.equal(betsForBefore);
    expect(betsAgainstAfter).to.equal(betsAgainstBefore);
    expect(challengerBetAfter).to.equal(challengerBetBefore);
    expect(deployerBetAfter).to.equal(deployerBetBefore);

    // Verify the challenge can continue functioning post-upgrade
    const isUserChallengerAfter = await challengeV2.challengerWhitelist(userAddress);
    expect(isUserChallengerAfter).to.be.true;

    // Submit measurements under the upgraded contract
    await challengeV2.connect(user).submitMeasurements(challengeId, [12000]);

    // Now simulate enough time passing to conclude the challenge
    // We'll need to advance time to simulate the challenge ending
    const blockchainTimestamp = (await ethers.provider.getBlock("latest"))!.timestamp;
    const challengeEndTime = Number(challengeStartTimeAfter) + Number(challengeLengthAfter) + 1;
    if (challengeEndTime > blockchainTimestamp) {
      await ethers.provider.send("evm_setNextBlockTimestamp", [challengeEndTime]);
      await ethers.provider.send("evm_mine", []);
    }

    // Finally, distribute winnings to complete the challenge lifecycle
    await challengeV2.connect(deployer).distributeWinnings(challengeId);

    // Verify the challenge is properly concluded
    const challengeStatusFinal = await challengeV2.challengeToChallengeStatus(challengeId);
    const winningsPaid = await challengeV2.challengeToWinningsPaid(challengeId);

    // Status should be 3 (STATUS_CHALLENGER_WON) since they exceeded their target
    expect(challengeStatusFinal).to.equal(3);

    expect(winningsPaid).to.be.greaterThan(0);
  });
});
