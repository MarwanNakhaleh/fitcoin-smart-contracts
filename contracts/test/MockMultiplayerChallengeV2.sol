// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "../MultiplayerChallenge.sol";

/**
 * @title MockMultiplayerChallengeV2
 * @notice Mock V2 implementation of MultiplayerChallenge for testing upgrades
 * @dev This contract adds new properties and overrides existing functions to test the upgrade process
 */
contract MockMultiplayerChallengeV2 is MultiplayerChallenge {
    // New property not present in V1
    string public newV2Property;
    
    uint16 public constant OVERTOOK_LEADER = 1;

    event OvertookLeader(uint256 indexed _challengeId, address indexed _newLeader);
    
    // New state variable to track competitor bonuses
    mapping(uint256 => mapping(address => uint16[])) public challengeToCompetitorBadges;

    /// @notice New initializer for V2. Using reinitializer(2) ensures it can only be called once after upgrade.
    function initializeV2() public reinitializer(2) {
        newV2Property = "multiplayerV2";
    }

    /**
     * @notice Override the submitMeasurements function to add V2 functionality
     * @dev Now also calculates and assigns a bonus based on measurement value
     */
    function submitMeasurements(
        uint256 _challengeId,
        uint256[] calldata _submittedMeasurements
    ) public override {
        // Call the original implementation
        address oldLeader = getLeader(_challengeId);

        super.submitMeasurements(_challengeId, _submittedMeasurements);
        
        // Add V2 functionality: assign a bonus if measurement is high
        address newLeader = getLeader(_challengeId);
        address caller = msg.sender;
        if (newLeader == caller && oldLeader != caller) {
            challengeToCompetitorBadges[_challengeId][caller].push(OVERTOOK_LEADER);
            emit OvertookLeader(_challengeId, caller);
        }
    }

    /**
     * @notice A new V2 function to get a competitor's bonus
     * @param _challengeId The challenge ID
     * @param _competitor The competitor's address
     * @return The bonus amount
     */
    function getCompetitorBadges(uint256 _challengeId, address _competitor) external view returns (uint16[] memory) {
        return challengeToCompetitorBadges[_challengeId][_competitor];
    }

    /**
     * @notice Getter for the new V2 property
     * @return The new V2 property value
     */
    function getNewV2Property() external view returns (string memory) {
        return newV2Property;
    }
} 