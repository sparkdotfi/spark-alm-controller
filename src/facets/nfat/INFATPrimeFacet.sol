// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface INFATPrimeFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function subscribe(address nfatFacility, uint256 amount, bytes calldata data) external;

    function withdraw(address nfatFacility, uint256 amount) external;

    function collect(address nfatFacility, uint256 tokenId, uint256 amount) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_SUBSCRIBE() external pure returns (bytes32);

    function LIMIT_COLLECT() external pure returns (bytes32);

}
