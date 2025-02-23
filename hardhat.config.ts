import "@openzeppelin/hardhat-upgrades";

import { config as dotEnvConfig } from "dotenv";

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "solidity-docgen";

dotEnvConfig();

const config: HardhatUserConfig = {
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
      forking: {
        url: process.env.MAINNET_RPC_URL as string,
        blockNumber: 4776540
      }
    }
  }
};

export default config;
