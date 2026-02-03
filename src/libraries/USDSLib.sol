// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

}

interface IVaultLike {

    function buffer() external view returns (address);

    function draw(uint256 usdsAmount) external;

    function wipe(uint256 usdsAmount) external;

}

library USDSLib {

    bytes32 public constant LIMIT_MINT = keccak256("LIMIT_USDS_MINT");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function mint(
        address proxy,
        address rateLimits,
        address vault,
        address usds,
        uint256 usdsAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_MINT, usdsAmount);

        // Mint USDS into the buffer.
        IALMProxy(proxy).doCall(vault, abi.encodeCall(IVaultLike.draw, (usdsAmount)));

        // Transfer USDS from the buffer to the proxy.
        // Not need for ApprobeLib as we are transferring USDS with an expected transfer function.
        IALMProxy(proxy).doCall(
            usds,
            abi.encodeCall(
                IERC20Like.transferFrom,
                (IVaultLike(vault).buffer(), proxy, usdsAmount)
            )
        );
    }

    function burn(
        address proxy,
        address rateLimits,
        address vault,
        address usds,
        uint256 usdsAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitIncrease(LIMIT_MINT, usdsAmount);

        // Transfer USDS from the proxy to the buffer.
        // Not need for ApprobeLib as we are transferring USDS with an expected transfer function.
        IALMProxy(proxy).doCall(
            usds,
            abi.encodeCall(IERC20Like.transfer, (IVaultLike(vault).buffer(), usdsAmount))
        );

        // Burn USDS from the buffer.
        IALMProxy(proxy).doCall(vault, abi.encodeCall(IVaultLike.wipe, (usdsAmount)));
    }

}
