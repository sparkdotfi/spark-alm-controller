// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../interfaces/IALMProxy.sol";

library WrapProxyETHLib {

    function wrapAll(address proxy, address weth) external {
        uint256 proxyBalance = proxy.balance;

        if (proxyBalance == 0) return;

        IALMProxy(proxy).doCallWithValue(weth, "", proxyBalance);
    }

}
