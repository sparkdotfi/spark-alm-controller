// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "../IFacetBase.sol";

interface IOTCFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Parameters {
        address buffer;
        uint256 normalizedRate;
        uint256 maxSlippage;  // 1e18 precision
        mapping (address asset => bool isWhitelisted) assetWhitelisted;
    }

    struct State {
        uint256 normalizedSent;
        uint256 sentTimestamp;
        uint256 normalizedClaimed;
    }

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event OTCBufferSet(address indexed exchange, address indexed buffer);

    event OTCClaimed(
        address indexed exchange,
        address indexed buffer,
        address indexed assetClaimed,
        uint256         amountClaimed,
        uint256         normalizedAmountClaimed
    );

    event OTCMaxSlippageSet(address indexed exchange, uint256 maxSlippage);

    event OTCRechargeRateSet(address indexed exchange, uint256 normalizedRate);

    event OTCSwapSent(
        address indexed exchange,
        address indexed buffer,
        address indexed tokenSent,
        uint256         amountSent,
        uint256         normalizedAmountSent
    );

    event OTCWhitelistedAssetSet(
        address indexed exchange,
        address indexed asset,
        bool            isWhitelisted
    );

    /**********************************************************************************************/
    /*** Interactive Functions                                                                  ***/
    /**********************************************************************************************/

    function claim(address exchange, address assetToClaim) external;

    function send(address exchange, address assetToSend, uint256 amount) external;

    function setBuffer(address exchange, address buffer) external;

    function setIsWhitelisted(address exchange, address asset, bool isWhitelisted) external;

    function setMaxSlippage(address exchange, uint256 maxSlippage) external;

    function setRechargeRate(address exchange, uint256 normalizedRate) external;

    /**********************************************************************************************/
    /*** Variables                                                                              ***/
    /**********************************************************************************************/

    function LIMIT_SWAP() external pure returns (bytes32);

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                    ***/
    /**********************************************************************************************/

    function getBuffer(address exchange) external view returns (address);

    function getClaimWithRecharge(address exchange) external view returns (uint256);

    function getIsWhitelisted(address exchange, address asset) external view returns (bool);

    function getMaxSlippage(address exchange) external view returns (uint256);

    function getRechargeRate(address exchange) external view returns (uint256);

    function getState(address exchange)
        external
        view
        returns (uint256 normalizedSent, uint256 sentTimestamp, uint256 normalizedClaimed);

    function isSwapReady(address exchange) external view returns (bool);

}
