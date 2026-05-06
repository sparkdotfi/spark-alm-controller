// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  IEthenaFacet
 * @notice PAU facet for interacting with Ethena's USDe ecosystem. Supports minting/burning USDe via
 *         the Ethena minter, staking/unstaking sUSDe, and managing the sUSDe cooldown process.
 */
interface IEthenaFacet is IFacet {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a USDe cooldown is initiated by asset amount.
     * @param  usdeAmount Amount of USDe queued for cooldown.
     * @param  shares     Amount of sUSDe shares locked.
     */
    event EthenaCooldownAssets(uint256 usdeAmount, uint256 shares);

    /**
     * @notice Emitted when a USDe cooldown is initiated by share amount.
     * @param  susdeAmount Amount of sUSDe shares queued for cooldown.
     * @param  assets      Amount of USDe assets that will be received.
     */
    event EthenaCooldownShares(uint256 susdeAmount, uint256 assets);

    /**
     * @notice Emitted when a USDe burn is prepared by approving USDe to the Ethena minter.
     * @param  usdeAmount Amount of USDe approved for burning.
     */
    event EthenaPrepareBurn(uint256 usdeAmount);

    /**
     * @notice Emitted when a USDe mint is prepared by approving USDC to the Ethena minter.
     * @param  usdcAmount Amount of USDC approved for minting (6-decimal precision).
     */
    event EthenaPrepareMint(uint256 usdcAmount);

    /**
     * @notice Emitted when a delegated signer is removed from the Ethena minter.
     * @param  delegatedSigner Address of the removed delegated signer.
     */
    event EthenaRemoveDelegatedSigner(address indexed delegatedSigner);

    /**
     * @notice Emitted when a delegated signer is set on the Ethena minter.
     * @param  delegatedSigner Address of the delegated signer.
     */
    event EthenaSetDelegatedSigner(address indexed delegatedSigner);

    /**
     * @notice Emitted when sUSDe is unstaked after the cooldown period.
     * @param  assets Amount of USDe assets received from unstaking.
     */
    event EthenaUnstake(uint256 assets);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Initiates sUSDe cooldown by specifying a USDe asset amount.
     * @param  usdeAmount Amount of USDe to cooldown.
     * @return shares     Amount of sUSDe shares locked in cooldown.
     */
    function cooldownAssets(uint256 usdeAmount) external returns (uint256 shares);

    /**
     * @notice Initiates sUSDe cooldown by specifying a share amount.
     * @param  susdeAmount Amount of sUSDe shares to cooldown.
     * @return assets      Amount of USDe assets queued for withdrawal.
     */
    function cooldownShares(uint256 susdeAmount) external returns (uint256 assets);

    /**
     * @notice Prepares a USDe burn by approving USDe to the Ethena minter. The actual burn is
     *         executed off-chain by the delegated signer.
     * @param  usdeAmount Amount of USDe to approve for burning.
     */
    function prepareBurn(uint256 usdeAmount) external;

    /**
     * @notice Prepares a USDe mint by approving USDC to the Ethena minter. The actual mint is
     *         executed off-chain by the delegated signer.
     * @param  usdcAmount Amount of USDC to approve for minting (6-decimal precision).
     */
    function prepareMint(uint256 usdcAmount) external;

    /**
     * @notice Removes a delegated signer from the Ethena minter for the proxy.
     * @param  delegatedSigner Address of the delegated signer to remove.
     */
    function removeDelegatedSigner(address delegatedSigner) external;

    /**
     * @notice Sets a delegated signer on the Ethena minter for the proxy.
     * @param  delegatedSigner Address of the delegated signer to set.
     */
    function setDelegatedSigner(address delegatedSigner) external;

    /// @notice Unstakes sUSDe after the cooldown period, receiving USDe.
    function unstake() external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice The derived rate limit key for USDe burn operations.
    function burnRateLimitKey() external pure returns (bytes32 key);

    /// @notice The derived rate limit key for sUSDe cooldown operations.
    function cooldownRateLimitKey() external pure returns (bytes32 key);

    /// @notice Address of the Ethena minter contract (immutable).
    function minter() external view returns (address);

    /// @notice The derived rate limit key for USDe mint operations.
    function mintRateLimitKey() external pure returns (bytes32 key);

    /// @notice The derived rate limit key for remove delegated signer operations.
    function removeDelegatedSignerRateLimitKey() external pure returns (bytes32 key);

    /// @notice The derived rate limit key for set delegated signer operations.
    function setDelegatedSignerRateLimitKey() external pure returns (bytes32 key);

    /// @notice Address of the sUSDe (staked USDe) token contract (immutable).
    function susde() external view returns (address);

    /// @notice The derived rate limit key for unstake operations.
    function unstakeRateLimitKey() external pure returns (bytes32 key);

    /// @notice Address of the USDC token contract (immutable).
    function usdc() external view returns (address);

    /// @notice Address of the USDe token contract (immutable).
    function usde() external view returns (address);

}
