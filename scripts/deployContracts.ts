import hre from "hardhat";
import { ethers, upgrades } from "hardhat";
import deployParams from "./params/deployParams.json";
import { arbitrumSepoliaChainId, baseSepoliaChainId, hardhatChainId, optimismSepoliaChainId, baseChainId, arbitrumChainId, optimismChainId } from "../globals";
import { localhostChainId } from "../globals";

const deployFunc = async () => {
  // Determine the price feed address based on the network.
  const network = hre.network.config.chainId;
  let priceFeedAddress;

  switch (network) {
    case localhostChainId:
    case hardhatChainId: {
      const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
      const mockPriceFeed = await MockV3Aggregator.deploy(8, 200000000000);
      await mockPriceFeed.waitForDeployment();
      priceFeedAddress = await mockPriceFeed.getAddress();
      break;
    }
    case baseSepoliaChainId:
      priceFeedAddress = deployParams.baseSepolia.priceFeedAddress;
      break;
    case arbitrumSepoliaChainId:
      priceFeedAddress = deployParams.arbitrumSepolia.priceFeedAddress;
      break;
    case optimismSepoliaChainId:
      priceFeedAddress = deployParams.optimismSepolia.priceFeedAddress;
      break;
    case baseChainId:
      priceFeedAddress = deployParams.base.priceFeedAddress;
      break;
    case arbitrumChainId:
      priceFeedAddress = deployParams.arbitrum.priceFeedAddress;
      break;
    case optimismChainId:
      priceFeedAddress = deployParams.optimism.priceFeedAddress;
      break;
    default:
      throw new Error(`Unsupported network: ${network}`);
  }

  // Deploy Challenge contract using the upgradeable proxy pattern.
  const ChallengeFactory = await ethers.getContractFactory("Challenge");
  const minimumUsdBetValue = BigInt(deployParams.general.minimumUsdBetValue) * BigInt(1e14);
  const maximumChallengeLengthInSeconds = deployParams.general.maximumChallengeLengthInSeconds;
  const maximumNumberOfChallengeMetrics = deployParams.general.maximumNumberOfChallengeMetrics;
  const maximumNumberOfBettorsPerChallenge = deployParams.general.maximumNumberOfBettorsPerChallenge;
  const challengeContract = await upgrades.deployProxy(
    ChallengeFactory,
    [
      minimumUsdBetValue, 
      priceFeedAddress,
      maximumNumberOfBettorsPerChallenge,
      maximumChallengeLengthInSeconds,
      maximumNumberOfChallengeMetrics
    ],
    { 
      initializer: "initialize",
      unsafeAllow: ["external-library-linking"]
     }
  );
  await challengeContract.waitForDeployment();
  const challengeContractAddress = await challengeContract.getAddress();
  console.log("Challenge contract deployed to:", challengeContractAddress);

  // Deploy Vault contract using the upgradeable proxy pattern.
  const VaultFactory = await ethers.getContractFactory("Vault");
  const vaultContract = await upgrades.deployProxy(
    VaultFactory,
    [challengeContractAddress],
    { 
      initializer: "initialize",
      unsafeAllow: ["external-library-linking"]
     }
  );
  await vaultContract.waitForDeployment();
  const vaultContractAddress = await vaultContract.getAddress();
  console.log("Vault contract deployed to:", vaultContractAddress);

  // Set the vault address in the Challenge contract.
  const challengeSetVaultTx = await challengeContract.setVault(vaultContractAddress);
  await challengeSetVaultTx.wait();
  console.log("Vault address set in Challenge contract");

  // Deploy MultiplayerChallenge contract using the upgradeable proxy pattern.
  const maximumNumberOfChallengeCompetitors = deployParams.general.maximumNumberOfChallengeCompetitors;

  const MultiplayerChallengeFactory = await ethers.getContractFactory("MultiplayerChallenge");
  const multiplayerChallengeContract = await upgrades.deployProxy(
    MultiplayerChallengeFactory,
    [
      minimumUsdBetValue, 
      maximumNumberOfChallengeCompetitors, 
      priceFeedAddress,
      maximumNumberOfBettorsPerChallenge,
      maximumChallengeLengthInSeconds,
      maximumNumberOfChallengeMetrics
    ],
    { 
      initializer: "initializeMultiplayerChallenge",
      unsafeAllow: ["external-library-linking"]
     }
  );
  await multiplayerChallengeContract.waitForDeployment();
  const multiplayerChallengeContractAddress = await multiplayerChallengeContract.getAddress();
  console.log("MultiplayerChallenge contract deployed to:", multiplayerChallengeContractAddress);

  const multiplayerChallengeSetVaultTx = await multiplayerChallengeContract.setVault(vaultContractAddress);
  await multiplayerChallengeSetVaultTx.wait();
  console.log("Vault address set in MultiplayerChallenge contract");
  
  return {
    challengeContractAddress,
    vaultContractAddress,
    multiplayerChallengeContractAddress,
  };
};

async function main() {
  const deployedContracts = await deployFunc();
  console.log("Deployment successful:", deployedContracts);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deployment failed:", error);
    process.exit(1);
  });
