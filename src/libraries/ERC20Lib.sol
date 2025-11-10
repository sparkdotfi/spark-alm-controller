// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { IALMProxy } from "../interfaces/IALMProxy.sol";

library ERC20Lib {
    
    // NOTE: This logic was inspired by OpenZeppelin's forceApprove in SafeERC20 library
    function approve(
        IALMProxy proxy,
        address   token,
        address   spender,
        uint256   amount
    )
        external
    {
        bytes memory approveData = abi.encodeCall(IERC20.approve, (spender, amount));

        // Call doCall on proxy to approve the token
        ( bool success, bytes memory data )
            = address(proxy).call(abi.encodeCall(IALMProxy.doCall, (token, approveData)));

        bytes memory approveCallReturnData;

        if (success) {
            // Data is the ABI-encoding of the approve call bytes return data, need to
            // decode it first
            approveCallReturnData = abi.decode(data, (bytes));
            // Approve was successful if 1) no return value or 2) true return value
            if (approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool))) {
                return;
            }
        }

        // If call was unsuccessful, set to zero and try again
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, 0)));

        approveCallReturnData = proxy.doCall(token, approveData);

        // Revert if approve returns false
        require(
            approveCallReturnData.length == 0 || abi.decode(approveCallReturnData, (bool)),
            "ERC20Lib/approve-failed"
        );
    }

    function transfer(
        IALMProxy proxy,
        address   token,
        address   to,
        uint256   amount
    ) external {
        bytes memory returnData = proxy.doCall(
            token,
            abi.encodeCall(IERC20(token).transfer, (to, amount))
        );

        require(
            returnData.length == 0 || abi.decode(returnData, (bool)),
            "ERC20Lib/transfer-failed"
        );
    }
}
