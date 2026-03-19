// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

contract MockJug {

    function drip(bytes32) external pure returns (uint256) {
        return 1e27;
    }

}
