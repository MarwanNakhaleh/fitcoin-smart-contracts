// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "../Challenge.sol";

contract MockChallengeV2 is Challenge {
    // new property not present in V1
    string public newProperty;

    /// @notice New initializer for V2. Use reinitializer(2) so it can only be called once after upgrade.
    function initializeV2() public reinitializer(2) {
        newProperty = "v2";
    }

    // Example: override a virtual function from V1 to add new behavior
    function addNewChallenger(address challenger) public override onlyOwner {
        Challenge.addNewChallenger(challenger);
        // (Additional V2 behavior can be added here)
    }

    // Similarly, you can override additional virtual functions as needed

    /// @notice Getter for the new property
    function getNewProperty() external view returns (string memory) {
        return newProperty;
    }
}
