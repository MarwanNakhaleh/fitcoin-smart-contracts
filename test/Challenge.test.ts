import { ethers, upgrades } from "hardhat";
import { AddressLike, Signer, parseEther, BigNumberish } from "ethers";
import { expect } from "chai";
import { Challenge, Challenge__factory, Vault } from "../typechain";

describe("Challenge Tests", () => {
  let challengeContract: Challenge;
  let vaultContract: Vault;
  let owner: Signer;
  let bettor: Signer;
  let bettor2: Signer;
  let challenger: Signer;
  let challengerAddress: AddressLike;

  const ethPriceFactorConversionUnits: bigint = BigInt(1e14); // number of wei in one ETH
  const minimumUsdBetValue: bigint = BigInt(10) * ethPriceFactorConversionUnits;

  const CHALLENGE_STEPS: BigNumberish = 0;
  const CHALLENGE_MILEAGE: BigNumberish = 1;
  const CHALLENGE_CYCLING_MILEAGE: BigNumberish = 2;
  const CHALLENGE_CALORIES_BURNED: BigNumberish = 3;

  let maximumChallengeLengthInSeconds: bigint;
  let maximumNumberOfBettorsPerChallenge: bigint;
  let maximumNumberOfChallengeMetrics: bigint;

  beforeEach(async () => {
    // Add mock price feed
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3Aggregator.deploy(8, 200000000000); // 8 decimals, $2000.00000000 ETH/USD price
    const mockPriceFeedAddress = await mockPriceFeed.getAddress();

    const PriceDataFeed = await ethers.getContractFactory("PriceDataFeed");
    const priceDataFeed = await PriceDataFeed.deploy(); // 8 decimals, $2000.00000000 ETH/USD price
    const priceDataFeedAddress = await priceDataFeed.getAddress();

    const ChallengeFactory: Challenge__factory = await ethers.getContractFactory("Challenge", {
      libraries: {
        PriceDataFeed: priceDataFeedAddress
      },
    });
    [owner, bettor, bettor2, challenger] = await ethers.getSigners();


    maximumNumberOfBettorsPerChallenge = BigInt(100);
    maximumChallengeLengthInSeconds = BigInt(2592000);
    maximumNumberOfChallengeMetrics = BigInt(3);

    challengeContract = await upgrades.deployProxy(
      ChallengeFactory,
      [
        minimumUsdBetValue,
        mockPriceFeedAddress,
        maximumNumberOfBettorsPerChallenge,
        maximumChallengeLengthInSeconds,
        maximumNumberOfChallengeMetrics
      ],
      {
        initializer: 'initialize',
        unsafeAllow: ["external-library-linking"]
      }
    );
    await challengeContract.waitForDeployment();
    const challengeContractAddress = await challengeContract.getAddress();

    const VaultFactory = await ethers.getContractFactory("Vault");
    vaultContract = await upgrades.deployProxy(VaultFactory, [challengeContractAddress], {
      initializer: 'initialize',
      unsafeAllow: ["external-library-linking"]
    });
    await vaultContract.waitForDeployment();

    await challengeContract.connect(owner).setVault(await vaultContract.getAddress());

    challengerAddress = await challenger.getAddress();
  });

  describe("Testing the getters", async () => {
    it("should return the correct minimum USD value of a bet", async () => {
      expect(await challengeContract.getMinimumUsdValueOfBet()).to.equal(minimumUsdBetValue);
    });

    it("should return the correct maximum challenge length", async () => {
      expect(await challengeContract.getMaximumChallengeLength()).to.equal(maximumChallengeLengthInSeconds);
    });

    it("should return the correct maximum number of bettors per challenge", async () => {
      expect(await challengeContract.getMaximumNumberOfBettorsPerChallenge()).to.equal(maximumNumberOfBettorsPerChallenge);
    });

    it("should return the correct maximum number of challenge metrics", async () => {
      expect(await challengeContract.getMaximumNumberOfChallengeMetrics()).to.equal(maximumNumberOfChallengeMetrics);
    });
  });

  describe("Testing the setters", async () => {
    it("should not allow the owner to set the maximum challenge length to be less than the minimum allowed", async () => {
      await expect(challengeContract.connect(owner).setMaximumChallengeLength(0)).to.be.revertedWithCustomError(challengeContract, "ChallengeLengthTooShort");
    });

    it("should allow the owner to set the maximum challenge length to be the minimum allowed", async () => {
      expect(await challengeContract.connect(owner).setMaximumChallengeLength(1)).not.to.be.reverted;
    });

    it("should not allow the owner to set the maximum number of bettors per challenge to be less than the minimum allowed", async () => {
      await expect(challengeContract.connect(owner).setMaximumNumberOfBettorsPerChallenge(0)).to.be.revertedWithCustomError(challengeContract, "MaximumNumberOfBettorsPerChallengeTooSmall");
      await expect(challengeContract.connect(owner).setMaximumNumberOfBettorsPerChallenge(1)).to.be.revertedWithCustomError(challengeContract, "MaximumNumberOfBettorsPerChallengeTooSmall"); // minimum allowed is number of bettors against + 1
    });

    it("should allow the owner to set the maximum number of bettors per challenge to be the minimum allowed", async () => {
      expect(await challengeContract.connect(owner).setMaximumNumberOfBettorsPerChallenge(2)).not.to.be.reverted;
    });

    it("should not allow a non-owner to set any metrics", async () => {
      await expect(challengeContract.connect(bettor).setMaximumChallengeLength(1)).to.be.revertedWithCustomError(challengeContract, "OwnableUnauthorizedAccount");
      await expect(challengeContract.connect(bettor).setMaximumNumberOfBettorsPerChallenge(2)).to.be.revertedWithCustomError(challengeContract, "OwnableUnauthorizedAccount");
      await expect(challengeContract.connect(bettor).setMaximumNumberOfChallengeMetrics(3)).to.be.revertedWithCustomError(challengeContract, "OwnableUnauthorizedAccount");
      await expect(challengeContract.connect(bettor).setMinimumBetValue(1)).to.be.revertedWithCustomError(challengeContract, "OwnableUnauthorizedAccount");
    });
  });

  describe("Attempting to create a challenge with invalid parameters", () => {
    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5
    const targetMeasurements = [targetNumberOfSteps, targetNumberOfMiles]

    let challengeLength: bigint;

    beforeEach(async () => {
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);
      expect(await challengeContract.challengerWhitelist(challengerAddress)).to.be.true;
      challengeLength = BigInt(60 * 60);
    });

    it("should not allow a non-whitelisted address to create a challenge", async () => {
      await expect(challengeContract.connect(bettor).createChallenge(challengeLength, challengeMetrics, targetMeasurements))
        .to.be.revertedWithCustomError(challengeContract, "ChallengerNotInWhitelist");
    });

    it("should not allow challenge length to be greater than the maximum allowed", async () => {
      challengeLength = BigInt(2592001); // 30 days + 1 second, maximum allowed challenge length is 30 days exactly
      await expect(challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements))
        .to.be.revertedWithCustomError(challengeContract, "ChallengeLengthTooLong");
    });

    it("should not allow a challenge to have malformed metrics", async () => {
      const targetNumberOfCaloriesBurned = 1000;
      const malformedTargetMeasurements = [
        ...targetMeasurements,
        targetNumberOfCaloriesBurned
      ];
      // 2 challenge metrics provided, but 3 target measurements provided
      await expect(challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, malformedTargetMeasurements))
        .to.be.revertedWithCustomError(challengeContract, "MalformedChallengeMetricsProvided");
    });

    describe("Testing the maximum number of challenge metrics", async () => {
      const tooManyChallengeMetrics = [
        ...challengeMetrics,
        CHALLENGE_CALORIES_BURNED,
        CHALLENGE_CYCLING_MILEAGE
      ];
      const targetNumberOfCaloriesBurned = 1000;
      const targetCyclingMileage = 100;
      const tooManyChallengeTargetMeasurements = [
        ...targetMeasurements,
        targetNumberOfCaloriesBurned,
        targetCyclingMileage
      ];

      it("should not allow a challenge to have more than the set number of metrics", async () => {
        await expect(challengeContract.connect(challenger).createChallenge(challengeLength, tooManyChallengeMetrics, tooManyChallengeTargetMeasurements))
          .to.be.revertedWithCustomError(challengeContract, "TooManyChallengeMetrics");
      });

      it("should allow a challenge to more metrics after the owner changes the maximum number of challenge metrics", async () => {
        await challengeContract.connect(owner).setMaximumNumberOfChallengeMetrics(4);

        await expect(challengeContract.connect(challenger).createChallenge(challengeLength, tooManyChallengeMetrics, tooManyChallengeTargetMeasurements))
      });
    });
  });

  describe("Creating and betting on a challenge", async () => {
    const betAmount = parseEther("1");

    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5
    const targetMeasurements = [targetNumberOfSteps, targetNumberOfMiles]
    const challengeLength = BigInt(60 * 60) // 1 hour challenge time
    let challengeId: bigint;

    beforeEach(async () => {
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);
      await challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements);
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      challengeId = challengeIds[0];
    });

    it("should return the correct challenge ID when creating the first challenge", async () => {
      expect(challengeId).to.equal(0);
    });

    it("should not allow a bettor to place a bet on a challenge if he is not whitelisted", async () => {
      await expect(challengeContract.connect(bettor).placeBet(0, false, {
        value: betAmount,
      })).to.be.revertedWithCustomError(challengeContract, "BettorNotInWhitelist");
    });

    it("should allow a bettor to place a bet on a challenge if he is whitelisted", async () => {
      await challengeContract.connect(owner).addNewBettor(bettor.getAddress());
      await challengeContract.connect(bettor).placeBet(0, false, {
        value: betAmount,
      });
    });

    it("should not allow placing a bet after the challenge has started", async () => {
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
      ).to.be.revertedWithCustomError(challengeContract, "ChallengeCannotBeModified");
    });

    it("does not allow a bet under the minimum USD value of ETH needed", async () => {
      const latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
      const tinyBetAmount = 0.004 * Number(latestEthPrice); // $8.00 at test ETH price of $2000.00

      await expect(
        challengeContract.connect(challenger).placeBet(challengeId, true, { value: BigInt(tinyBetAmount) })
      ).to.be.revertedWithCustomError(challengeContract, "MinimumBetAmountTooSmall");
    });

    it("allows a bet just above the minimum USD value of ETH needed", async () => {
      const latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
      const tinyBetAmount = 0.005 * Number(latestEthPrice); // $10.00 at test ETH price of $2000.00

      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      const challengeId = challengeIds[0];

      await expect(
        challengeContract.connect(challenger).placeBet(challengeId, true, { value: BigInt(tinyBetAmount) })
      ).not.to.be.reverted;
    });

    it("should not allow the challenger to start the challenge without enough bettors", async () => {
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      const challengeId = challengeIds[0];

      await expect(
        challengeContract.connect(challenger).startChallenge(challengeId)
      ).to.be.revertedWithCustomError(challengeContract, "NobodyBettingAgainstChallenger");
    });

    it("should allow the challenger to start the challenge when there are enough bettors", async () => {
      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
      const challengeId = challengeIds[0];

      const initialChallengerBalance = await ethers.provider.getBalance(challenger.getAddress());

      // Place bet for the challenger
      await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount });

      // Check the contract balance to ensure the bet amount was transferred
      const vaultBalance = await vaultContract.getBalance(false); // false indicates ETH
      expect(vaultBalance).to.equal(betAmount);

      // Check the challenger's balance after placing the bet
      const challengerBalanceAfterBetting = await ethers.provider.getBalance(challenger.getAddress());

      // The challenger's balance should be reduced by the bet amount plus gas fees
      expect(challengerBalanceAfterBetting).to.be.lessThan(initialChallengerBalance - betAmount);

      await challengeContract.connect(owner).addNewBettor(bettor2.getAddress());
      await challengeContract.connect(bettor2).placeBet(challengeId, false, { value: betAmount });

      await challengeContract.connect(challenger).startChallenge(challengeId);

      const challengeStatus = await challengeContract.challengeToChallengeStatus(challengeId);
      expect(challengeStatus).to.equal(1); // ChallengeStatus.Active
    });

    describe("Concluding the challenge", async () => {
      let initialBettorBalance: bigint;
      let initialBettor2Balance: bigint;
      let initialChallengerBalance: bigint;
      let challengeId: bigint;
      let latestEthPrice: bigint;
      let betAmount: bigint;

      beforeEach(async () => {
        latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
        betAmount = parseEther("1");

        initialBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
        initialBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
        initialChallengerBalance = await ethers.provider.getBalance(challengerAddress);

        const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);
        challengeId = challengeIds[0];

        await challengeContract.connect(owner).addNewBettor(bettor.getAddress());
        await challengeContract.connect(owner).addNewBettor(bettor2.getAddress());
      });

      it("should not allow a challenger to submit measurements on an expired challenge", async () => {
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

      it("should not allow distribution of winnings before the challenge time has elapsed", async () => {
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

      it("should distribute winnings to the people who bet for the challenger if the challenger wins", async () => {
        // Place bets
        const bettorPlaceBetTx = await challengeContract.connect(bettor).placeBet(challengeId, true, { value: betAmount });
        await bettorPlaceBetTx.wait();
        const bettorBalanceAfterBetting = await ethers.provider.getBalance(bettor.getAddress());

        const bettor2PlaceBetTx = await challengeContract.connect(bettor2).placeBet(challengeId, false, { value: betAmount });
        await bettor2PlaceBetTx.wait();
        const bettor2BalanceAfterBetting = await ethers.provider.getBalance(bettor2.getAddress());

        const challengerPlaceBetTx = await challengeContract.connect(challenger).placeBet(challengeId, true, { value: betAmount });
        await challengerPlaceBetTx.wait();
        const challengerBalanceAfterBetting = await ethers.provider.getBalance(challengerAddress);

        // Start and submit measurements for the challenge
        await challengeContract.connect(challenger).startChallenge(challengeId);
        await challengeContract.connect(challenger).submitMeasurements(challengeId, [10000, 5]);

        // Move time forward to simulate challenge end
        const pastTimestamp = (await ethers.provider.getBlock('latest') || { timestamp: 0 }).timestamp + (3600 + 1);
        await ethers.provider.send("evm_setNextBlockTimestamp", [pastTimestamp]);
        await ethers.provider.send("evm_mine", []);

        const vaultBalanceBefore = await vaultContract.getBalance(false);

        // Distribute winnings
        await challengeContract.connect(owner).distributeWinnings(challengeId);

        const vaultBalanceAfter = await vaultContract.getBalance(false);
        expect(vaultBalanceAfter).to.be.below(vaultBalanceBefore);

        // Capture final balances
        const finalBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
        const finalBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
        const finalChallengerBalance = await ethers.provider.getBalance(challengerAddress);

        // Calculate expected winnings
        const expectedBettorWinnings = betAmount + (betAmount / BigInt(2));
        const expectedChallengerWinnings = betAmount + (betAmount / BigInt(2));
        // Adjust assertions to account for gas costs
        expect(finalBettorBalance).to.equal(bettorBalanceAfterBetting + expectedBettorWinnings);
        expect(finalChallengerBalance).to.be.closeTo(challengerBalanceAfterBetting + expectedChallengerWinnings, parseEther("0.001"));
        expect(finalBettor2Balance).to.equal(bettor2BalanceAfterBetting);
      });
    })

    describe("Handling oracle data issues", () => {
      it("should handle price feed returning zero or extremely low values", async () => {
        // Deploy a mock price feed with zero price
        const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
        const mockPriceFeedZero = await MockV3Aggregator.deploy(8, 0); // $0.00000000 ETH/USD price
        const mockPriceFeedZeroAddress = await mockPriceFeedZero.getAddress();

        const PriceDataFeed = await ethers.getContractFactory("PriceDataFeed");
        const priceDataFeed = await PriceDataFeed.deploy(); // 8 decimals, $2000.00000000 ETH/USD price
        const priceDataFeedAddress = await priceDataFeed.getAddress();

        // Deploy a new challenge contract with the zero-price feed
        const ChallengeFactory: Challenge__factory = await ethers.getContractFactory("Challenge", {
          libraries: {
            PriceDataFeed: priceDataFeedAddress
          },
        });
        const zeroPriceChallenge = await upgrades.deployProxy(
          ChallengeFactory,
          [
            minimumUsdBetValue,
            mockPriceFeedZeroAddress,
            100, // maximumNumberOfBettorsPerChallenge
            2592000, // maximumChallengeLengthInSeconds (30 days)
            3 // maximumNumberOfChallengeMetrics
          ],
          {
            initializer: 'initialize',
            unsafeAllow: ["external-library-linking"]
          }
        );

        await zeroPriceChallenge.waitForDeployment();
        const zeroPriceChallengeAddress = await zeroPriceChallenge.getAddress();

        // Set the vault
        const VaultFactory = await ethers.getContractFactory("Vault");
        const vault = await upgrades.deployProxy(VaultFactory, [zeroPriceChallengeAddress], {
          initializer: 'initialize',
          unsafeAllow: ["external-library-linking"]
        });
        await vault.waitForDeployment();
        const vaultAddress = await vault.getAddress();

        // Vault needs to be set
        zeroPriceChallenge.connect(owner).setVault(vaultAddress);

        // Now try to get the latest price - this should not revert but should return 0
        const price = await zeroPriceChallenge.getLatestPrice();
        expect(price).to.equal(0);

        // With a price of 0, any bet amount should fail the minimum check
        await zeroPriceChallenge.connect(owner).addNewChallenger(challengerAddress);

        const challengeMetricsArray: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
        const targetNumberOfSteps: BigNumberish = 10000;
        const targetNumberOfMiles: BigNumberish = 5;
        const targetMeasurementsArray = [targetNumberOfSteps, targetNumberOfMiles];
        const challengeLengthValue = BigInt(60 * 60); // 1 hour

        await zeroPriceChallenge.connect(challenger).createChallenge(
          challengeLengthValue,
          challengeMetricsArray,
          targetMeasurementsArray
        );

        const challengeIds = await zeroPriceChallenge.getChallengesForChallenger(challengerAddress);
        const challengeId = challengeIds[0];

        // Even with a large bet, it should fail since price * bet < minimum
        await expect(
          zeroPriceChallenge.connect(challenger).placeBet(challengeId, true, { value: parseEther("100") })
        ).to.be.revertedWithCustomError(zeroPriceChallenge, "MinimumBetAmountTooSmall");
      });
    });

    describe("Gas limitations with many bettors", () => {
      it("should handle distributing winnings to many bettors without running out of gas", async () => {
        // Deploy a new instance with a higher limit of bettors
        const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
        const mockPriceFeed = await MockV3Aggregator.deploy(8, 200000000000); // $2000.00000000 ETH/USD price
        const mockPriceFeedAddress = await mockPriceFeed.getAddress();

        const maxBettors = 20; // Set to a reasonable number for testing - in production could be much higher

        const PriceDataFeed = await ethers.getContractFactory("PriceDataFeed");
        const priceDataFeed = await PriceDataFeed.deploy(); // 8 decimals, $2000.00000000 ETH/USD price
        const priceDataFeedAddress = await priceDataFeed.getAddress();

        const ChallengeFactory = await ethers.getContractFactory("Challenge", {
          libraries: {
            PriceDataFeed: priceDataFeedAddress
          },
        });
        const manyBettorsChallenge = await upgrades.deployProxy(
          ChallengeFactory,
          [
            minimumUsdBetValue,
            mockPriceFeedAddress,
            maxBettors,
            2592000, // 30 days
            3 // max metrics
          ],
          {
            initializer: 'initialize',
            unsafeAllow: ["external-library-linking"]
          }
        );

        await manyBettorsChallenge.waitForDeployment();
        const manyBettorsChallengeAddress = await manyBettorsChallenge.getAddress();

        const vaultFactory = await ethers.getContractFactory("Vault");
        const vault = await upgrades.deployProxy(vaultFactory, [manyBettorsChallengeAddress], {
          initializer: 'initialize',
          unsafeAllow: ["external-library-linking"]
        });
        await vault.waitForDeployment();
        const vaultAddress = await vault.getAddress();

        manyBettorsChallenge.connect(owner).setVault(vaultAddress);

        // Create a challenge
        await manyBettorsChallenge.connect(owner).addNewChallenger(challengerAddress);

        const challengeMetricsArray: BigNumberish[] = [CHALLENGE_STEPS];
        const targetNumberOfSteps: BigNumberish = 10000;
        const targetMeasurementsArray = [targetNumberOfSteps];
        const challengeLengthValue = BigInt(60 * 60); // 1 hour

        await manyBettorsChallenge.connect(challenger).createChallenge(
          challengeLengthValue,
          challengeMetricsArray,
          targetMeasurementsArray
        );

        const challengeIds = await manyBettorsChallenge.getChallengesForChallenger(challengerAddress);
        const challengeId = challengeIds[0];

        // Have the challenger place a bet
        await manyBettorsChallenge.connect(challenger).placeBet(challengeId, true, { value: parseEther("1") });

        // Create multiple bettors and have them place bets
        const bettorsFor = [];
        const bettorsAgainst = [];
        // Adding 17 bettors for the test, 8 betting for the challenger and 9 betting against the challenger
        // the total becomes 18 bettors, and the challenger is betting for himself
        for (let i = 0; i < 17; i++) {
          const newBettor = ethers.Wallet.createRandom().connect(ethers.provider);

          // Fund the bettor
          await owner.sendTransaction({
            to: await newBettor.getAddress(),
            value: parseEther("2") // Fund with 2 ETH
          });

          // Add bettor to whitelist and place bet
          await manyBettorsChallenge.connect(owner).addNewBettor(await newBettor.getAddress());

          if (i % 2 === 0) {
            bettorsAgainst.push(newBettor);
            await manyBettorsChallenge.connect(newBettor).placeBet(challengeId, false, { value: parseEther("1") });
          } else {
            bettorsFor.push(newBettor);
            await manyBettorsChallenge.connect(newBettor).placeBet(challengeId, true, { value: parseEther("1") });
          }
        }

        // Start the challenge
        await manyBettorsChallenge.connect(challenger).startChallenge(challengeId);

        // Submit measurements that succeed
        await manyBettorsChallenge.connect(challenger).submitMeasurements(challengeId, [targetNumberOfSteps]);

        // Move time forward past challenge end
        const challengeStartTime = await manyBettorsChallenge.challengeToStartTime(challengeId);
        const challengeLength = await manyBettorsChallenge.challengeToChallengeLength(challengeId);
        const futureTimestamp = challengeStartTime + challengeLength + BigInt(100);
        await ethers.provider.send("evm_setNextBlockTimestamp", [Number(futureTimestamp)]);
        await ethers.provider.send("evm_mine", []);

        // Now distribute winnings - this should handle many transactions without gas issues
        const tx = await manyBettorsChallenge.connect(owner).distributeWinnings(challengeId);
        const receipt = await tx.wait();

        // Check the gas used is reasonable (not approaching block gas limit)
        expect(receipt?.gasUsed).to.be.lt(5000000); // Block gas limit is typically around 30M on Ethereum

        // Check that winnings were marked as paid
        expect(await manyBettorsChallenge.challengeToWinningsPaid(challengeId)).to.be.greaterThan(0);

        const eachGeneratedBettorWalletAmountAfterBetting = parseEther("1");
        const receivedAmountForSuccessfulBets = parseEther("2");

        bettorsFor.forEach(async (bettor) => {
          const finalBettorBalance = await ethers.provider.getBalance(await bettor.getAddress());
          expect(finalBettorBalance).to.be.closeTo(eachGeneratedBettorWalletAmountAfterBetting + receivedAmountForSuccessfulBets, parseEther("0.001"));
        });

        bettorsAgainst.forEach(async (bettor) => {
          const finalBettorBalance = await ethers.provider.getBalance(await bettor.getAddress());
          expect(finalBettorBalance).to.be.closeTo(eachGeneratedBettorWalletAmountAfterBetting, parseEther("0.001"));
        });
      });
    });
  });
});
