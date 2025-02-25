# Fitcoin Smart Contracts (name pending)
This repo contains a set of smart contracts that will empower people to bet against each other based on the achievement of some kind of metric. 

The betting is written to focus on fitness, and the easiest way to try this out will be to get people to sign up with Fitbit, regularly pull data from Fitbit's APIs, and call our smart contracts with that information.

## Local testing

```bash
npm install
npx hardhat typechain
npx hardhat test
```

## Deploying
### Local
Terminal window 1
```bash
npx hardhat node
```

Terminal window 2
```bash
npx hardhat run scripts/DeployContracts.ts --network hardhat
```

### Public

```bash
npx hardhat run scripts/DeployContracts.ts --network <network>
```

Right now, the following networks are supported
* Base
* Base Sepolia
* Arbitrum
* Arbitrum Sepolia
* Optimism 
* Optimism Sepolia

## Useful links for figuring these things out
### Testing against Chainlink price oracles
* https://blog.chain.link/testing-chainlink-smart-contracts/
* https://github.com/PatrickAlphaC/chainlink-hardhat 
