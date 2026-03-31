// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IWEETHModule is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived);

    function initialize(address admin_, address almProxy_) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function almProxy() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

}
