// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IRateLimits } from "../../interfaces/IRateLimits.sol";
import { IALMProxy }   from "../../interfaces/IALMProxy.sol";

import { FacetBase } from "../FacetBase.sol";

import { IPSMFacet } from "./IPSMFacet.sol";

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

contract PSMFacet is IPSMFacet, FacetBase {

    bytes32 public constant LIMIT_USDS_TO_USDC = keccak256("LIMIT_USDS_TO_USDC");

    address public immutable dai;
    address public immutable daiUSDS;
    address public immutable psm;
    address public immutable usdc;
    address public immutable usds;

    constructor(address dai_, address daiUSDS_, address psm_, address usdc_, address usds_) {
        dai     = dai_;
        daiUSDS = daiUSDS_;
        psm     = psm_;
        usdc    = usdc_;
        usds    = usds_;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    // NOTE: The param `usdcAmount` is denominated in 1e6 precision to match how PSM uses
    //       USDC precision for both `buyGemNoFee` and `sellGemNoFee`
    function swapUSDSToUSDC(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitDecrease(LIMIT_USDS_TO_USDC, usdcAmount);

        uint256 usdsAmount = usdcAmount * IPSMLike(psm).to18ConversionFactor();
        address proxy      = $.proxy;

        // Approve USDS to DaiUsds migrator from the proxy (assumes the proxy has enough USDS).
        _approve(usds, proxy, daiUSDS, usdsAmount);

        // Swap USDS to DAI 1:1.
        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1.
        _approve(dai, proxy, psm, usdsAmount);

        // Swap DAI to USDC through the PSM.
        IALMProxy(proxy).doCall(psm, abi.encodeCall(IPSMLike.buyGemNoFee, (proxy, usdcAmount)));
    }

    function swapUSDCToUSDS(uint256 usdcAmount) external nonReentrant onlyRole(RELAYER_ROLE) {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        IRateLimits($.rateLimits).triggerRateLimitIncrease(LIMIT_USDS_TO_USDC, usdcAmount);

        address proxy = $.proxy;

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC).
        _approve(usdc, proxy, psm, usdcAmount);

        uint256 conversionFactor = IPSMLike(psm).to18ConversionFactor();
        uint256 daiAmount        = usdcAmount * conversionFactor;

        // Swap all if amount is less than or equal to the max USDC that can be swapped to DAI in
        // one call, else refill and swap in chunks within the limits.
        if (usdcAmount <= IERC20Like(dai).balanceOf(psm) / conversionFactor) {
            _swapUSDCToDAI(proxy, psm, usdcAmount);
        } else {
            // Refill the PSM with DAI as many times as needed to get to the full `usdcAmount`.
            // If the PSM cannot be filled with the full amount, psm.fill() will revert with
            // `DssLitePsm/nothing-to-fill` since rush() will return 0. This is desired behavior
            // because this function should only succeed if the full `usdcAmount` can be swapped.
            while (usdcAmount > 0) {
                IPSMLike(psm).fill();

                // Max USDC that can be swapped to DAI in one call/fill.
                uint256 limit      = IERC20Like(dai).balanceOf(psm) / conversionFactor;
                uint256 swapAmount = usdcAmount <= limit ? usdcAmount : limit;

                _swapUSDCToDAI(proxy, psm, swapAmount);

                usdcAmount -= swapAmount;
            }
        }

        // Approve DAI to DaiUsds migrator from the proxy (assumes the proxy has enough DAI).
        _approve(dai, proxy, daiUSDS, daiAmount);

        // Swap DAI to USDS 1:1.
        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );
    }

    function to18ConversionFactor() external view returns (uint256) {
        return IPSMLike(psm).to18ConversionFactor();
    }

    /**********************************************************************************************/
    /*** Helper functions                                                                       ***/
    /**********************************************************************************************/

    // NOTE: As swaps are only done between USDC and USDS, no need for `ApproveLib`.
    function _approve(address token, address proxy, address spender, uint256 amount) internal {
        IALMProxy(proxy).doCall(token, abi.encodeCall(IERC20Like.approve, (spender, amount)));
    }

    function _swapUSDCToDAI(address proxy, address _psm, uint256 usdcAmount) internal {
        // Swap USDC to DAI through the PSM (1:1 since sellGemNoFee is used).
        IALMProxy(proxy).doCall(
            _psm,
            abi.encodeCall(IPSMLike.sellGemNoFee, (proxy, usdcAmount))
        );
    }

}
