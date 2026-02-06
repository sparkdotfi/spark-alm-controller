// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import {
    AccessControlEnumerableUpgradeable
} from "../lib/oz-upgradeable/contracts/access/extensions/AccessControlEnumerableUpgradeable.sol";

import { UUPSUpgradeable } from "../lib/oz-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import { Ethereum } from "../lib/spark-address-registry/src/Ethereum.sol";

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

// NOTE: This contract is is specifically for Mainnet Ethereum.
contract WEETHModule is AccessControlEnumerableUpgradeable, UUPSUpgradeable {

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

    function initialize(address admin_, address almProxy_) external initializer {
        require(almProxy_ != address(0), "WEETHModule/invalid-alm-proxy");
        require(admin_     != address(0), "WEETHModule/invalid-admin");

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        _getWEETHModuleStorage().almProxy = almProxy_;
    }

    // Only DEFAULT_ADMIN_ROLE can upgrade the implementation
    function _authorizeUpgrade(address) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**********************************************************************************************/
    /*** External functions                                                                     ***/
    /**********************************************************************************************/

    function claimWithdrawal(uint256 requestId) external returns (uint256 ethReceived) {
        require(msg.sender == almProxy(), "WEETHModule/invalid-sender");

        address eeth               = IWEETHLike(Ethereum.WEETH).eETH();
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
        IWETHLike(Ethereum.WETH).deposit{value: ethReceived}();

        // No need for SafeERC20 as we are transferring WETH with an expected transfer function.
        IERC20Like(Ethereum.WETH).transfer(msg.sender, ethReceived);
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
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
