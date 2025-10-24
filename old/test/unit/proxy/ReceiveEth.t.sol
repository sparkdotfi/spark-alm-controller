// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ALMProxy } from "../../../src/ALMProxy.sol";

import "../UnitTestBase.t.sol";

contract ALMProxyReceiveEthTests is UnitTestBase {

    function test_receiveEth() public {
        ALMProxy almProxy = new ALMProxy(admin);

        deal(address(this), 10 ether);

        assertEq(address(this).balance,     10 ether);
        assertEq(address(almProxy).balance, 0);

        payable(address(almProxy)).transfer(10 ether);

        assertEq(address(this).balance,     0);
        assertEq(address(almProxy).balance, 10 ether);
    }

}
