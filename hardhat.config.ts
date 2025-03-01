import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-ignition-ethers";
import { config as dotEnvConfig } from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-docgen";
import { arbitrumChainId, arbitrumSepoliaChainId, baseChainId, baseSepoliaChainId, optimismChainId, optimismSepoliaChainId } from "./globals";

dotEnvConfig();

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  typechain: {
    outDir: "typechain", 
    target: "ethers-v6",
  },
  networks: {
    hardhat: {},
    running: {
      url: "http://localhost:8545",
      chainId: 31337,
    },
    localhost: {
      url: "http://localhost:8545",
      chainId: 31337,
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: baseSepoliaChainId,
    },
    base: {
      url: process.env.BASE_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: baseChainId
    },
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: arbitrumSepoliaChainId
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: arbitrumChainId
    },
    optimismSepolia: {
      url: process.env.OPTIMISM_SEPOLIA_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: optimismSepoliaChainId
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
      chainId: optimismChainId
    }
  }
};

export default config;
