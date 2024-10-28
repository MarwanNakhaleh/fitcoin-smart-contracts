// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MINIMUM_BET_VALUE = 5;

const ChallengeContractModule = buildModule("ChallengeContractModule", (m) => {
  const minimumBetValue = m.getParameter("minimumBetValue", MINIMUM_BET_VALUE);

  const challengeContract = m.contract("", [minimumBetValue]);

  return { challengeContract };
});

export default ChallengeContractModule;
