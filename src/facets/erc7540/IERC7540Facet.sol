// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IERC7540Facet
 * @notice PAU facet for interacting with ERC-7540 asynchronous vaults. Supports the async
 *         request/claim lifecycle for both deposits and redemptions.
 */
interface IERC7540Facet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a fulfilled deposit request is claimed.
     * @param  token  Address of the ERC-7540 vault token.
     * @param  shares Amount of vault shares claimed.
     */
    event ERC7540ClaimDeposit(address indexed token, uint256 shares);

    /**
     * @notice Emitted when a fulfilled redeem request is claimed.
     * @param  token  Address of the ERC-7540 vault token.
     * @param  assets Amount of underlying assets claimed.
     */
    event ERC7540ClaimRedeem(address indexed token, uint256 assets);

    /**
     * @notice Emitted when a deposit request is submitted.
     * @param  token  Address of the ERC-7540 vault token.
     * @param  assets Amount of underlying assets submitted for deposit.
     */
    event ERC7540RequestDeposit(address indexed token, uint256 assets);

    /**
     * @notice Emitted when a redeem request is submitted.
     * @param  token  Address of the ERC-7540 vault token.
     * @param  shares Amount of vault shares submitted for redemption.
     */
    event ERC7540RequestRedeem(address indexed token, uint256 shares);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Claims shares from a fulfilled deposit request by minting the maximum claimable
     *         amount.
     * @param  token Address of the ERC-7540 vault token.
     */
    function claimDeposit(address token) external;

    /**
     * @notice Claims assets from a fulfilled redeem request by withdrawing the maximum claimable
     *         amount.
     * @param  token Address of the ERC-7540 vault token.
     */
    function claimRedeem(address token) external;

    /**
     * @notice Submits an async deposit request to the ERC-7540 vault.
     * @param  token  Address of the ERC-7540 vault token.
     * @param  amount Amount of underlying assets to request for deposit.
     */
    function requestDeposit(address token, uint256 amount) external;

    /**
     * @notice Submits an async redeem request to the ERC-7540 vault.
     * @param  token  Address of the ERC-7540 vault token.
     * @param  shares Amount of vault shares to request for redemption.
     */
    function requestRedeem(address token, uint256 shares) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /**
     * @notice Rate limit key for deposit operations, combined with the asset address and vault
     *         token address to form the per-market key.
     */
    function LIMIT_DEPOSIT() external pure returns (bytes32);

    /**
     * @notice Rate limit key for redeem operations, combined with the vault token address to form
     *         the per-vault keys.
     */
    function LIMIT_REDEEM() external pure returns (bytes32);

}
