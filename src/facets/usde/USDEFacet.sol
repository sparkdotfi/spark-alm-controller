// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IUSDEFacet } from "./IUSDEFacet.sol";

interface IERC20Like {

    function balanceOf(address account) external view returns (uint256);

}

interface IEthenaMinterLike {

    function setDelegatedSigner(address delegateSigner) external;

    function removeDelegatedSigner(address delegateSigner) external;

}

interface ISUSDELike {

    function cooldownAssets(uint256 usdeAmount) external returns (uint256);

    function cooldownShares(uint256 susdeAmount) external returns (uint256);

    function unstake(address receiver) external;

}

contract USDEFacet is IUSDEFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_BURN     = keccak256("LIMIT_USDE_BURN");
    bytes32 internal constant _LIMIT_COOLDOWN = keccak256("LIMIT_SUSDE_COOLDOWN");
    bytes32 internal constant _LIMIT_MINT     = keccak256("LIMIT_USDE_MINT");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUSDEFacet
    address public immutable override ethenaMinter;

    /// @inheritdoc IUSDEFacet
    address public immutable override susde;

    /// @inheritdoc IUSDEFacet
    address public immutable override usdc;

    /// @inheritdoc IUSDEFacet
    address public immutable override usde;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address ethenaMinter_, address susde_, address usdc_, address usde_) {
        require(ethenaMinter_ != address(0), "USDEFacet/zero-ethenaMinter");
        require(susde_        != address(0), "USDEFacet/zero-susde");
        require(usdc_         != address(0), "USDEFacet/zero-usdc");
        require(usde_         != address(0), "USDEFacet/zero-usde");

        ethenaMinter = ethenaMinter_;
        susde        = susde_;
        usdc         = usdc_;
        usde         = usde_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IUSDEFacet
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

        emit USDESetDelegatedSigner(delegatedSigner);
    }

    /// @inheritdoc IUSDEFacet
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

        emit USDERemoveDelegatedSigner(delegatedSigner);
    }

    /// @inheritdoc IUSDEFacet
    function prepareMint(uint256 usdcAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _decreaseRateLimit(mintRateLimitKey(), usdcAmount);

        ApproveLib.approve(usdc, _getSharedControllerStorage().proxy, ethenaMinter, usdcAmount);

        emit USDEPrepareMint(usdcAmount);
    }

    /// @inheritdoc IUSDEFacet
    function prepareBurn(uint256 usdeAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _decreaseRateLimit(burnRateLimitKey(), usdeAmount);

        ApproveLib.approve(usde, _getSharedControllerStorage().proxy, ethenaMinter, usdeAmount);

        emit USDEPrepareBurn(usdeAmount);
    }

    /// @inheritdoc IUSDEFacet
    function cooldownAssets(uint256 usdeAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(cooldownRateLimitKey(), usdeAmount);

        // NOTE: The SUSDE contract is immutable, so the return value can be trusted.
        shares = abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );

        emit USDECooldownAssets(usdeAmount, shares);
    }

    /// @inheritdoc IUSDEFacet
    function cooldownShares(uint256 susdeAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256 assets)
    {
        // NOTE: The SUSDE contract is immutable, so the return value can be trusted.
        assets = abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        _decreaseRateLimit(cooldownRateLimitKey(), assets);

        emit USDECooldownShares(susdeAmount, assets);
    }

    /// @inheritdoc IUSDEFacet
    function unstake() external override nonReentrant onlyRole(RELAYER_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingUSDE = IERC20Like(usde).balanceOf(proxy);

        IALMProxy(proxy).doCall(susde, abi.encodeCall(ISUSDELike.unstake, (proxy)));

        emit USDEUnstake(IERC20Like(usde).balanceOf(proxy) - startingUSDE);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUSDEFacet
    function burnRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_BURN;
    }

    /// @inheritdoc IUSDEFacet
    function cooldownRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_COOLDOWN;
    }

    /// @inheritdoc IUSDEFacet
    function mintRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_MINT;
    }

}
