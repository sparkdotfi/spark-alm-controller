// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy } from "../interfaces/IALMProxy.sol";

interface IMerklDistributorLike {

    function toggleOperator(address user, address operator) external;

}

library MerklLib {

    function toggleOperator(address proxy, address distributor, address operator) external {
        require(distributor != address(0), "MerklLib/merkl-distributor-not-set");

        IALMProxy(proxy).doCall(
            distributor,
            abi.encodeCall(IMerklDistributorLike.toggleOperator, (proxy, operator))
        );
    }

}
