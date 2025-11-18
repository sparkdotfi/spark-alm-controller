// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }             from "../interfaces/IALMProxy.sol";
import { IMerklDistributorLike } from "../interfaces/MerklInterfaces.sol";

library MerklLib {

    struct MerklToggleOperatorParams {
        IALMProxy proxy;
        address   distributor;
        address   operator;
    }

    function toggleOperator(MerklToggleOperatorParams memory params) external {
        params.proxy.doCall(
            params.distributor,
            abi.encodeCall(IMerklDistributorLike.toggleOperator, (address(params.proxy), params.operator))
        );
    }

}
