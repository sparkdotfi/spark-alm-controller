// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

import { ApproveLib } from "./ApproveLib.sol";


interface IEthenaMinterLike {

    function setDelegatedSigner(address delegateSigner) external;

    function removeDelegatedSigner(address delegateSigner) external;

}

interface ISUSDELike {

    function cooldownAssets(uint256 usdeAmount) external returns (uint256);

    function cooldownShares(uint256 susdeAmount) external returns (uint256);

    function unstake(address receiver) external;

}

library USDELib {

    bytes32 public constant LIMIT_USDE_BURN      = keccak256("LIMIT_USDE_BURN");
    bytes32 public constant LIMIT_USDE_MINT      = keccak256("LIMIT_USDE_MINT");
    bytes32 public constant LIMIT_SUSDE_COOLDOWN = keccak256("LIMIT_SUSDE_COOLDOWN");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address proxy, address ethenaMinter, address delegatedSigner)
        external
    {
        IALMProxy(proxy).doCall(
            ethenaMinter,
            abi.encodeCall(IEthenaMinterLike.setDelegatedSigner, (delegatedSigner))
        );
    }

    function removeDelegatedSigner(address proxy, address ethenaMinter, address delegatedSigner)
        external
    {
        IALMProxy(proxy).doCall(
            ethenaMinter,
            abi.encodeCall(IEthenaMinterLike.removeDelegatedSigner, (delegatedSigner))
        );
    }

    function prepareUSDEMint(
        address proxy,
        address rateLimits,
        address usdc,
        address minter,
        uint256 usdcAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_USDE_MINT, usdcAmount);

        ApproveLib.approve(usdc, proxy, minter, usdcAmount);
    }

    function prepareUSDEBurn(
        address proxy,
        address rateLimits,
        address usde,
        address minter,
        uint256 usdeAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_USDE_BURN, usdeAmount);

        ApproveLib.approve(usde, proxy, minter, usdeAmount);
    }

    function cooldownAssetsSUSDE(
        address proxy,
        address rateLimits,
        address susde,
        uint256 usdeAmount
    )
        external
        returns (uint256 cooldownShares)
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_SUSDE_COOLDOWN, usdeAmount);

        return abi.decode(
            IALMProxy(proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );
    }

    // NOTE: Rate limited at end of function
    function cooldownSharesSUSDE(
        address proxy,
        address rateLimits,
        address susde,
        uint256 susdeAmount
    )
        external
        returns (uint256 cooldownAssets)
    {
        cooldownAssets = abi.decode(
            IALMProxy(proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_SUSDE_COOLDOWN, cooldownAssets);
    }

    function unstakeSUSDE(address proxy, address susde) external {
        IALMProxy(proxy).doCall(susde, abi.encodeCall(ISUSDELike.unstake, (proxy)));
    }

}
