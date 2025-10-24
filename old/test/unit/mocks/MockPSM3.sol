
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

contract MockPSM3 {

    address public asset0;
    address public asset1;
    address public asset2;

    constructor(address _asset0, address _asset1, address _asset2) {
        asset0 = _asset0;
        asset1 = _asset1;
        asset2 = _asset2;
    }

}
