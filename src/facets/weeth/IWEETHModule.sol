// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    IAccessControlEnumerable
} from "../../../lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IWEETHModule is IAccessControlEnumerable {

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    /**
     * @notice Claims a withdrawal.
     * @param  requestId   Request ID.
     * @return ethReceived Amount of ETH received.
     */
    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived);

    /**
     * @notice Initializes the WEETH module.
     * @param  admin_ Admin address.
     * @param  proxy_ ALM proxy address.
     */
    function initialize(address admin_, address proxy_) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    /// @notice Address of the ALMProxy contract.
    function proxy() external view returns (address);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    /// @notice Address of the weETH token contract (immutable).
    function weeth() external view returns (address);

    /// @notice Address of the WETH token contract (immutable).
    function weth() external view returns (address);

    /**
     * @notice Receives an ERC721 token.
     * @param  operator Operator address.
     * @param  from     From address.
     * @param  tokenId  Token ID.
     * @param  data     Data.
     * @return selector Selector response.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        pure
        returns (bytes4 selector);

    /**
     * @notice Supports an interface.
     * @param  interfaceId Interface ID.
     * @return isSupported True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool isSupported);

}
