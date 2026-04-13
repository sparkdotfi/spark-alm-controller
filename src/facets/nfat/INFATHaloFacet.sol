// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface INFATHaloFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event NFATAllowedRepayRecipientSet(address indexed recipient, bool isAllowed);

    /**********************************************************************************************/
    /*** Interactive functions                                                                  ***/
    /**********************************************************************************************/

    function setAllowedRepayRecipient(address recipient, bool isAllowed) external;

    function repay(address nfatFacility, uint256 tokenId, uint256 amount) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function getAllowedRepayRecipients() external view returns (address[] memory);

    function isAllowedRepayRecipient(address recipient) external view returns (bool);

    function LIMIT_REPAY() external pure returns (bytes32);

}
