// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import {
    AccessControlEnumerableUpgradeable
} from "../../../lib/oz-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {
    UUPSUpgradeable
} from "../../../lib/oz-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import { IWEETHModule } from "./IWEETHModule.sol";

interface IERC20Like {

    function transfer(address to, uint256 amount) external returns (bool);

}

interface IEETHLike {

    function liquidityPool() external view returns (address);

}

interface ILiquidityPoolLike {

    function withdrawRequestNFT() external view returns (address);

}

interface IWEETHLike {

    function eETH() external view returns (address);

}

interface IWETHLike {

    function deposit() external payable;

}

interface IWithdrawRequestNFTLike {

    function claimWithdraw(uint256 requestId) external;

    function isFinalized(uint256 requestId) external view returns (bool);

    function isValid(uint256 requestId) external view returns (bool);

}

// NOTE: This contract is specifically for Mainnet Ethereum.
contract WEETHModule is IWEETHModule, AccessControlEnumerableUpgradeable, UUPSUpgradeable {

    /**********************************************************************************************/
    /*** UUPS Storage                                                                           ***/
    /**********************************************************************************************/

    /// @custom:storage-location erc7201:sky.pau.storage.WEETHModule.v1
    struct WEETHModuleStorage {
        address proxy;
    }

    // keccak256(abi.encode(uint256(keccak256("sky.pau.storage.WEETHModule.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _WEETH_MODULE_STORAGE_LOCATION =
        0x072d818e7fec5969c5ff28092831f41de97405b50d97fe9622741f7cad03bb00;

    function _getWEETHModuleStorage() internal pure returns (WEETHModuleStorage storage $) {
        assembly {
            $.slot := _WEETH_MODULE_STORAGE_LOCATION
        }
    }

    /**********************************************************************************************/
    /*** Declarations                                                                           ***/
    /**********************************************************************************************/

    address public immutable override weeth;
    address public immutable override weth;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor(address weeth_, address weth_) {
        require(weeth_ != address(0), "WEETHModule/zero-weeth");
        require(weth_  != address(0), "WEETHModule/zero-weth");

        weeth = weeth_;
        weth  = weth_;

        _disableInitializers();  // Avoid initializing in the context of the implementation
    }

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    function initialize(address admin_, address proxy_) external override initializer {
        require(proxy_ != address(0), "WEETHModule/invalid-proxy");
        require(admin_ != address(0), "WEETHModule/invalid-admin");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _getWEETHModuleStorage().proxy = proxy_;
    }

    /**********************************************************************************************/
    /*** External Interactive ALMProxy Functions                                                ***/
    /**********************************************************************************************/

    function claimWithdrawal(uint256 requestId) external override returns (uint256 ethReceived) {
        require(msg.sender == _getWEETHModuleStorage().proxy, "WEETHModule/invalid-sender");

        address eeth               = IWEETHLike(weeth).eETH();
        address liquidityPool      = IEETHLike(eeth).liquidityPool();
        address withdrawRequestNFT = ILiquidityPoolLike(liquidityPool).withdrawRequestNFT();

        require(
            IWithdrawRequestNFTLike(withdrawRequestNFT).isValid(requestId),
            "WEETHModule/invalid-request-id"
        );

        require(
            IWithdrawRequestNFTLike(withdrawRequestNFT).isFinalized(requestId),
            "WEETHModule/request-not-finalized"
        );

        IWithdrawRequestNFTLike(withdrawRequestNFT).claimWithdraw(requestId);

        ethReceived = address(this).balance;

        // Wrap ETH to WETH.
        IWETHLike(weth).deposit{value: ethReceived}();

        // No need for SafeERC20 as we are transferring WETH with an expected transfer function.
        IERC20Like(weth).transfer(msg.sender, ethReceived);
    }

    /**********************************************************************************************/
    /*** External Variable Getters                                                              ***/
    /**********************************************************************************************/

    function proxy() external view override returns (address) {
        return _getWEETHModuleStorage().proxy;
    }

    /**********************************************************************************************/
    /*** External View/Pure Functions                                                           ***/
    /**********************************************************************************************/

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IWEETHModule, AccessControlEnumerableUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IWEETHModule).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**********************************************************************************************/
    /*** Receive function                                                                       ***/
    /**********************************************************************************************/

    receive() external payable {}

    /**********************************************************************************************/
    /*** Internal Interactive Functions                                                         ***/
    /**********************************************************************************************/

    // Only DEFAULT_ADMIN_ROLE can upgrade the implementation
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

}
