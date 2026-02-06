// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { Ownable } from "../../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract MockVat is Ownable {

    uint256 public ilkLine;

    constructor(address _owner) Ownable(_owner) {
        ilkLine = 1e9 * 1e45;  // Just make it some really large number by default so we can ignore
    }

    function ilks(bytes32)
        external
        view
        returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust) {
        return (0, 1e27, 0, ilkLine, 0);
    }

    function setIlkLine(uint256 _line) external onlyOwner {
        ilkLine = _line;
    }

    function hope(address usr) external {
    }

    function frob(bytes32 i, address u, address v, address w, int dink, int dart) external {
    }

}
