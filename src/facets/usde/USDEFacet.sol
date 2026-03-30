// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IUSDEFacet } from "./IUSDEFacet.sol";

interface IEthenaMinterLike {

    function setDelegatedSigner(address delegateSigner) external;

    function removeDelegatedSigner(address delegateSigner) external;

}

interface ISUSDELike {

    function cooldownAssets(uint256 usdeAmount) external returns (uint256);

    function cooldownShares(uint256 susdeAmount) external returns (uint256);

    function unstake(address receiver) external;

}

contract USDEFacet is IUSDEFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant LIMIT_USDE_BURN      = keccak256("LIMIT_USDE_BURN");
    bytes32 public constant LIMIT_USDE_MINT      = keccak256("LIMIT_USDE_MINT");
    bytes32 public constant LIMIT_SUSDE_COOLDOWN = keccak256("LIMIT_SUSDE_COOLDOWN");

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable ethenaMinter;
    address public immutable susde;
    address public immutable usdc;
    address public immutable usde;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address ethenaMinter_, address susde_, address usdc_, address usde_) {
        ethenaMinter = ethenaMinter_;
        susde        = susde_;
        usdc         = usdc_;
        usde         = usde_;
    }

    /**********************************************************************************************/
    /*** External Interactive functions                                                         ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address delegatedSigner)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            ethenaMinter,
            abi.encodeCall(IEthenaMinterLike.setDelegatedSigner, (delegatedSigner))
        );
    }

    function removeDelegatedSigner(address delegatedSigner)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            ethenaMinter,
            abi.encodeCall(IEthenaMinterLike.removeDelegatedSigner, (delegatedSigner))
        );
    }

    function prepareMint(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_USDE_MINT, usdcAmount);

        ApproveLib.approve(usdc, $.proxy, ethenaMinter, usdcAmount);
    }

    function prepareBurn(uint256 usdeAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_USDE_BURN, usdeAmount);

        ApproveLib.approve(usde, $.proxy, ethenaMinter, usdeAmount);
    }

    function cooldownAssets(uint256 usdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_SUSDE_COOLDOWN, usdeAmount);

        return abi.decode(
            IALMProxy($.proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );
    }

    function cooldownShares(uint256 susdeAmount)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assets)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        // NOTE: Rate limited at end of function, so cannot return here.
        assets = abi.decode(
            IALMProxy($.proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_SUSDE_COOLDOWN, assets);
    }

    function unstakeSUSDE() external nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(susde, abi.encodeCall(ISUSDELike.unstake, (proxy)));
    }

}
