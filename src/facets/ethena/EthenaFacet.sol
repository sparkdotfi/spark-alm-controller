// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { ApproveLib } from "../../libraries/ApproveLib.sol";

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IEthenaFacet } from "./IEthenaFacet.sol";

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

contract EthenaFacet is IEthenaFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_SET_DELEGATED_SIGNER
        = keccak256("LIMIT_ETHENA_SET_DELEGATED_SIGNER");

    bytes32 internal constant _LIMIT_REMOVE_DELEGATED_SIGNER
        = keccak256("LIMIT_ETHENA_REMOVE_DELEGATED_SIGNER");

    bytes32 internal constant _LIMIT_MINT     = keccak256("LIMIT_ETHENA_MINT");
    bytes32 internal constant _LIMIT_BURN     = keccak256("LIMIT_ETHENA_BURN");
    bytes32 internal constant _LIMIT_COOLDOWN = keccak256("LIMIT_ETHENA_COOLDOWN");
    bytes32 internal constant _LIMIT_UNSTAKE  = keccak256("LIMIT_ETHENA_UNSTAKE");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IEthenaFacet
    address public immutable override minter;

    /// @inheritdoc IEthenaFacet
    address public immutable override susde;

    /// @inheritdoc IEthenaFacet
    address public immutable override usdc;

    /// @inheritdoc IEthenaFacet
    address public immutable override usde;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address minter_, address susde_, address usdc_, address usde_) {
        require(minter_ != address(0), "EthenaFacet/zero-minter");
        require(susde_  != address(0), "EthenaFacet/zero-susde");
        require(usdc_   != address(0), "EthenaFacet/zero-usdc");
        require(usde_   != address(0), "EthenaFacet/zero-usde");

        minter = minter_;
        susde  = susde_;
        usdc   = usdc_;
        usde   = usde_;
    }

    /**********************************************************************************************/
    /*** External Interactive Allocator Functions                                               ***/
    /**********************************************************************************************/

    /// @inheritdoc IEthenaFacet
    function setDelegatedSigner(address delegatedSigner)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(_rateLimitExists(setDelegatedSignerRateLimitKey()), "EthenaFacet/invalid-action");

        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            minter,
            abi.encodeCall(IEthenaMinterLike.setDelegatedSigner, (delegatedSigner))
        );

        emit EthenaSetDelegatedSigner(delegatedSigner);
    }

    /// @inheritdoc IEthenaFacet
    function removeDelegatedSigner(address delegatedSigner)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        require(
            _rateLimitExists(removeDelegatedSignerRateLimitKey()),
            "EthenaFacet/invalid-action"
        );

        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            minter,
            abi.encodeCall(IEthenaMinterLike.removeDelegatedSigner, (delegatedSigner))
        );

        emit EthenaRemoveDelegatedSigner(delegatedSigner);
    }

    /// @inheritdoc IEthenaFacet
    function prepareMint(uint256 usdcAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _decreaseRateLimit(mintRateLimitKey(), usdcAmount);

        ApproveLib.approve(usdc, _getSharedControllerStorage().proxy, minter, usdcAmount);

        emit EthenaPrepareMint(usdcAmount);
    }

    /// @inheritdoc IEthenaFacet
    function prepareBurn(uint256 usdeAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
    {
        _decreaseRateLimit(burnRateLimitKey(), usdeAmount);

        ApproveLib.approve(usde, _getSharedControllerStorage().proxy, minter, usdeAmount);

        emit EthenaPrepareBurn(usdeAmount);
    }

    /// @inheritdoc IEthenaFacet
    function cooldownAssets(uint256 usdeAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 shares)
    {
        _decreaseRateLimit(cooldownRateLimitKey(), usdeAmount);

        // NOTE: The SUSDE contract is immutable, so the return value can be trusted, but also the
        //       shares are siloed which is still a process that must be trusted anyway.
        shares = abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownAssets, (usdeAmount))
            ),
            (uint256)
        );

        emit EthenaCooldownAssets(usdeAmount, shares);
    }

    /// @inheritdoc IEthenaFacet
    function cooldownShares(uint256 susdeAmount)
        external
        override
        nonReentrant
        onlyRole(ALLOCATOR_ROLE)
        returns (uint256 assets)
    {
        // NOTE: The SUSDE contract is immutable, so the return value can be trusted, but also the
        //       assets are siloed which is still a process that must be trusted anyway.
        assets = abi.decode(
            IALMProxy(_getSharedControllerStorage().proxy).doCall(
                susde,
                abi.encodeCall(ISUSDELike.cooldownShares, (susdeAmount))
            ),
            (uint256)
        );

        _decreaseRateLimit(cooldownRateLimitKey(), assets);

        emit EthenaCooldownShares(susdeAmount, assets);
    }

    /// @inheritdoc IEthenaFacet
    function unstake() external override nonReentrant onlyRole(ALLOCATOR_ROLE) {
        address proxy = _getSharedControllerStorage().proxy;

        uint256 startingUSDE = IERC20Like(usde).balanceOf(proxy);

        require(_rateLimitExists(unstakeRateLimitKey()), "EthenaFacet/invalid-action");

        IALMProxy(proxy).doCall(susde, abi.encodeCall(ISUSDELike.unstake, (proxy)));

        emit EthenaUnstake(IERC20Like(usde).balanceOf(proxy) - startingUSDE);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IEthenaFacet
    function setDelegatedSignerRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_SET_DELEGATED_SIGNER;
    }

    /// @inheritdoc IEthenaFacet
    function removeDelegatedSignerRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_REMOVE_DELEGATED_SIGNER;
    }

    /// @inheritdoc IEthenaFacet
    function mintRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_MINT;
    }

    /// @inheritdoc IEthenaFacet
    function burnRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_BURN;
    }

    /// @inheritdoc IEthenaFacet
    function cooldownRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_COOLDOWN;
    }

    /// @inheritdoc IEthenaFacet
    function unstakeRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_UNSTAKE;
    }

}
