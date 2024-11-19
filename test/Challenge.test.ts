import { ethers, upgrades } from "hardhat";
import { AddressLike, Signer, parseEther, BigNumberish} from "ethers";
import { expect } from "chai";
import { Challenge, Challenge__factory } from "../typechain";

describe("Challenge Tests", function () {
  let challengeContract: Challenge;
  let owner: Signer;
  let bettor: Signer;
  let bettor2: Signer;
  let challenger: Signer;

  const ethPriceFactorConversionUnits: bigint = BigInt(1e14); // number of wei in one ETH
  const minimumUsdBetValue: bigint = BigInt(10) * ethPriceFactorConversionUnits;

  const CHALLENGE_STEPS: BigNumberish = 0;
  const CHALLENGE_MILEAGE: BigNumberish = 1;
  const CHALLENGE_CYCLING: BigNumberish = 2;
  const CHALLENGE_CALORIES_BURNED: BigNumberish = 3;

  const dataFeedAddress: AddressLike = "0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70"

  beforeEach(async function () {
    const ChallengeFactory: Challenge__factory = await ethers.getContractFactory("Challenge");
    [owner, bettor, bettor2, challenger] = await ethers.getSigners();

    challengeContract = await upgrades.deployProxy(
      ChallengeFactory, 
      [minimumUsdBetValue, dataFeedAddress], 
      { initializer: 'initialize' } // Specify the initializer function
    );
    await challengeContract.waitForDeployment();
  });

  describe("Creating and betting on a challenge", async () => {
    const betAmount = parseEther("1");
    
    const challengeMetrics: BigNumberish[] = [CHALLENGE_STEPS, CHALLENGE_MILEAGE];
    const targetNumberOfSteps: BigNumberish = 10000;
    const targetNumberOfMiles: BigNumberish = 5
    const targetMeasurements= [targetNumberOfSteps, targetNumberOfMiles]
    const challengeLength = BigInt(60 * 60) // 1 hour challenge time

    it("should return the correct challenge ID when creating the first challenge", async function () {
      const challengerAddress = await challenger.getAddress();
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);

      await challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements);

      const challengeIds = await challengeContract.getChallengesForChallenger(challengerAddress);

      expect(challengeIds[0]).to.equal(0);
    });

    it("should not allow a bettor to place a bet on a challenge if he is not whitelisted", async function () {
      const challengerAddress = await challenger.getAddress();
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);

      await challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements);

      await expect(challengeContract.connect(bettor).placeBet(0, false, {
        value: betAmount,
      })).to.be.revertedWithCustomError(challengeContract, "BettorNotInWhitelist");
    });

    it("should allow a bettor to place a bet on a challenge if he is whitelisted", async function () {
      const challengerAddress = await challenger.getAddress();
      await challengeContract.connect(owner).addNewChallenger(challengerAddress);

      await challengeContract.connect(challenger).createChallenge(challengeLength, challengeMetrics, targetMeasurements);

      await challengeContract.connect(owner).addNewBettor(bettor.getAddress());
      await challengeContract.connect(bettor).placeBet(0, false, {
        value: betAmount,
      });
    });
  
    // it("should not allow placing a bet after the challenge has started", async function () {
    //   await challengeContract.connect(challenger).placeBet(challenger.getAddress(), true, { value: betAmount });
    //   await challengeContract.connect(challenger).startChallenge(0);

    //   const challenge = await challengeContract.challenges(challenger.getAddress());

    //   expect(challenge.numberOfBettorsFor).to.equal(1);
    //   expect(challenge.numberOfBettorsAgainst).to.equal(1);
      
    //   await expect(
    //     challengeContract.connect(bettor2).placeBet(challenger.getAddress(), true, { value: betAmount })
    //   ).to.be.revertedWith("Challenge has already been started");
    // });

    // it("does not allow a bet under the minimum USD value of ETH needed", async function () {
    //   const latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
    //   const tinyBetAmount = 0.004 * Number(latestEthPrice); // 0.001 ETH

    //   await expect(
    //     challengeContract.connect(challenger).placeBet(challenger.getAddress(), true, { value: BigInt(tinyBetAmount) })
    //   ).to.be.revertedWith("Amount is less than minimum bet!")
    // });

    // it("allows a bet just above the minimum USD value of ETH needed", async function () {
    //   const latestEthPrice = await challengeContract.connect(owner).getLatestPrice();
    //   const tinyBetAmount = 0.005 * Number(latestEthPrice); // 0.005 ETH, equal to ~$12.50 at time of testing

    //   await expect(
    //     challengeContract.connect(challenger).placeBet(challenger.getAddress(), true, { value: BigInt(tinyBetAmount) })
    //   ).not.to.be.reverted;
    // });
  });


  // describe("Creating a challenge and betting before it starts", async () => {
  //   const betAmount = parseEther("1");

  //   beforeEach(async function () {
  //     await challengeContract.connect(challenger).createChallenge(60 * 60, 0, 9000);  
  //     await challengeContract.connect(bettor).placeBet(challenger.getAddress(), true, { value: betAmount });
  //     await challengeContract.connect(challenger).placeBet(challenger.getAddress(), true, { value: betAmount });
  //   });

  //   it("should not allow the challenger to start the challenge without enough bettors", async function () {
  //     await expect(
  //       challengeContract.connect(challenger).startChallenge(100)
  //     ).to.be.revertedWith("Not enough people have bet on the challenge for it to start!");
  //   });
    
  //   it("should allow the challenger to start the challenge when there are enough bettors", async function () {
  //     await challengeContract.connect(bettor2).placeBet(challenger.getAddress(), false, { value: betAmount });

  //     await challengeContract.connect(challenger).startChallenge(100);
  
  //     const challenge = await challengeContract.challenges(challenger.getAddress());
  //     expect(challenge.status).to.equal(1); // ChallengeStatus.Active
  //   });
  // });

  // describe("Concluding the challenge", async () => {
  //   let initialBettorBalance: bigint;
  //   let initialBettor2Balance: bigint;
  //   let initialChallengerBalance: bigint;
    
  //   beforeEach("", async () => {
  //     await challengeContract.connect(challenger).createChallenge(60 * 60, 0, 9000);
  //     const betAmount = parseEther("1");
  
  //     initialBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
  //     initialBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
  //     initialChallengerBalance = await ethers.provider.getBalance(challenger.getAddress());
      
  //     await challengeContract.connect(bettor).placeBet(challenger.getAddress(), true, { value: betAmount }); // wins half of bettor2's money
  //     await challengeContract.connect(bettor2).placeBet(challenger.getAddress(), false, { value: betAmount }); // loses all of his money
  //     await challengeContract.connect(challenger).placeBet(challenger.getAddress(), true, { value: betAmount }); // wins half of bettor2's money

  //     await challengeContract.connect(challenger).startChallenge(100);
  //   });

  //   it("should not allow distribution of winnings before the challenge time has elapsed", async function () {      
  //     await challengeContract.connect(owner).submitMeasurement(challenger.getAddress(), 10000);

  //     await expect(challengeContract.connect(owner).distributeWinnings(challenger.getAddress())).to.be.revertedWith("Challenge time has not elapsed!");
  //   });

  //   it("should distribute winnings to bettors correctly after the challenge is completed", async function () {      
  //     await challengeContract.connect(owner).submitMeasurement(challenger.getAddress(), 10000);

  //     const pastTimestamp = (await ethers.provider.getBlock('latest') || {timestamp: 0}).timestamp + (3600 + 1);
      
  //     await ethers.provider.send("evm_setNextBlockTimestamp", [pastTimestamp]);
  //     await ethers.provider.send("evm_mine", []);

  //     await challengeContract.connect(owner).distributeWinnings(challenger.getAddress());
  
  //     // bettor2 should lose his money, and since bettor and challenger bet the same amount, bettor2's money should be split between them
  //     const finalBettorBalance = await ethers.provider.getBalance(bettor.getAddress());
  //     const finalBettor2Balance = await ethers.provider.getBalance(bettor2.getAddress());
  //     const finalChallengerBalance = await ethers.provider.getBalance(challenger.getAddress());
      
  //     // the following calculations include gas fee differences
  //     expect(finalBettorBalance).to.be.lessThan(initialBettorBalance + parseEther("0.5"));
  //     expect(finalBettorBalance).to.be.greaterThan(initialBettorBalance + parseEther("0.495"));
  //     expect(finalBettor2Balance).to.lessThan(initialBettor2Balance - parseEther("1"));
  //     expect(finalBettor2Balance).to.greaterThan(initialBettor2Balance - parseEther("1.05"));
  //     expect(finalChallengerBalance).to.be.lessThan(initialChallengerBalance + parseEther("0.5"));
  //     expect(finalChallengerBalance).to.be.greaterThan(initialChallengerBalance + parseEther("0.495"));
  //   });
  // })
});
