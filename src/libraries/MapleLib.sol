// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC4626 } from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { makeAddressKey } from "../RateLimitHelpers.sol";

interface IMapleTokenLike is IERC4626 {

    function requestRedeem(uint256 shares, address receiver) external;

    function removeShares(uint256 shares, address receiver) external;

}

library MapleLib {

    bytes32 public constant LIMIT_REDEEM = keccak256("LIMIT_MAPLE_REDEEM");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function requestRedemption(
        address proxy,
        address rateLimits,
        address mapleToken,
        uint256 shares
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(
            makeAddressKey(LIMIT_REDEEM, mapleToken),
            IMapleTokenLike(mapleToken).convertToAssets(shares)
        );

        IALMProxy(proxy).doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike.requestRedeem, (shares, proxy))
        );
    }

    function cancelRedemption(
        address proxy,
        address rateLimits,
        address mapleToken,
        uint256 shares
    )
        external
    {
        require(
            IRateLimits(rateLimits).getRateLimitData(
                makeAddressKey(LIMIT_REDEEM, mapleToken)
            ).maxAmount > 0,
            "MapleLib/invalid-action"
        );

        IALMProxy(proxy).doCall(
            mapleToken,
            abi.encodeCall(IMapleTokenLike.removeShares, (shares, proxy))
        );
    }

}
