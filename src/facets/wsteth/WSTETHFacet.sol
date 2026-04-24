// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IALMProxy }   from "../../interfaces/IALMProxy.sol";
import { IRateLimits } from "../../interfaces/IRateLimits.sol";

import { IFacet } from "../IFacet.sol";

import { Facet } from "../Facet.sol";

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

contract WSTETHFacet is IWSTETHFacet, Facet {

    /**********************************************************************************************/
    /*** Constants                                                                              ***/
    /**********************************************************************************************/

    /// @inheritdoc IWSTETHFacet
    bytes32 public constant override LIMIT_DEPOSIT = keccak256("LIMIT_WSTETH_DEPOSIT");

    /// @inheritdoc IWSTETHFacet
    bytes32 public constant override LIMIT_REQUEST_WITHDRAW =
        keccak256("LIMIT_WSTETH_REQUEST_WITHDRAW");

    /// @inheritdoc IFacet
    string public constant override VERSION = "1.0.0";

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    /// @inheritdoc IWSTETHFacet
    address public immutable override weth;

    /// @inheritdoc IWSTETHFacet
    address public immutable override withdrawQueue;

    /// @inheritdoc IWSTETHFacet
    address public immutable override wsteth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weth_, address withdrawQueue_, address wsteth_) {
        require(weth_          != address(0), "WSTETHFacet/zero-weth");
        require(withdrawQueue_ != address(0), "WSTETHFacet/zero-withdrawQueue");
        require(wsteth_        != address(0), "WSTETHFacet/zero-wsteth");

        weth          = weth_;
        withdrawQueue = withdrawQueue_;
        wsteth        = wsteth_;
    }

    /**********************************************************************************************/
    /*** External Interactive Relayer Functions                                                 ***/
    /**********************************************************************************************/

    /// @inheritdoc IWSTETHFacet
    function deposit(uint256 amount) external override nonReentrant onlyRole(RELAYER_ROLE) {
        _decreaseRateLimit(LIMIT_DEPOSIT, amount);

        address proxy = _getSharedControllerStorage().proxy;

        IALMProxy(proxy).doCall(weth, abi.encodeCall(IWETHLike.withdraw, (amount)));

        IALMProxy(proxy).doCallWithValue(wsteth, "", amount);

        emit WSTETHDeposit(amount);
    }

    /// @inheritdoc IWSTETHFacet
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

        // NOTE: Despite the withdrawal queue contract being mutable, there is no other reliable way
        //       to get the requestIds without decoding the return value.
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

    /// @inheritdoc IWSTETHFacet
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
