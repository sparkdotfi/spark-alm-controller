// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacet } from "../IFacet.sol";

/**
 * @title  INFATHaloFacet
 * @notice PAU facet for the Halo (recipient) side of an NFAT facility. Issues NFT positions
 *         against prior subscriptions, accrues per-facility interest via a configurable annual
 *         growth rate, and exposes split repayment flows for principal and interest. Operational
 *         entry points are gated on ALLOCATOR_ROLE and rate-limited per (facility, recipient or
 *         gem) tuple.
 */
interface INFATHaloFacet is IFacet {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @notice Per-facility tunable parameters.
     * @param  maxAnnualGrowthRate Max annual growth rate (1e18-scaled APR; 1e18 == 100%/year) used
     *                             to drive interest accrual on issued positions.
     */
    struct Parameters {
        uint256 maxAnnualGrowthRate;
    }

    /**
     * @notice Per-facility checkpoint state used to compute the cumulative interest index.
     * @param  interestIndex Cumulative 1e18-scaled interest accrued per unit of principal as of
     *                       `lastUpdated`. Combine with elapsed time and the current annual
     *                       growth rate to derive the live index.
     * @param  lastUpdated   Timestamp of the last checkpoint. Zero means the facility has never
     *                       been configured via `setMaxAnnualGrowthRate`.
     */
    struct FacilityState {
        uint256 interestIndex;
        uint256 lastUpdated;
    }

    /**
     * @notice Per-NFAT bookkeeping recorded by this facet.
     * @param  issued                 Whether the NFAT position has been issued.
     * @param  outstandingPrincipal   Outstanding principal.
     * @param  maxOutstandingInterest Max outstanding interest.
     * @param  interestIndex          Facility-wide interest index recorded at the last checkpoint.
     */
    struct Position {
        bool    issued;
        uint256 outstandingPrincipal;
        uint256 maxOutstandingInterest;
        uint256 interestIndex;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @notice Emitted when the max annual growth rate (1e18-scaled APR) for a facility is updated.
     * @param  facility            Address of the NFAT facility.
     * @param  maxAnnualGrowthRate New max annual growth rate, 1e18 = 100% APR.
     */
    event NFATHaloMaxAnnualGrowthRateSet(address indexed facility, uint256 maxAnnualGrowthRate);

    /**
     * @notice Emitted when an NFAT NFT is issued via this facet.
     * @param  facility Address of the NFAT facility.
     * @param  to       Recipient of the minted NFT (becomes the NFAT owner).
     * @param  tokenId  Identifier of the freshly minted NFAT token.
     * @param  amount   Principal recorded for this token (gem-native decimals).
     */
    event NFATHaloIssue(
        address indexed facility,
        address indexed to,
        uint256 indexed tokenId,
        uint256         amount
    );

    /**
     * @notice Emitted when interest is repaid against an issued NFAT position.
     * @param  facility Address of the NFAT facility.
     * @param  tokenId  Identifier of the NFAT token being repaid against.
     * @param  amount   Interest amount repaid (gem-native decimals).
     */
    event NFATHaloRepayInterest(address indexed facility, uint256 indexed tokenId, uint256 amount);

    /**
     * @notice Emitted when principal is repaid against an issued NFAT position.
     * @param  facility Address of the NFAT facility.
     * @param  tokenId  Identifier of the NFAT token being repaid against.
     * @param  amount   Principal amount repaid (gem-native decimals).
     */
    event NFATHaloRepayPrincipal(address indexed facility, uint256 indexed tokenId, uint256 amount);

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Issues an NFAT NFT and records the recorded principal for `tokenId`. The facility
     *         transfers the gem from itself to its configured recipient — which MUST be the
     *         controller's ALMProxy, so the principal lands back in our custody. Both the
     *         recorded `principal` and the consumed (facility, to) issue rate limit are sized
     *         from the actual ALMProxy gem balance delta, not the requested `amount`.
     * @param  facility Address of the NFAT facility. Its `recipient()` must equal the ALMProxy.
     * @param  to       Address to receive the NFT.
     * @param  tokenId  Token id to mint.
     * @param  amount   Requested principal to pull from the facility's deposit accounting.
     */
    function issue(address facility, address to, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Repays interest against an issued NFAT position. Bounded by `maxOutstandingInterest` after
     *         checkpointing; consumes the (facility, gem) repay-interest rate limit.
     * @param  facility Address of the NFAT facility.
     * @param  tokenId  Identifier of the NFAT token being repaid against.
     * @param  amount   Interest amount to repay. Must be non-zero and <= currently-accrued interest.
     */
    function repayInterest(address facility, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Repays principal owed on an issued NFAT position. Bounded by remaining principal
     *         (`principal - principalRepaid`); consumes the (facility, gem) repay-principal
     *         rate limit.
     * @param  facility Address of the NFAT facility.
     * @param  tokenId  Identifier of the NFAT token being repaid against.
     * @param  amount   Principal amount to repay. Must be non-zero and <= remaining principal.
     */
    function repayPrincipal(address facility, uint256 tokenId, uint256 amount) external;

    /**
     * @notice Sets the annual growth rate (1e18-scaled APR) used for interest accrual on a
     *         facility. Checkpoints the facility before applying the new rate so accrued interest
     *         under the previous rate is preserved.
     * @param  facility            Address of the NFAT facility.
     * @param  maxAnnualGrowthRate New max annual growth rate, 1e18 = 100% APR.
     */
    function setMaxAnnualGrowthRate(address facility, uint256 maxAnnualGrowthRate) external;

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /**
     * @notice Returns the configured annual growth rate (1e18-scaled APR) for a facility.
     * @param  facility            Address of the NFAT facility.
     * @return maxAnnualGrowthRate Max annual growth rate, 1e18 = 100% APR. Zero if unset.
     */
    function getMaxAnnualGrowthRate(address facility)
        external
        view
        returns (uint256 maxAnnualGrowthRate);

    /**
     * @notice Returns the last facility-wide interest index checkpoint and time of the checkpoint.
     * @param  facility      Address of the NFAT facility.
     * @return interestIndex Last cumulative 1e18-scaled interest index checkpoint.
     * @return lastUpdated   Timestamp of the last checkpoint. Zero means the facility has never
     *                       been configured.
     */
    function getFacilityState(address facility)
        external
        view
        returns (uint256 interestIndex, uint256 lastUpdated);

    /**
     * @notice Returns the derived issue rate limit key for an NFAT facility and NFT recipient.
     * @param  facility Address of the NFAT facility.
     * @param  to       Address that will receive issued NFAT NFTs under the configured budget.
     * @return key      Derived rate limit key.
     */
    function getIssueRateLimitKey(address facility, address to)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the outstanding principal, outstanding interest, and interest index for a
     *         given NFAT position.
     * @param  facility               Address of the NFAT facility.
     * @param  tokenId                Identifier of the NFAT token.
     * @return issued                 Whether the NFAT position has been issued.
     * @return outstandingPrincipal   Outstanding principal.
     * @return maxOutstandingInterest Last checkpointed max outstanding interest.
     * @return interestIndex          Last checkpointed facility-wide interest index.
     */
    function getPosition(address facility, uint256 tokenId)
        external
        view
        returns (
            bool    issued,
            uint256 outstandingPrincipal,
            uint256 maxOutstandingInterest,
            uint256 interestIndex
        );

    /**
     * @notice Returns the current outstanding interest for a given NFAT position.
     * @param  facility               Address of the NFAT facility.
     * @param  tokenId                Identifier of the NFAT token.
     * @return maxOutstandingInterest Current max outstanding interest.
     */
    function getCurrentMaxOutstandingInterest(address facility, uint256 tokenId)
        external
        view
        returns (uint256);

    /**
     * @notice Returns the derived repay-interest rate limit key for an NFAT facility and gem.
     * @dev    Keyed on (facility, gem) so a facility cannot change its gem under a configured
     *         rate limit; switching the gem invalidates the key.
     * @param  facility Address of the NFAT facility.
     * @param  gem      Address of the facility's gem token at configuration time.
     * @return key      Derived rate limit key.
     */
    function getRepayInterestRateLimitKey(address facility, address gem)
        external
        pure
        returns (bytes32 key);

    /**
     * @notice Returns the derived repay-principal rate limit key for an NFAT facility and gem.
     * @dev    Keyed on (facility, gem) so a facility cannot change its gem under a configured
     *         rate limit; switching the gem invalidates the key.
     * @param  facility Address of the NFAT facility.
     * @param  gem      Address of the facility's gem token at configuration time.
     * @return key      Derived rate limit key.
     */
    function getRepayPrincipalRateLimitKey(address facility, address gem)
        external
        pure
        returns (bytes32 key);

}
