import hre from "hardhat";
import { ethers, upgrades } from "hardhat";
import deployParams from "./params/deployParams.json";

const baseChainId = 8453;
const baseSepoliaChainId = 84532;
const arbitrumChainId = 42161;
const arbitrumSepoliaChainId = 421614;
const optimismChainId = 10;
const optimismSepoliaChainId = 11155420;
const localhostChainId = 1337;
const hardhatChainId = 31337;

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
  const minimumUsdBetValue = BigInt(10) * BigInt(1e14); // Adjust as needed
  const challengeContract = await upgrades.deployProxy(
    ChallengeFactory,
    [minimumUsdBetValue, priceFeedAddress],
    { initializer: "initialize" }
  );
  await challengeContract.waitForDeployment();
  const challengeContractAddress = await challengeContract.getAddress();
  console.log("Challenge contract deployed to:", challengeContractAddress);

  // Deploy Vault contract using the upgradeable proxy pattern.
  const VaultFactory = await ethers.getContractFactory("Vault");
  const vaultContract = await upgrades.deployProxy(
    VaultFactory,
    [challengeContractAddress],
    { initializer: "initialize" }
  );
  await vaultContract.waitForDeployment();
  const vaultContractAddress = await vaultContract.getAddress();
  console.log("Vault contract deployed to:", vaultContractAddress);

  // Set the vault address in the Challenge contract.
  const tx = await challengeContract.setVault(vaultContractAddress);
  await tx.wait();
  console.log("Vault address set in Challenge contract");

  return {
    challengeContractAddress,
    vaultContractAddress,
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
