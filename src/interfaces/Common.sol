// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

interface IERC20Like {

    function approve(address spender, uint256 amount) external returns (bool success);

    function balanceOf(address account) external view returns (uint256 balance);

    function decimals() external view returns (uint8 decimals);

}

interface IPermit2Like {

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

}
