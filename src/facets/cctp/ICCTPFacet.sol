// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  ICCTPFacet
 * @notice PAU facet for cross-chain USDC transfers via Circle's CCTP V2. Burns USDC on the source
 *         chain and mints on the destination. Large transfers are automatically split to respect
 *         per-message burn limits.
 */
interface ICCTPFacet is IFacet {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct DomainParameters {
        bytes32 mintRecipient;
        uint32  minFeeCapRate;
        uint32  maxFeeCapRate;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when a mint recipient is configured for a destination domain.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  mintRecipient     Bytes32-encoded address that receives minted USDC.
     * @param  minFeeCapRate     Minimum fee cap rate (in basis points) for the destination domain.
     * @param  maxFeeCapRate     Maximum fee cap rate (in basis points) for the destination domain.
     */
    event CCTPDomainParametersSet(
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint32          minFeeCapRate,
        uint32          maxFeeCapRate
    );

    /**
     * @notice Emitted per depositForBurn call for off-chain attestation tracking.
     * @dev    Used to track individual transfers for off-chain processing of CCTP transactions.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  mintRecipient     Bytes32-encoded recipient on the target chain.
     * @param  amount            Amount of USDC burned in this transfer chunk.
     * @param  maxFee            Maximum fee for the transfer (USDC precision, 6 decimals).
     */
    event CCTPTransferInitiated(
        uint32  indexed destinationDomain,
        bytes32 indexed mintRecipient,
        uint256         amount,
        uint256         maxFee
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Configures the mint recipient for a CCTP destination domain.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  recipient         Bytes32-encoded address to receive minted USDC.
     * @param  minFeeCapRate     Minimum fee cap rate (in basis points) for the destination domain.
     * @param  maxFeeCapRate     Maximum fee cap rate (in basis points) for the destination domain.
     */
    function setDomainParameters(
        uint32  destinationDomain,
        bytes32 recipient,
        uint32  minFeeCapRate,
        uint32  maxFeeCapRate
    ) external;

    /**
     * @notice Transfers USDC to a destination chain with a max fee for fast burns.
     * @param  amount            Amount of USDC to transfer (6-decimal precision).
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @param  feeCapRate        Fee cap rate (in basis points) for the transfer(s).
     *                           Fee cap rate should be zero until CCTP introduces fees.
     */
    function transfer(uint256 amount, uint32 destinationDomain, uint64 feeCapRate) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Always bytes32(0): any address can complete the message on the destination chain.
    function DESTINATION_CALLER() external pure returns (bytes32);

    /**
     * @notice Finality threshold for CCTP depositForBurn. Value 2000 corresponds to standard
     *         (finalized) messages in CCTP V2.
     */
    function MAX_FINALITY_THRESHOLD() external pure returns (uint32);

    /// @notice Address of the CCTP TokenMessenger contract (immutable).
    function cctp() external view returns (address);

    /// @notice The derived rate limit key for aggregate CCTP volume across all domains.
    function toCCTPRateLimitKey() external pure returns (bytes32 key);

    /// @notice Address of the USDC token contract (immutable).
    function usdc() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the derived per-domain rate limit key for CCTP transfers.
     * @param  destinationDomain CCTP domain identifier for the target chain.
     * @return key               Derived rate limit key.
     */
    function getToDomainRateLimitKey(uint32 destinationDomain) external pure returns (bytes32 key);

    /**
     * @notice Returns the configured mint recipient for a destination domain.
     * @param  destinationDomain CCTP domain identifier.
     * @return mintRecipient     Bytes32-encoded recipient. Zero if not set.
     * @return minFeeCapRate     Minimum fee cap rate (in basis points) for the destination domain.
     * @return maxFeeCapRate     Maximum fee cap rate (in basis points) for the destination domain.
     */
    function getDomainParameters(uint32 destinationDomain)
        external
        view
        returns (bytes32 mintRecipient, uint32 minFeeCapRate, uint32 maxFeeCapRate);

}
