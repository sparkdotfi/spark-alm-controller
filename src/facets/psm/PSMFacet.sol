// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy } from "../../interfaces/IALMProxy.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

import { IPSMFacet } from "./IPSMFacet.sol";

interface IDAIUSDSLike {

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

contract PSMFacet is IPSMFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _LIMIT_USDS_TO_USDC = keccak256("LIMIT_USDS_TO_USDC");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IPSMFacet
    address public immutable override dai;

    /// @inheritdoc IPSMFacet
    address public immutable override daiUSDS;

    /// @inheritdoc IPSMFacet
    address public immutable override psm;

    /// @inheritdoc IPSMFacet
    address public immutable override usdc;

    /// @inheritdoc IPSMFacet
    address public immutable override usds;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address dai_, address daiUSDS_, address psm_, address usdc_, address usds_) {
        require(dai_     != address(0), "PSMFacet/zero-dai");
        require(daiUSDS_ != address(0), "PSMFacet/zero-daiUSDS");
        require(psm_     != address(0), "PSMFacet/zero-psm");
        require(usdc_    != address(0), "PSMFacet/zero-usdc");
        require(usds_    != address(0), "PSMFacet/zero-usds");

        dai     = dai_;
        daiUSDS = daiUSDS_;
        psm     = psm_;
        usdc    = usdc_;
        usds    = usds_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    // NOTE: The param `usdcAmount` is denominated in 1e6 precision to match how PSM uses
    //       USDC precision for both `buyGemNoFee` and `sellGemNoFee`
    /// @inheritdoc IPSMFacet
    function swapUSDSToUSDC(uint256 usdcAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _decreaseRateLimit(usdsToUSDCSwapRateLimitKey(), usdcAmount);

        uint256 usdsAmount = usdcAmount * to18ConversionFactor();

        // Approve USDS to DAI-USDS migrator from the proxy (assumes the proxy has enough USDS).
        _approve(usds, daiUSDS, usdsAmount);

        address proxy = _getSharedControllerStorage().proxy;

        // Swap USDS to DAI 1:1.
        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.usdsToDai, (proxy, usdsAmount))
        );

        // Approve DAI to PSM from the proxy because conversion from USDS to DAI was 1:1.
        _approve(dai, psm, usdsAmount);

        // Swap DAI to USDC through the PSM.
        IALMProxy(proxy).doCall(psm, abi.encodeCall(IPSMLike.buyGemNoFee, (proxy, usdcAmount)));

        emit PSMSwapUSDSToUSDC(usdcAmount);
    }

    /// @inheritdoc IPSMFacet
    function swapUSDCToUSDS(uint256 usdcAmount)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        _increaseRateLimit(usdsToUSDCSwapRateLimitKey(), usdcAmount);

        // Approve USDC to PSM from the proxy (assumes the proxy has enough USDC).
        _approve(usdc, psm, usdcAmount);

        uint256 conversionFactor = to18ConversionFactor();
        uint256 daiAmount        = usdcAmount * conversionFactor;

        emit PSMSwapUSDCToUSDS(usdcAmount);

        address proxy = _getSharedControllerStorage().proxy;

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

        // Approve DAI to DAI-USDS migrator from the proxy (assumes the proxy has enough DAI).
        _approve(dai, daiUSDS, daiAmount);

        // Swap DAI to USDS 1:1.
        IALMProxy(proxy).doCall(
            daiUSDS,
            abi.encodeCall(IDAIUSDSLike.daiToUsds, (proxy, daiAmount))
        );
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IPSMFacet
    function to18ConversionFactor() public view override returns (uint256) {
        return IPSMLike(psm).to18ConversionFactor();
    }

    /// @inheritdoc IPSMFacet
    function usdsToUSDCSwapRateLimitKey() public pure override returns (bytes32) {
        return _LIMIT_USDS_TO_USDC;
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    // NOTE: As swaps are only done between USDC and USDS, no need for `ApproveLib`.
    function _approve(address token, address spender, uint256 amount) internal {
        IALMProxy(_getSharedControllerStorage().proxy).doCall(
            token,
            abi.encodeCall(IERC20Like.approve, (spender, amount))
        );
    }

    function _swapUSDCToDAI(address proxy, address _psm, uint256 usdcAmount) internal {
        // Swap USDC to DAI through the PSM (1:1 since sellGemNoFee is used).
        IALMProxy(proxy).doCall(
            _psm,
            abi.encodeCall(IPSMLike.sellGemNoFee, (proxy, usdcAmount))
        );
    }

}
