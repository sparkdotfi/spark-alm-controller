// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IALMProxy }   from "../interfaces/IALMProxy.sol";
import { IRateLimits } from "../interfaces/IRateLimits.sol";

interface IERC20ike {

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

library WSTETHLib {

    bytes32 public constant LIMIT_DEPOSIT          = keccak256("LIMIT_WSTETH_DEPOSIT");
    bytes32 public constant LIMIT_REQUEST_WITHDRAW = keccak256("LIMIT_WSTETH_REQUEST_WITHDRAW");

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(
        address proxy,
        address rateLimits,
        address weth,
        address wsteth,
        uint256 amount
    )
        external
    {
        _decreaseRateLimit(rateLimits, LIMIT_DEPOSIT, amount);

        IALMProxy(proxy).doCall(weth, abi.encodeCall(IWETHLike.withdraw, (amount)));

        IALMProxy(proxy).doCallWithValue(wsteth, "", amount);
    }

    function requestWithdraw(
        address proxy,
        address rateLimits,
        address wsteth,
        address withdrawQueue,
        uint256 amountToRedeem
    )
        external
        returns (uint256[] memory requestIds)
    {
        uint256 stethAmount = IWSTETHLike(wsteth).getStETHByWstETH(amountToRedeem);

        _decreaseRateLimit(rateLimits, LIMIT_REQUEST_WITHDRAW, stethAmount);

        IALMProxy(proxy).doCall(
            wsteth,
            abi.encodeCall(IERC20ike.approve, (withdrawQueue, amountToRedeem))
        );

        uint256[] memory amountsToRedeem = new uint256[](1);
        amountsToRedeem[0] = amountToRedeem;

        return abi.decode(
            IALMProxy(proxy).doCall(
                withdrawQueue,
                abi.encodeCall(
                    IWithdrawalQueueLike.requestWithdrawalsWstETH,
                    (amountsToRedeem, proxy)
                )
            ),
            (uint256[])
        );
    }

    function claimWithdrawal(
        address proxy,
        address withdrawQueue,
        address weth,
        uint256 requestId
    )
        external
    {
        uint256 initialEthBalance = address(proxy).balance;

        IALMProxy(proxy).doCall(
            withdrawQueue,
            abi.encodeCall(IWithdrawalQueueLike.claimWithdrawal, (requestId))
        );

        IALMProxy(proxy).doCallWithValue(weth, "", address(proxy).balance - initialEthBalance);
    }

    function _decreaseRateLimit(address rateLimits, bytes32 key, uint256 amount) internal {
        IRateLimits(rateLimits).triggerRateLimitDecrease(key, amount);
    }

}
