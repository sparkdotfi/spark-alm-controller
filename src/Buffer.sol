// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { AccessControlEnumerable } from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { Address }                 from "openzeppelin-contracts/contracts/utils/Address.sol";

contract Buffer is AccessControlEnumerable {

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    address public exchange;

    uint256 public lastPendingReceivable;
    uint256 public lastTimestamp;
    uint256 public decrementingRate;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address controller_, address exchange_, address almProxy_, address admin) {
        controller = controller_;
        exchange   = exchange;
        almProxy   = almProxy;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**********************************************************************************************/
    /*** Call functions                                                                         ***/
    /**********************************************************************************************/

    function sendToExchange(address asset, uint256 amountOut) external {
        require(pendingReceivables() == 0, "Buffer/insufficient-unlock-amount");

        IERC20(asset).transferFrom(msg.sender, exchange, amountOut);

        lastPendingReceivable = amountOut
            * MainnetController(controller).maxSlippages(address(this))
            * 1e18
            / 10 ** IERC20(asset).decimals()
            / 1e18;

        lastTimestamp = block.timestamp;
    }

    function unlock(address asset) external {
        uint256 balance = IERC20(asset).balanceOf(address(this));

        IERC20(asset).transfer(almProxy, balance);

        uint256 decrementAmount = balance * 1e18 / 10 ** IERC20(asset).decimals();

        lastPendingReceivable = safeSub(pendingReceivables(), decrementAmount);
        lastTimestamp         = block.timestamp;
    }

    function pendingReceivables() public view returns (uint256) {
        uint256 decrementedAmount = decrementingRate * (block.timestamp - lastTimestamp) / 1e27;
        return safeSub(lastPendingReceivable, decrementedAmount);
    }

    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
