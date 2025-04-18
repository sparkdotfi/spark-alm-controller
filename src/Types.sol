// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

library Types {

    struct SwapCurveParams {
        address pool;
        uint256 inputIndex;
        uint256 outputIndex;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 maxSlippage;
    }

}
