// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    IERC20Metadata as IERC20
} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {
    AccessControlEnumerableUpgradeable
} from "../lib/oz-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { UUPSUpgradeable } from "../lib/oz-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

import { IEETHLike, ILiquidityPoolLike, IWETHLike, IWEETHLike } from "./libraries/WEETHLib.sol";

interface IWithdrawRequestNFTLike {

    function claimWithdraw(uint256 requestId) external;

    function isFinalized(uint256 requestId) external view returns (bool);

    function isValid(uint256 requestId) external view returns (bool);

}

// NOTE: This contract is is specifically for Mainnet Ethereum.
contract WEETHModule is AccessControlEnumerableUpgradeable, UUPSUpgradeable {

    using SafeERC20 for IERC20;

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    struct WEETHModuleStorage {
        address almProxy;
    }

    // keccak256(abi.encode(uint256(keccak256("almController.storage.WEETHModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _WEETH_MODULE_STORAGE_LOCATION =
        0x72fb93b69874a05cc16cf86ff69e742007cd0f04a37e31aa1dda9b1c977e8300;

    function _getWEETHModuleStorage() internal pure returns (WEETHModuleStorage storage $) {
        assembly {
            $.slot := _WEETH_MODULE_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor() {
        _disableInitializers();  // Avoid initializing in the context of the implementation
    }

    function initialize(address admin, address almProxy_) external initializer {
        require(almProxy_ != address(0), "WEETHModule/invalid-alm-proxy");
        require(admin     != address(0), "WEETHModule/invalid-admin");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        _getWEETHModuleStorage().almProxy = almProxy_;
    }

    // Only DEFAULT_ADMIN_ROLE can upgrade the implementation
    function _authorizeUpgrade(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived) {
        require(msg.sender == almProxy(), "WeEthModule/invalid-sender");

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

        IERC20(Ethereum.WETH).safeTransfer(msg.sender, ethReceived);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external pure returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function almProxy() public view returns (address) {
        return _getWEETHModuleStorage().almProxy;
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable { }

}
