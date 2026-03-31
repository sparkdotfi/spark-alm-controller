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

    bytes32 public constant override LIMIT_USDE_BURN      = keccak256("LIMIT_USDE_BURN");
    bytes32 public constant override LIMIT_USDE_MINT      = keccak256("LIMIT_USDE_MINT");
    bytes32 public constant override LIMIT_SUSDE_COOLDOWN = keccak256("LIMIT_SUSDE_COOLDOWN");

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override ethenaMinter;
    address public immutable override susde;
    address public immutable override usdc;
    address public immutable override usde;

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
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function setDelegatedSigner(address delegatedSigner)
        external
        override
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
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            ethenaMinter,
            abi.encodeCall(IEthenaMinterLike.removeDelegatedSigner, (delegatedSigner))
        );
    }

    function prepareMint(uint256 usdcAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _decreaseRateLimit(LIMIT_USDE_MINT, usdcAmount);

        ApproveLib.approve(usdc, _getSharedControllerStorage().proxy, ethenaMinter, usdcAmount);
    }

    function prepareBurn(uint256 usdeAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _decreaseRateLimit(LIMIT_USDE_BURN, usdeAmount);

        ApproveLib.approve(usde, _getSharedControllerStorage().proxy, ethenaMinter, usdeAmount);
    }

    function cooldownAssets(uint256 usdeAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(LIMIT_SUSDE_COOLDOWN, usdeAmount);

        return abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );
    }

    function cooldownShares(uint256 susdeAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assets)
    {
        // NOTE: Rate limited at end of function, so cannot return here.
        assets = abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        _decreaseRateLimit(LIMIT_SUSDE_COOLDOWN, assets);
    }

    function unstakeSUSDE() external override nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(susde, abi.encodeCall(ISUSDELike.unstake, (proxy)));
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
