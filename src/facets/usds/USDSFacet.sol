// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IUSDSFacet } from "./IUSDSFacet.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

}

interface IVaultLike {

    function buffer() external view returns (address);

    function draw(uint256 usdsAmount) external;

    function wipe(uint256 usdsAmount) external;

}

contract USDSFacet is IUSDSFacet, FacetBase {

    /**********************************************************************************************/
    /*** Facet Storage Domain                                                                   ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.USDSFacet.v1
    struct FacetStorage {
        address vault;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.USDSFacet.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant FACET_STORAGE_LOCATION =
        0xeb14dfb2e71bee4012142363a6b9a4ac529734e72a5b7fc8a9e74774349daf00;

    function _getFacetStorage() internal pure returns (FacetStorage storage $) {
        assembly {
            $.slot := FACET_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_MINT = keccak256("LIMIT_USDS_MINT");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override usds;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address usds_) {
        require(usds_ != address(0), "USDSFacet/zero-usds");

        usds = usds_;
    }

    /**********************************************************************************************/
    /*** External Interactive Admin Functions                                                   ***/
    /**********************************************************************************************/

    function setVault(address vault_) external override nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(vault_ != address(0), "USDSFacet/zero-vault");

        emit USDSVaultSet(_getFacetStorage().vault = vault_);
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function mint(uint256 usdsAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_MINT, usdsAmount);

        address proxy  = $.proxy;
        address vault_ = _getFacetStorage().vault;

        // Mint USDS into the buffer.
        IALMProxy(proxy).doCall(vault_, abi.encodeCall(IVaultLike.draw, (usdsAmount)));

        // Transfer USDS from the buffer to the proxy.
        // No need for ApproveLib as we are transferring USDS with an expected transfer function.
        IALMProxy(proxy).doCall(
            usds,
            abi.encodeCall(
                IERC20Like.transferFrom,
                (IVaultLike(vault_).buffer(), proxy, usdsAmount)
            )
        );

        emit USDSMint(usdsAmount);
    }

    function burn(uint256 usdsAmount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitIncrease(LIMIT_MINT, usdsAmount);

        address proxy  = $.proxy;
        address vault_ = _getFacetStorage().vault;

        // Transfer USDS from the proxy to the buffer.
        // No need for ApproveLib as we are transferring USDS with an expected transfer function.
        IALMProxy(proxy).doCall(
            usds,
            abi.encodeCall(IERC20Like.transfer, (IVaultLike(vault_).buffer(), usdsAmount))
        );

        // Burn USDS from the buffer.
        IALMProxy(proxy).doCall(vault_, abi.encodeCall(IVaultLike.wipe, (usdsAmount)));

        emit USDSBurn(usdsAmount);
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IUSDSFacet
    function vault() external view override returns (address) {
        return _getFacetStorage().vault;
    }

}
