// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

contract MockVault {

    address public buffer;

    constructor(address _buffer) {
        buffer = _buffer;
    }

}
