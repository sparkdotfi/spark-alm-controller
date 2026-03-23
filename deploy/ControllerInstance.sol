// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

struct ControllerInstance {
    address         almProxy;
    address payable controller;
    address         rateLimits;
}
