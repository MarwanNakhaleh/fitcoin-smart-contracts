# Fitcoin (name pending) Smart Contracts 
This repo contains a set of smart contracts that will empower people to bet against each other based on the achievement of some kind of metric. 

The betting is written to focus on fitness, and the easiest way to try this out will be to get people to sign up with Fitbit, regularly pull data from Fitbit's APIs, and call our smart contracts with that information.

## Deployed information
### Base Sepolia

* Challenge contract deployed to: **0x4D47D64E6B00a094E68fDA8a6A919C2183458e10**
* Vault contract deployed to: **0x093FAe391c564540F88D5D7374C312EB1f62C3b7**
* Vault address set in Challenge contract
* MultiplayerChallenge contract deployed to: **0x2eF908dEf08bC0269979E278cc7755EF869484ff**
* Vault address set in MultiplayerChallenge contract
```bash
Deployment successful: {
  challengeContractAddress: '0x4D47D64E6B00a094E68fDA8a6A919C2183458e10',
  vaultContractAddress: '0x093FAe391c564540F88D5D7374C312EB1f62C3b7',
  multiplayerChallengeContractAddress: '0x2eF908dEf08bC0269979E278cc7755EF869484ff'
}
```

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
