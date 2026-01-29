// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { AccessControlEnumerable }  from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IEETHLike, ILiquidityPoolLike, IWETHLike, IWEETHLike } from "./libraries/WEETHLib.sol";

interface IWithdrawRequestNFTLike {
    function claimWithdraw(uint256 requestId) external;
    function isFinalized(uint256 requestId) external view returns (bool);
    function isValid(uint256 requestId) external view returns (bool);
}

contract WEETHModule is AccessControlEnumerable {

    address public immutable almProxy;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(address admin, address _almProxy) {
        require(_almProxy != address(0), "WeEthModule/invalid-alm-proxy");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        almProxy = _almProxy;
    }

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived) {
        require(msg.sender == almProxy, "WeEthModule/invalid-sender");

        address eETH               = IWEETHLike(Ethereum.WEETH).eETH();
        address liquidityPool      = IEETHLike(eETH).liquidityPool();
        address withdrawRequestNFT = ILiquidityPoolLike(liquidityPool).withdrawRequestNFT();

        require(
            IWithdrawRequestNFTLike(withdrawRequestNFT).isValid(requestId),
            "WeEthModule/invalid-request-id"
        );

        require(
            IWithdrawRequestNFTLike(withdrawRequestNFT).isFinalized(requestId),
            "WeEthModule/request-not-finalized"
        );

        IWithdrawRequestNFTLike(withdrawRequestNFT).claimWithdraw(requestId);

        ethReceived = address(this).balance;

        // Wrap ETH to WETH.
        IWETHLike(Ethereum.WETH).deposit{value: ethReceived}();

        IERC20(Ethereum.WETH).transfer(almProxy, ethReceived);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
