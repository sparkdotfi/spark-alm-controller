// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { FacetBase } from "../FacetBase.sol";

import { IWSTETHFacet } from "./IWSTETHFacet.sol";

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool success);

}

interface IWETHLike {

    function withdraw(uint256 amount) external;

}

interface IWithdrawalQueueLike {

    function requestWithdrawalsWstETH(uint256[] calldata amounts, address owner)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 requestId) external;

}

interface IWSTETHLike {

    function getStETHByWstETH(uint256 wstETHAmount) external view returns (uint256);

}

contract WSTETHFacet is IWSTETHFacet, FacetBase {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    bytes32 public constant override LIMIT_DEPOSIT          = keccak256("LIMIT_WSTETH_DEPOSIT");
    bytes32 public constant override LIMIT_REQUEST_WITHDRAW = keccak256("LIMIT_WSTETH_REQUEST_WITHDRAW");

    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override weth;
    address public immutable override withdrawQueue;
    address public immutable override wsteth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_, address withdrawQueue_, address wsteth_) {
        weth          = weth_;
        withdrawQueue = withdrawQueue_;
        wsteth        = wsteth_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    function deposit(uint256 amount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _decreaseRateLimit(LIMIT_DEPOSIT, amount);

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(weth, abi.encodeCall(IWETHLike.withdraw, (amount)));

        IALMProxy(proxy).doCallWithValue(wsteth, "", amount);

        emit WSTETHDeposit(amount);
    }

    function requestWithdraw(uint256 amountToRedeem)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256[] memory requestIds)
    {
        uint256 stethAmount = IWSTETHLike(wsteth).getStETHByWstETH(amountToRedeem);

        _decreaseRateLimit(LIMIT_REQUEST_WITHDRAW, stethAmount);

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(
            wsteth,
            abi.encodeCall(IERC20Like.approve, (withdrawQueue, amountToRedeem))
        );

        uint256[] memory amountsToRedeem = new uint256[](1);
        amountsToRedeem[0] = amountToRedeem;

        requestIds = abi.decode(
            IALMProxy(proxy).doCall(
                withdrawQueue,
                abi.encodeCall(
                    IWithdrawalQueueLike.requestWithdrawalsWstETH,
                    (amountsToRedeem, proxy)
                )
            ),
            (uint256[])
        );

        emit WSTETHRequestWithdraw(amountToRedeem, stethAmount, requestIds);
    }

    function claimWithdrawal(uint256 requestId)
        external
        override
        nonReentrant
        onlyRole(RELAYER_ROLE)
    {
        SharedControllerStorage storage $ = _getSharedControllerStorage();

        address proxy             = $.proxy;
        uint256 initialETHBalance = proxy.balance;

        require(
            IRateLimits($.rateLimits).getRateLimitData(LIMIT_REQUEST_WITHDRAW).maxAmount > 0,
            "WSTETHFacet/invalid-action"
        );

        IALMProxy(proxy).doCall(
            withdrawQueue,
            abi.encodeCall(IWithdrawalQueueLike.claimWithdrawal, (requestId))
        );

        uint256 ethClaimed = proxy.balance - initialETHBalance;

        IALMProxy(proxy).doCallWithValue(weth, "", ethClaimed);

        emit WSTETHClaimWithdrawal(requestId, ethClaimed);
    }

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    function _decreaseRateLimit(bytes32 key, uint256 amount) internal {
        IRateLimits(_getSharedControllerStorage().rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
