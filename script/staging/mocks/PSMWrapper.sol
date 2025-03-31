// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

interface IPSMLike {
    function buyGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function fill() external returns (uint256 wad);
    function gem() external view returns(address);
    function pocket() external view returns(address);
    function sellGemNoFee(address usr, uint256 usdcAmount) external returns (uint256 usdsAmount);
    function to18ConversionFactor() external view returns (uint256);
}

interface ILivePSMLike is IPSMLike {
    function buyGem(address usr, uint256 usdcAmount) external returns (uint256 swappedAmount);
    function sellGem(address usr, uint256 usdcAmount) external returns (uint256 swappedAmount);
}

// TODO: Add admin that can withdraw

contract PSMWrapper {

    IERC20 public immutable usdc;
    IERC20 public immutable dai;

    ILivePSMLike public immutable psm;

    constructor(address usdc_, address dai_, address psm_) {
        usdc = IERC20(usdc_);
        dai  = IERC20(dai_);
        psm  = ILivePSMLike(psm_);
    }

    /**********************************************************************************************/
    /*** Wrapped external functions                                                             ***/
    /**********************************************************************************************/

    function buyGemNoFee(address usr, uint256 usdcAmount)
        external returns (uint256 swappedAmount)
    {
        uint256 daiAmount = usdcAmount * 1e12;

        dai.transferFrom(msg.sender, address(this), daiAmount);
        dai.approve(address(psm), daiAmount);
        swappedAmount = psm.buyGem(usr, usdcAmount);
    }

    function sellGemNoFee(address usr, uint256 usdcAmount)
        external returns (uint256 swappedAmount)
    {
        usdc.transferFrom(msg.sender, address(this), usdcAmount);
        usdc.approve(address(psm), usdcAmount);
        swappedAmount = psm.sellGem(usr, usdcAmount);
    }

    function fill() external returns (uint256) {
        return psm.fill();
    }

    /**********************************************************************************************/
    /*** Wrapped view functions                                                                 ***/
    /**********************************************************************************************/

    function gem() external view returns (address) {
        return psm.gem();
    }

    function pocket() external view returns (address) {
        return psm.pocket();
    }

    function to18ConversionFactor() external view returns (uint256) {
        return psm.to18ConversionFactor();
    }

}
