// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface ICurveFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event CurveMaxSlippageSet(address indexed pool, uint256 maxSlippage);

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage) external;

    function swap(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    function addLiquidity(
        address            pool,
        uint256[] calldata depositAmounts,
        uint256            minLpAmount
    ) external returns (uint256 shares);

    function removeLiquidity(
        address            pool,
        uint256            lpBurnAmount,
        uint256[] calldata minWithdrawAmounts
    ) external returns (uint256[] memory withdrawnTokens);

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_SWAP() external pure returns (bytes32);

    function LIMIT_WITHDRAW() external pure returns (bytes32);

    function getMaxSlippage(address pool) external view returns (uint256);

}
