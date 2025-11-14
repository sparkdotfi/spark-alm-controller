// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

library MathLib {

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
