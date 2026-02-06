// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy } from "../interfaces/IALMProxy.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool success);

}

library ApproveLib {

    // NOTE: This logic was inspired by OpenZeppelin's forceApprove in SafeERC20 library.
    function approve(address token, address proxy, address spender, uint256 amount) internal {
        bytes memory approveData = abi.encodeCall(IERC20Like.approve, (spender, amount));

        // Call doCall on proxy to approve the token.
        ( bool success, bytes memory data )
            = proxy.call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        bytes memory returnData;

        if (success) {
            // Decode the ABI-encoding of the approve call bytes return data first.
            returnData = abi.decode(data, (bytes));

            // Approve was successful if 1) no return value or 2) true return value.
            if (
                returnData.length == 0 ||
                (returnData.length == 32 && abi.decode(returnData, (bool)))
            ) return;
        }

        // If call was unsuccessful, set to zero and try again.
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, 0)));

        returnData = IALMProxy(proxy).doCall(token, approveData);

        // Revert if approve returns false.
        require(
            returnData.length == 0 || (returnData.length == 32 && abi.decode(returnData, (bool))),
            "ApproveLib/approve-failed"
        );
    }

}
