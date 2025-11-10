// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { IALMProxy } from "../interfaces/IALMProxy.sol";

library ApproveLib {

    // NOTE: This logic was inspired by OpenZeppelin's forceApprove in SafeERC20 library.
    function approve(address token, address proxy, address spender, uint256 amount) internal {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, amount));

        // Call doCall on proxy to approve the token.
        ( bool success, bytes memory data )
            = proxy.call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        if (success) {
            // Decode the ABI-encoding of the approve call bytes return data first.
            bytes memory returnData = abi.decode(data, (bytes));

            // Approve was successful if 1) no return value or 2) true return value.
            if (returnData.length == 0 || abi.decode(returnData, (bool))) return;
        }

        // If call was unsuccessful, set to zero and try again.
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));

        bytes memory returnData = IALMProxy(proxy).doCall(token, approveData);

        // Revert if approve returns false.
        require(returnData.length == 0 || abi.decode(returnData, (bool)), "MC/approve-failed");
    }

}
