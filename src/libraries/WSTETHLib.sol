// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }    from "../interfaces/IALMProxy.sol";
import { IRateLimits }  from "../interfaces/IRateLimits.sol";
import { IWSTETHFacet } from "../interfaces/facets/IWSTETHFacet.sol";

import { FacetBase } from "./FacetBase.sol";

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

    bytes32 public constant LIMIT_DEPOSIT          = keccak256("LIMIT_WSTETH_DEPOSIT");
    bytes32 public constant LIMIT_REQUEST_WITHDRAW = keccak256("LIMIT_WSTETH_REQUEST_WITHDRAW");

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable weth;
    address public immutable withdrawQueue;
    address public immutable wsteth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_, address withdrawQueue_, address wsteth_) {
        weth          = weth_;
        withdrawQueue = withdrawQueue_;
        wsteth        = wsteth_;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(uint256 amount) external nonReentrant onlyRole(RELAYER_ROLE) {
        ControllerStorage storage $ = _getControllerStorage();

        _decreaseRateLimit($.rateLimits, LIMIT_DEPOSIT, amount);

        IALMProxy($.proxy).doCall(weth, abi.encodeCall(IWETHLike.withdraw, (amount)));

        IALMProxy($.proxy).doCallWithValue(wsteth, "", amount);
    }

    function requestWithdraw(uint256 amountToRedeem)
        external
        nonReentrant
        onlyRole(RELAYER_ROLE)
        returns (uint256[] memory requestIds)
    {
        ControllerStorage storage $ = _getControllerStorage();

        uint256 stethAmount = IWSTETHLike(wsteth).getStETHByWstETH(amountToRedeem);

        _decreaseRateLimit($.rateLimits, LIMIT_REQUEST_WITHDRAW, stethAmount);

        IALMProxy($.proxy).doCall(
            wsteth,
            abi.encodeCall(IERC20Like.approve, (withdrawQueue, amountToRedeem))
        );

        uint256[] memory amountsToRedeem = new uint256[](1);
        amountsToRedeem[0] = amountToRedeem;

        return abi.decode(
            IALMProxy($.proxy).doCall(
                withdrawQueue,
                abi.encodeCall(
                    IWithdrawalQueueLike.requestWithdrawalsWstETH,
                    (amountsToRedeem, $.proxy)
                )
            ),
            (uint256[])
        );
    }

    function claimWithdrawal(uint256 requestId) external nonReentrant onlyRole(RELAYER_ROLE) {
        ControllerStorage storage $ = _getControllerStorage();

        uint256 initialETHBalance = address($.proxy).balance;

        IALMProxy($.proxy).doCall(
            withdrawQueue,
            abi.encodeCall(IWithdrawalQueueLike.claimWithdrawal, (requestId))
        );

        IALMProxy($.proxy).doCallWithValue(weth, "", address($.proxy).balance - initialETHBalance);
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, uint256 amount) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
