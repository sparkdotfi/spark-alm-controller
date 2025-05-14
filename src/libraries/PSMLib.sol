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

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct SwapUSDSToUSDCParams {
        IALMProxy    proxy;
        IRateLimits  rateLimits;
        IDaiUsdsLike daiUsds;
        IPSMLike     psm;
        IERC20       usds;
        IERC20       dai;
        bytes32      rateLimitId;
        uint256      usdcAmount;
        uint256      psmTo18ConversionFactor;
    }

    struct SwapUSDCToUSDSParams {
        IALMProxy    proxy;
        IRateLimits  rateLimits;
        IDaiUsdsLike daiUsds;
        IPSMLike     psm;
        IERC20       dai;
        IERC20       usdc;
        bytes32      rateLimitId;
        uint256      usdcAmount;
        uint256      psmTo18ConversionFactor;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swapUSDSToUSDC(SwapUSDSToUSDCParams calldata params) external {
        _rateLimited(params.rateLimitId, params.usdcAmount, params.rateLimits);

        uint256 usdsAmount = params.usdcAmount * params.psmTo18ConversionFactor;

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        _approve(params.proxy, address(params.usds), address(params.daiUsds), usdsAmount);

        // Swap USDS to DAI 1:1
        params.proxy.doCall(
            address(params.daiUsds),
            abi.encodeCall(params.daiUsds.usdsToDai, (address(params.proxy), usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1
        _approve(params.proxy, address(params.dai), address(params.psm), usdsAmount);

        // Swap DAI to USDC through the PSM
        params.proxy.doCall(
            address(params.psm),
            abi.encodeCall(params.psm.buyGemNoFee, (address(params.proxy), params.usdcAmount))
        );
    }

    function swapUSDCToUSDS(SwapUSDCToUSDSParams calldata params) external {
        _cancelRateLimit(params.rateLimitId, params.usdcAmount, params.rateLimits);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC)
        _approve(params.proxy, address(params.usdc), address(params.psm), params.usdcAmount);

        // Max USDC that can be swapped to DAI in one call
        uint256 limit = params.dai.balanceOf(address(params.psm)) / params.psmTo18ConversionFactor;

        if (params.usdcAmount <= limit) {
            _swapUSDCToDAI(params.proxy, params.psm, params.usdcAmount);
        } else {
            uint256 remainingUsdcToSwap = params.usdcAmount;

            // Refill the PSM with DAI as many times as needed to get to the full `usdcAmount`.
            // If the PSM cannot be filled with the full amount, psm.fill() will revert
            // with `DssLitePsm/nothing-to-fill` since rush() will return 0.
            // This is desired behavior because this function should only succeed if the full
            // `usdcAmount` can be swapped.
            while (remainingUsdcToSwap > 0) {
                params.psm.fill();

                limit = params.dai.balanceOf(address(params.psm)) / params.psmTo18ConversionFactor;

                uint256 swapAmount = remainingUsdcToSwap < limit ? remainingUsdcToSwap : limit;

                _swapUSDCToDAI(params.proxy, params.psm, swapAmount);

                remainingUsdcToSwap -= swapAmount;
            }
        }

        uint256 daiAmount = params.usdcAmount * params.psmTo18ConversionFactor;

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        _approve(params.proxy, address(params.dai), address(params.daiUsds), daiAmount);

        // Swap DAI to USDS 1:1
        params.proxy.doCall(
            address(params.daiUsds),
            abi.encodeCall(params.daiUsds.daiToUsds, (address(params.proxy), daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    // NOTE: As swaps are only done between USDC and USDS and vice versa, using `_forceApprove` 
    //       is unnecessary.
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
