// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IFacetBase } from "./IFacetBase.sol";

interface IOTCFacet is IFacetBase {

    /**********************************************************************************************/
    /*** Structs                                                                                ***/
    /**********************************************************************************************/

    struct Parameters {
        address buffer;
        uint256 rechargeRate18;
        uint256 maxSlippage;
        mapping (address asset => bool isWhitelisted) assetWhitelisted;
    }

    struct State {
        uint256 sent18;
        uint256 sentTimestamp;
        uint256 claimed18;
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
        uint256         amountClaimed18
    );

    event OTCSwapSent(
        address indexed exchange,
        address indexed buffer,
        address indexed tokenSent,
        uint256         amountSent,
        uint256         amountSent18
    );

    event OTCRechargeRateSet(address indexed exchange, uint256 rate18);

    event OTCWhitelistedAssetSet(
        address indexed exchange,
        address indexed asset,
        bool            isWhitelisted
    );

    event OTCMaxSlippageSet(address indexed exchange, uint256 maxSlippage);

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function setMaxSlippage(address exchange, uint256 maxSlippage) external;

    function setBuffer(address exchange, address buffer) external;

    function setRechargeRate(address exchange, uint256 rechargeRate18) external;

    function setIsWhitelisted(address exchange, address asset, bool isWhitelisted) external;

    function send(address exchange, address assetToSend, uint256 amount) external;

    function claim(address exchange, address assetToClaim) external;

    /**********************************************************************************************/
    /*** View/Pure functions                                                                    ***/
    /**********************************************************************************************/

    function LIMIT_SWAP() external pure returns (bytes32);

    function getBuffer(address exchange) external view returns (address);

    function getMaxSlippage(address exchange) external view returns (uint256);

    function getRechargeRate(address exchange) external view returns (uint256);

    function getIsWhitelisted(address exchange, address asset) external view returns (bool);

    function getState(address exchange)
        external
        view
        returns (uint256 sent18, uint256 sentTimestamp, uint256 claimed18);

    function getClaimWithRecharge(address exchange) external view returns (uint256);

    function isSwapReady(address exchange) external view returns (bool);

}
