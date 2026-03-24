// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IFacetBase } from "./IFacetBase.sol";

interface IUSDEFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function cooldownAssets(uint256 usdeAmount) external returns (uint256 shares);

    function cooldownShares(uint256 susdeAmount) external returns (uint256 assets);

    function prepareMint(uint256 usdcAmount) external;

    function prepareBurn(uint256 usdeAmount) external;

    function removeDelegatedSigner(address delegatedSigner) external;

    function setDelegatedSigner(address delegatedSigner) external;

    function unstakeSUSDE() external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_USDE_BURN() external view returns (bytes32);

    function LIMIT_USDE_MINT() external view returns (bytes32);

    function LIMIT_SUSDE_COOLDOWN() external view returns (bytes32);

    function ethenaMinter() external view returns (address);

    function susde() external view returns (address);

    function usdc() external view returns (address);

    function usde() external view returns (address);

}
