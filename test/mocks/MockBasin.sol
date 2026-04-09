// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

contract MockBasin {

    /**********************************************************************************************/
    /*** State Variables                                                                        ***/
    /**********************************************************************************************/

    bool    internal _useCustomDepositShares;
    uint256 internal _depositShares;

    bool    internal _useCustomWithdrawAmount;
    uint256 internal _withdrawAmount;

    /**********************************************************************************************/
    /*** Setter Functions                                                                       ***/
    /**********************************************************************************************/

    function setDepositShares(uint256 shares_) external {
        _useCustomDepositShares = true;
        _depositShares          = shares_;
    }

    function setWithdrawAmount(uint256 amount_) external {
        _useCustomWithdrawAmount = true;
        _withdrawAmount          = amount_;
    }

    /**********************************************************************************************/
    /*** Basin Interface Functions                                                              ***/
    /**********************************************************************************************/

    function deposit(address asset, address, uint256 assetsToDeposit)
        external
        returns (uint256 newShares)
    {
        IERC20(asset).transferFrom(msg.sender, address(this), assetsToDeposit);

        newShares = _useCustomDepositShares ? _depositShares : assetsToDeposit;
    }

    function withdraw(address asset, address receiver, uint256 maxAssetsToWithdraw)
        external
        returns (uint256 assetsWithdrawn)
    {
        assetsWithdrawn = _useCustomWithdrawAmount ? _withdrawAmount : maxAssetsToWithdraw;

        IERC20(asset).transfer(receiver, assetsWithdrawn);
    }

}
