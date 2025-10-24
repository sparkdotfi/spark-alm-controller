// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

contract MockPSM {

    address public gem;

    uint256 public to18ConversionFactor = 1e12;

    constructor(address _gem) {
        gem = _gem;
    }

}
