// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

library RateLimitLib {

    /**********************************************************************************************/
    /*** Errors                                                                                 ***/
    /**********************************************************************************************/

    error RateLimitLib_InvalidLastAmount(uint256 lastAmount, uint256 maxAmount);

    error RateLimitLib_InvalidLastUpdated(uint256 lastUpdated, uint256 blockTimestamp);

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    /**
     * @dev   Struct representing a rate limit.
     *        The current rate limit is calculated using the formula:
     *        `currentRateLimit_ = min(slope * (block.timestamp - lastUpdated) + lastAmount, maxAmount)`.
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
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function decrease(RateLimitData storage rateLimitData_, uint256 amount_) internal returns (bool success_) {
        uint256 maxAmount_ = rateLimitData_.maxAmount;

        if (maxAmount_ == type(uint256).max) return true;  // Special case unlimited

        uint256 currentRateLimit_ = getCurrentRateLimit(rateLimitData_);

        if (amount_ > currentRateLimit_) return false;

        rateLimitData_.lastAmount = currentRateLimit_ - amount_;
        rateLimitData_.lastUpdated = block.timestamp;

        return true;
    }

    function increase(RateLimitData storage rateLimitData_, uint256 amount_) internal {
        uint256 maxAmount_ = rateLimitData_.maxAmount;

        if (maxAmount_ == type(uint256).max) return;  // Special case unlimited

        uint256 currentRateLimit_ = getCurrentRateLimit(rateLimitData_);

        rateLimitData_.lastAmount = min(currentRateLimit_ + amount_, maxAmount_);
        rateLimitData_.lastUpdated = block.timestamp;
    }

    function set(
        RateLimitData storage rateLimitData_,
        uint256 maxAmount_,
        uint256 slope_,
        uint256 lastAmount_,
        uint256 lastUpdated_
    ) internal {
        if (lastAmount_ > maxAmount_) revert RateLimitLib_InvalidLastAmount(lastAmount_, maxAmount_);
        if (lastUpdated_ > block.timestamp) revert RateLimitLib_InvalidLastUpdated(lastUpdated_, block.timestamp);

        rateLimitData_.maxAmount   = maxAmount_;
        rateLimitData_.slope       = slope_;
        rateLimitData_.lastAmount  = lastAmount_;
        rateLimitData_.lastUpdated = lastUpdated_;
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getCurrentRateLimit(RateLimitData storage rateLimitData_) internal view returns (uint256 rateLimit_) {
        return min(
            rateLimitData_.slope * (block.timestamp - rateLimitData_.lastUpdated) + rateLimitData_.lastAmount,
            rateLimitData_.maxAmount
        );
    }

    function min(uint256 a_, uint256 b_) internal pure returns (uint256 min_) {
        return a_ < b_ ? a_ : b_;
    }

}
