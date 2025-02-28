import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-ignition-ethers";
import { config as dotEnvConfig } from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-docgen";

dotEnvConfig();

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
        details: {
          yulDetails: {
            optimizerSteps: "u",
          },
        },
      },
      viaIR: true,
    }
  },
  typechain: {
    outDir: "typechain", 
    target: "ethers-v6",
  },
  networks: {
    hardhat: {

    },
    running: {
      url: "http://localhost:8545",
      chainId: 1337,
    },
    localhost: {
      url: "http://localhost:8545"
    },
    baseSepolia: {
      url: process.env.BASE_SEPOLIA_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    },
    base: {
      url: process.env.BASE_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    },
    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    },
    optimismSepolia: {
      url: process.env.OPTIMISM_SEPOLIA_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL as string,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY as string],
    }
  }
};

export default config;
