// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    IAccessControl
} from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

interface IRateLimits is IAccessControl {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @dev   Struct representing a rate limit.
     *        The current rate limit is calculated using the formula:
     *        `currentRateLimit = min(slope * (block.timestamp - lastUpdated) + lastAmount, maxAmount)`.
     * @param maxAmount   Maximum allowed amount at any time.
     * @param slope       The slope of the rate limit, used to calculate the new
     *                    limit based on time passed. [tokens / second]
     * @param lastAmount  The amount left available at the last update.
     * @param lastUpdated The timestamp when the rate limit was last updated.
     */
    struct RateLimitData {
        uint256 maxAmount;
        uint256 slope;
        uint256 lastAmount;
        uint256 lastUpdated;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    /**
     * @dev   Emitted when the rate limit data is set.
     * @param key         The identifier for the rate limit.
     * @param maxAmount   The maximum allowed amount for the rate limit.
     * @param slope       The slope value used in the rate limit calculation.
     * @param lastAmount  The amount left available at the last update.
     * @param lastUpdated The timestamp when the rate limit was last updated.
     */
    event RateLimitDataSet(
        bytes32 indexed key,
        uint256         maxAmount,
        uint256         slope,
        uint256         lastAmount,
        uint256         lastUpdated
    );

    /**
     * @dev   Emitted when a rate limit decrease is triggered.
     * @param key              The identifier for the rate limit.
     * @param amountToDecrease The amount to decrease from the current rate limit.
     * @param oldRateLimit     The previous rate limit value before triggering.
     * @param newRateLimit     The new rate limit value after triggering.
     */
    event RateLimitDecreaseTriggered(
        bytes32 indexed key,
        uint256         amountToDecrease,
        uint256         oldRateLimit,
        uint256         newRateLimit
    );

    /**
     * @dev   Emitted when a rate limit increase is triggered.
     * @param key              The identifier for the rate limit.
     * @param amountToIncrease The amount to increase from the current rate limit.
     * @param oldRateLimit     The previous rate limit value before triggering.
     * @param newRateLimit     The new rate limit value after triggering.
     */
    event RateLimitIncreaseTriggered(
        bytes32 indexed key,
        uint256         amountToIncrease,
        uint256         oldRateLimit,
        uint256         newRateLimit
    );

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    /**
     * @dev    Returns the controller identifier as a bytes32 value.
     * @return The controller identifier.
     */
    function CONTROLLER() external view returns (bytes32);

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    /**
     * @dev   Sets rate limit data for a specific key.
     * @param key         The identifier for the rate limit.
     * @param maxAmount   The maximum allowed amount for the rate limit.
     * @param slope       The slope value used in the rate limit calculation.
     * @param lastAmount  The amount left available at the last update.
     * @param lastUpdated The timestamp when the rate limit was last updated.
     */
    function setRateLimitData(
        bytes32 key,
        uint256 maxAmount,
        uint256 slope,
        uint256 lastAmount,
        uint256 lastUpdated
    ) external;

    /**
     * @dev   Sets rate limit data for a specific key with
     *        `lastAmount == maxAmount` and `lastUpdated == block.timestamp`.
     * @param key       The identifier for the rate limit.
     * @param maxAmount The maximum allowed amount for the rate limit.
     * @param slope     The slope value used in the rate limit calculation.
     */
    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    /**
     * @dev   Sets an unlimited rate limit.
     * @param key The identifier for the rate limit.
     */
    function setUnlimitedRateLimitData(bytes32 key) external;

    /**********************************************************************************************/
    /*** Getter Functions                                                                       ***/
    /**********************************************************************************************/

    /**
     * @dev    Retrieves the RateLimitData struct associated with a specific key.
     * @param  key The identifier for the rate limit.
     * @return The data associated with the rate limit.
     */
    function getRateLimitData(bytes32 key) external view returns (RateLimitData memory);

    /**
     * @dev    Retrieves the current rate limit for a specific key.
     * @param  key The identifier for the rate limit.
     * @return The current rate limit value for the given key.
     */
    function getCurrentRateLimit(bytes32 key) external view returns (uint256);

    /**********************************************************************************************/
    /*** Controller functions                                                                   ***/
    /**********************************************************************************************/

    /**
     * @dev    Triggers the rate limit for a specific key and reduces the available
     *         amount by the provided value.
     * @param  key              The identifier for the rate limit.
     * @param  amountToDecrease The amount to decrease from the current rate limit.
     * @return newLimit         The updated rate limit after the deduction.
     */
    function triggerRateLimitDecrease(bytes32 key, uint256 amountToDecrease)
        external
        returns (uint256 newLimit);

    /**
     * @dev    Increases the rate limit for a given key up to the maxAmount. Does not revert if
     *         the new rate limit exceeds the maxAmount.
     * @param  key              The identifier for the rate limit.
     * @param  amountToIncrease The amount to increase from the current rate limit.
     * @return newLimit         The updated rate limit after the addition.
     */
    function triggerRateLimitIncrease(bytes32 key, uint256 amountToIncrease)
        external
        returns (uint256 newLimit);

}
