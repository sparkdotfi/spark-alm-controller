// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

contract MockTarget {

    event ExampleEvent(
        address indexed exampleAddress,
        uint256 exampleValue,
        uint256 exampleReturn,
        address caller,
        uint256 value
    );

    function exampleCall(address exampleAddress, uint256 exampleValue)
        public
        payable
        returns (uint256 exampleReturn)
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

// Target that always reverts, used to verify revert propagation through ALMProxy.doCall*.
contract MockRevertingTarget {

    error MockError();

    function revertWithReason() external payable {
        revert("MockRevertingTarget/reverted");
    }

    function revertWithCustomError() external payable {
        revert MockError();
    }

}

// Target that writes to an arbitrary storage slot and returns the context address,
// used to verify delegatecalls.
contract MockStorageWriter {

    function write(uint256 slot, uint256 value) external returns (address context) {
        assembly {
            sstore(slot, value)
        }

        context = address(this);
    }

}
