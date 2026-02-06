// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IRateLimits } from "../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../interfaces/IALMProxy.sol";

interface IDAIUSDSLike {

    function dai() external view returns (address);

    function daiToUsds(address usr, uint256 wad) external;

    function usdsToDai(address usr, uint256 wad) external;

}

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool success);

    function balanceOf(address account) external view returns (uint256 balance);

}

interface IPSMLike {

    function buyGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);

    function fill() external returns (uint256 wad);

    function sellGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);

    function to18ConversionFactor() external view returns (uint256);

}

library PSMLib {

    bytes32 public constant LIMIT_USDS_TO_USDC = keccak256("LIMIT_USDS_TO_USDC");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function swapUSDSToUSDC(
        address proxy,
        address rateLimits,
        address daiUSDS,
        address psm,
        address usds,
        address dai,
        uint256 usdcAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitDecrease(LIMIT_USDS_TO_USDC, usdcAmount);

        uint256 usdsAmount = usdcAmount * IPSMLike(psm).to18ConversionFactor();

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS).
        _approve(proxy, usds, daiUSDS, usdsAmount);

        // Swap USDS to DAI 1:1
        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1.
        _approve(proxy, dai, psm, usdsAmount);

        // Swap DAI to USDC through the PSM.
        IALMProxy(proxy).doCall(psm, abi.encodeCall(IPSMLike.buyGemNoFee, (proxy, usdcAmount)));
    }

    function swapUSDCToUSDS(
        address proxy,
        address rateLimits,
        address daiUSDS,
        address psm,
        address dai,
        address usdc,
        uint256 usdcAmount
    )
        external
    {
        IRateLimits(rateLimits).triggerRateLimitIncrease(LIMIT_USDS_TO_USDC, usdcAmount);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC).
        _approve(proxy, usdc, psm, usdcAmount);

        uint256 conversionFactor = IPSMLike(psm).to18ConversionFactor();

        // Max USDC that can be swapped to DAI in one call/
        uint256 limit = IERC20Like(dai).balanceOf(psm) / conversionFactor;

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
                IPSMLike(psm).fill();

                limit = IERC20Like(dai).balanceOf(psm) / conversionFactor;

                uint256 swapAmount = remainingUsdcToSwap < limit ? remainingUsdcToSwap : limit;

                _swapUSDCToDAI(proxy, psm, swapAmount);

                remainingUsdcToSwap -= swapAmount;
            }
        }

        uint256 daiAmount = usdcAmount * conversionFactor;

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI)
        _approve(proxy, dai, daiUSDS, daiAmount);

        // Swap DAI to USDS 1:1
        IALMProxy(proxy).doCall(daiUSDS,abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount)));
    }

    function to18ConversionFactor(address psm) external view returns (uint256) {
        return IPSMLike(psm).to18ConversionFactor();
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    // NOTE: As swaps are only done between USDC and USDS, no need for `ApproveLib`.
    function _approve(address proxy, address token, address spender, uint256 amount) internal {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, amount)));
    }

    function _swapUSDCToDAI(address proxy, address psm, uint256 usdcAmount) internal {
        // Swap USDC to DAI through the PSM (1:1 since sellGemNoFee is used)
        IALMProxy(proxy).doCall(
            psm,
            abi.encodeCall(IPSMLike.sellGemNoFee, (address(proxy), usdcAmount))
        );
    }

}
