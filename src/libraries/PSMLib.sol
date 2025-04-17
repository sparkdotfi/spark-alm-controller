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

    bytes32 public constant LIMIT_USDS_TO_USDC = keccak256("LIMIT_USDS_TO_USDC");

    function swapUSDSToUSDCLib(
        uint256 usdcAmount,
        IALMProxy proxy,
        uint256 psmTo18ConversionFactor,
        IRateLimits rateLimits,
        IDaiUsdsLike daiUsds,
        IPSMLike psm,
        IERC20 usds,
        IERC20 dai
    ) external {
        _rateLimited(LIMIT_USDS_TO_USDC, usdcAmount, rateLimits);

        uint256 usdsAmount = usdcAmount * psmTo18ConversionFactor;

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS)
        _approve(address(usds), address(daiUsds), usdsAmount, proxy);

        // Swap USDS to DAI 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.usdsToDai, (address(proxy), usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1
        _approve(address(dai), address(psm), usdsAmount, proxy);

        // Swap DAI to USDC through the PSM
        proxy.doCall(
            address(psm),
            abi.encodeCall(psm.buyGemNoFee, (address(proxy), usdcAmount))
        );
    }

    function swapUSDCToUSDSLib(
        uint256 usdcAmount,
        IALMProxy proxy,
        uint256 psmTo18ConversionFactor,
        IRateLimits rateLimits,
        IDaiUsdsLike daiUsds,
        IPSMLike psm,
        IERC20 dai,
        IERC20 usdc
    ) external {
        _cancelRateLimit(LIMIT_USDS_TO_USDC, usdcAmount, rateLimits);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC)
        _approve(address(usdc), address(psm), usdcAmount, proxy);

        // Max USDC that can be swapped to DAI in one call
        uint256 limit = dai.balanceOf(address(psm)) / psmTo18ConversionFactor;

        if (usdcAmount <= limit) {
            _swapUSDCToDAI(usdcAmount, proxy, psm);
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

                _swapUSDCToDAI(swapAmount, proxy, psm);

                remainingUsdcToSwap -= swapAmount;
            }
        }

        uint256 daiAmount = usdcAmount * psmTo18ConversionFactor;

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        _approve(address(dai), address(daiUsds), daiAmount, proxy);

        // Swap DAI to USDS 1:1
        proxy.doCall(
            address(daiUsds),
            abi.encodeCall(daiUsds.daiToUsds, (address(proxy), daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** Helper functions                                                               ***/
    /**********************************************************************************************/

    function _approve(
        address token,
        address spender,
        uint256 amount,
        IALMProxy proxy
    ) 
        internal 
    {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _swapUSDCToDAI(uint256 usdcAmount, IALMProxy proxy, IPSMLike psm) internal {
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
