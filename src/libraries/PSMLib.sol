// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { IRateLimits }  from "../interfaces/IRateLimits.sol";
import { IALMProxy }    from "../interfaces/IALMProxy.sol";

import { RateLimitHelpers } from "../RateLimitHelpers.sol";

interface IDaiUsdsLike {
    function dai() external view returns (address);
    function daiToUsds(address usr, uint256 wad) external;
    function usdsToDai(address usr, uint256 wad) external;
}

interface IPSMLike {
    function buyGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function fill() external returns (uint256 wad);
    function gem() external view returns (address);
    function sellGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function to18ConversionFactor() external view returns (uint256);
}

library PSMLib {

    function swapUSDSToUSDC(
        IALMProxy    proxy,
        IRateLimits  rateLimits,
        IDaiUsdsLike daiUsds,
        IPSMLike     psm,
        IERC20       usds,
        IERC20       dai,
        bytes32      rateLimitId,
        uint256      usdcAmount,
        uint256      psmTo18ConversionFactor
    )
        external
    {
        _rateLimited(rateLimitId, usdcAmount, rateLimits);

        uint256 usdsAmount = usdcAmount * psmTo18ConversionFactor;

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        _approve(proxy, address(usds), address(daiUsds), usdsAmount);

        // Swap USDS to DAI 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.usdsToDai, (address(proxy), usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1
        _approve(proxy, address(dai), address(psm), usdsAmount);

        // Swap DAI to USDC through the PSM
        proxy.doCall(
            address(psm),
            abi.encodeCall(psm.buyGemNoFee, (address(proxy), usdcAmount))
        );
    }

    function swapUSDCToUSDS(
        IALMProxy    proxy,
        IRateLimits  rateLimits,
        IDaiUsdsLike daiUsds,
        IPSMLike     psm,
        IERC20       dai,
        IERC20       usdc,
        bytes32      rateLimitId,
        uint256      usdcAmount,
        uint256      psmTo18ConversionFactor
    )
        external
    {
        _cancelRateLimit(rateLimitId, usdcAmount, rateLimits);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC)
        _approve(proxy, address(usdc), address(psm), usdcAmount);

        // Max USDC that can be swapped to DAI in one call
        uint256 limit = dai.balanceOf(address(psm)) / psmTo18ConversionFactor;

        if (usdcAmount <= limit) {
            _swapUSDCToDAI(proxy, psm, usdcAmount);
        } else {
            uint256 remainingUsdcToSwap = usdcAmount;

            // Refill the PSM with DAI as many times as needed to get to the full `usdcAmount`.
            // If the PSM cannot be filled with the full amount, psm.fill() will revert
            // with `DssLitePsm/nothing-to-fill` since rush() will return 0.
            // This is desired behavior because this function should only succeed if the full
            // `usdcAmount` can be swapped.
            while (remainingUsdcToSwap > 0) {
                psm.fill();

                limit = dai.balanceOf(address(psm)) / psmTo18ConversionFactor;

                uint256 swapAmount = remainingUsdcToSwap < limit ? remainingUsdcToSwap : limit;

                _swapUSDCToDAI(proxy, psm, swapAmount);

                remainingUsdcToSwap -= swapAmount;
            }
        }

        uint256 daiAmount = usdcAmount * psmTo18ConversionFactor;

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        _approve(proxy, address(dai), address(daiUsds), daiAmount);

        // Swap DAI to USDS 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.daiToUsds, (address(proxy), daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    function _approve(
        IALMProxy proxy,
        address   token,
        address   spender,
        uint256   amount
    )
        internal
    {
        proxy.doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _swapUSDCToDAI(IALMProxy proxy, IPSMLike psm, uint256 usdcAmount) internal {
        // Swap USDC to DAI through the PSM (1:1 since sellGemNoFee is used)
        proxy.doCall(
            address(psm),
            abi.encodeCall(psm.sellGemNoFee, (address(proxy), usdcAmount))
        );
    }

    /**********************************************************************************************/
    /*** Rate Limit helper functions                                                            ***/
    /**********************************************************************************************/

    function _rateLimited(bytes32 key, uint256 amount, IRateLimits rateLimits) internal {
        rateLimits.triggerRateLimitDecrease(key, amount);
    }

    function _cancelRateLimit(bytes32 key, uint256 amount, IRateLimits rateLimits) internal {
        rateLimits.triggerRateLimitIncrease(key, amount);
    }

}
