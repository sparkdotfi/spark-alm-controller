// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "./IFacetBase.sol";

interface IERC4626Facet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxExchangeRateSet(address indexed token, uint256 maxExchangeRate);

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function deposit(address token, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 shares);

    function redeem(address token, uint256 shares, uint256 minAssetsOut)
        external
        returns (uint256 assets);

    function setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function withdraw(address token, uint256 amount, uint256 maxSharesIn)
        external
        returns (uint256 shares);

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function EXCHANGE_RATE_PRECISION() external pure returns (uint256);

    function LIMIT_DEPOSIT() external pure returns (bytes32);

    function LIMIT_WITHDRAW() external pure returns (bytes32);

    function maxExchangeRates(address token) external view returns (uint256);

}
