// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

contract MockTarget {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    function exampleCall(address exampleAddress, uint256 exampleValue)
        public payable returns (uint256 exampleReturn)
    {
        exampleReturn = exampleValue * 2;
        emit ExampleEvent(
            exampleAddress,
            exampleValue,
            exampleReturn,
            msg.sender,
            msg.value
        );
    }

}
