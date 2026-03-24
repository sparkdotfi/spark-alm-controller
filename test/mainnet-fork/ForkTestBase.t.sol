// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AllocatorDeploy } from "../../lib/dss-allocator/deploy/AllocatorDeploy.sol";

import { AllocatorInit, AllocatorIlkConfig } from "../../lib/dss-allocator/deploy/AllocatorInit.sol";

import {
    AllocatorIlkInstance,
    AllocatorSharedInstance
} from "../../lib/dss-allocator/deploy/AllocatorInstances.sol";

import { DssTest }          from "../../lib/dss-test/src/DssTest.sol";
import { DssInstance, MCD } from "../../lib/dss-test/src/MCD.sol";

import { IERC20 }   from "../../lib/forge-std/src/interfaces/IERC20.sol";
import { IERC4626 } from "../../lib/forge-std/src/interfaces/IERC4626.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { CCTPForwarder } from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { IDAIUSDSFacet }       from "../../src/interfaces/facets/IDAIUSDSFacet.sol";
import { ITransferAssetFacet } from "../../src/interfaces/facets/ITransferAssetFacet.sol";
import { IUSDEFacet }          from "../../src/interfaces/facets/IUSDEFacet.sol";
import { IUSDSFacet }          from "../../src/interfaces/facets/IUSDSFacet.sol";
import { IWEETHFacet }         from "../../src/interfaces/facets/IWEETHFacet.sol";
import { IWrapProxyETHFacet }  from "../../src/interfaces/facets/IWrapProxyETHFacet.sol";
import { IWSTETHFacet }        from "../../src/interfaces/facets/IWSTETHFacet.sol";

import { DAIUSDSFacet }       from "../../src/libraries/DAIUSDSLib.sol";
import { TransferAssetFacet } from "../../src/libraries/TransferAssetLib.sol";
import { USDEFacet }          from "../../src/libraries/USDELib.sol";
import { USDSFacet }          from "../../src/libraries/USDSLib.sol";
import { WEETHFacet }         from "../../src/libraries/WEETHLib.sol";
import { WrapProxyETHFacet }  from "../../src/libraries/WrapProxyETHLib.sol";
import { WSTETHFacet }        from "../../src/libraries/WSTETHLib.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { MainnetController } from "../../src/MainnetController.sol";
import { RateLimitHelpers }  from "../../src/RateLimitHelpers.sol";
import { RateLimits }        from "../../src/RateLimits.sol";
import { AccessControls }    from "../../src/AccessControls.sol";
import { Parameters }        from "../../src/Parameters.sol";

import { IMainnetControllerFull } from "../interfaces/IMainnetControllerFull.sol";

interface IChainlogLike {

    function getAddress(bytes32) external view returns (address);

}

interface IBufferLike {

    function approve(address, address, uint256) external;

}

interface IPSMLike {

    function kiss(address) external;

}

interface ISUSDELike is IERC4626 {

    function cooldownAssets(uint256 usdeAmount) external returns (uint256);

    function cooldownShares(uint256 susdeAmount) external returns (uint256);

    function unstake(address receiver) external;

    function silo() external view returns(address);

}

interface IVaultLike {

    function buffer() external view returns (address);

    function rely(address) external;

}

abstract contract ForkTestBase is DssTest {

    using DomainHelpers for *;

    struct MintRecipient {
        uint32  domain;
        bytes32 mintRecipient;
    }

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant ilk                = "ILK-A";
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 constant PSM_ILK = 0x4c4954452d50534d2d555344432d410000000000000000000000000000000000;

    uint256 constant INK           = 1e12 * 1e18;  // Ink initialization amount
    uint256 constant SEVEN_PCT_APY = 1.000000002145441671308778766e27;  // 7% APY (current DSR)
    uint256 constant EIGHT_PCT_APY = 1.000000002440418608258400030e27;  // 8% APY (current DSR + 1%)

    address freezer = Ethereum.ALM_FREEZER_MULTISIG;
    address relayer = Ethereum.ALM_RELAYER_MULTISIG;

    address backstopRelayer = makeAddr("backstopRelayer");  // TODO: Replace with real backstop

    bytes32 CONTROLLER;
    bytes32 FREEZER;
    bytes32 RELAYER;

    /**********************************************************************************************/
    /*** Mainnet addresses/constants                                                            ***/
    /**********************************************************************************************/

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    address constant CCTP_MESSENGER = Ethereum.CCTP_TOKEN_MESSENGER;
    address constant DAI_USDS       = Ethereum.DAI_USDS;
    address constant ETHENA_MINTER  = Ethereum.ETHENA_MINTER;
    address constant PAUSE_PROXY    = Ethereum.PAUSE_PROXY;
    address constant SPARK_PROXY    = Ethereum.SPARK_PROXY;

    IERC20 constant dai  = IERC20(Ethereum.DAI);
    IERC20 constant usdc = IERC20(Ethereum.USDC);
    IERC20 constant usde = IERC20(Ethereum.USDE);
    IERC20 constant usds = IERC20(Ethereum.USDS);
    IERC20 constant usdt = IERC20(Ethereum.USDT);

    IERC4626 constant susds = IERC4626(Ethereum.SUSDS);

    ISUSDELike constant susde = ISUSDELike(Ethereum.SUSDE);

    address POCKET;
    address USDS_JOIN;

    DssInstance dss;  // Mainnet DSS

    /**********************************************************************************************/
    /*** ALM system and allocation system deployments                                           ***/
    /**********************************************************************************************/

    AccessControls         accessControls;
    ALMProxy               almProxy;
    IMainnetControllerFull mainnetController;
    Parameters             parameters;
    RateLimits             rateLimits;

    address buffer;
    address vault;

    /**********************************************************************************************/
    /*** Cached mainnet state variables                                                         ***/
    /**********************************************************************************************/

    uint256 DAI_BAL_PSM;
    uint256 DAI_SUPPLY;
    uint256 USDC_BAL_PSM;
    uint256 USDC_SUPPLY;
    uint256 USDS_SUPPLY;
    uint256 USDS_BAL_SUSDS;
    uint256 VAT_DAI_USDS_JOIN;

    /**********************************************************************************************/
    /*** Test setup                                                                             ***/
    /**********************************************************************************************/

    function setUp() public virtual {

        /*** Step 1: Set up environment, cast addresses ***/

        getChain("mainnet").createSelectFork(_getBlock());

        dss = MCD.loadFromChainlog(LOG);

        USDS_JOIN = IChainlogLike(LOG).getAddress("USDS_JOIN");
        POCKET    = IChainlogLike(LOG).getAddress("MCD_LITE_PSM_USDC_A_POCKET");

        DAI_BAL_PSM       = dai.balanceOf(Ethereum.PSM);
        DAI_SUPPLY        = dai.totalSupply();
        USDC_BAL_PSM      = usdc.balanceOf(POCKET);
        USDC_SUPPLY       = usdc.totalSupply();
        USDS_SUPPLY       = usds.totalSupply();
        USDS_BAL_SUSDS    = usds.balanceOf(Ethereum.SUSDS);
        VAT_DAI_USDS_JOIN = dss.vat.dai(USDS_JOIN);

        /*** Step 2: Deploy and configure allocation system ***/

        AllocatorSharedInstance memory sharedInst
            = AllocatorDeploy.deployShared(address(this), Ethereum.PAUSE_PROXY);

        AllocatorIlkInstance memory ilkInst = AllocatorDeploy.deployIlk({
            deployer : address(this),
            owner    : Ethereum.PAUSE_PROXY,
            roles    : sharedInst.roles,
            ilk      : ilk,
            usdsJoin : USDS_JOIN
        });

        AllocatorIlkConfig memory ilkConfig = AllocatorIlkConfig({
            ilk            : ilk,
            duty           : EIGHT_PCT_APY,
            maxLine        : 100_000_000 * RAD,
            gap            : 10_000_000 * RAD,
            ttl            : 6 hours,
            allocatorProxy : Ethereum.SPARK_PROXY,
            ilkRegistry    : IChainlogLike(LOG).getAddress("ILK_REGISTRY")
        });

        vm.startPrank(Ethereum.PAUSE_PROXY);
        AllocatorInit.initShared(dss, sharedInst);
        AllocatorInit.initIlk(dss, sharedInst, ilkInst, ilkConfig);
        vm.stopPrank();

        buffer = ilkInst.buffer;
        vault  = ilkInst.vault;

        /*** Step 3: Deploy ALM system ***/

        almProxy   = new ALMProxy(Ethereum.SPARK_PROXY);
        rateLimits = new RateLimits(Ethereum.SPARK_PROXY);

        accessControls = new AccessControls(Ethereum.SPARK_PROXY);
        parameters     = new Parameters(Ethereum.SPARK_PROXY);

        mainnetController = IMainnetControllerFull(payable(new MainnetController({
            admin_          : Ethereum.SPARK_PROXY,
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits),
            accessControls_ : address(accessControls),
            parameters_     : address(parameters),
            vault_          : ilkInst.vault,
            psm_            : Ethereum.PSM,
            daiUsds_        : Ethereum.DAI_USDS,
            cctp_           : CCTP_MESSENGER
        })));

        CONTROLLER = almProxy.CONTROLLER();
        FREEZER    = mainnetController.FREEZER();
        RELAYER    = mainnetController.RELAYER();

        vm.startPrank(Ethereum.SPARK_PROXY);

        parameters.grantRole(parameters.CONTROLLER_ROLE(), address(mainnetController));
        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), backstopRelayer);

        // Facet wiring

        _wireDAIUSDSFacet();
        _wireTransferAssetFacet();
        _wireUSDEFacet();
        _wireUSDSFacet();
        _wireWEETHFacet();
        _wireWrapProxyETHFacet();
        _wireWSTETHFacet();

        vm.stopPrank();

        address[] memory relayers = new address[](2);
        relayers[0] = relayer;
        relayers[1] = backstopRelayer;

        MintRecipient[] memory mintRecipients = new MintRecipient[](1);

        mintRecipients[0] = MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : bytes32(uint256(uint160(makeAddr("baseAlmProxy"))))
        });

        // Step 4: Initialize through Sky governance (Sky spell payload)

        _pauseProxyInitAlmSystem(Ethereum.PSM, address(almProxy));

        // Step 5: Initialize through Spark governance (Spark spell payload)

        vm.startPrank(Ethereum.SPARK_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(),                address(mainnetController));
        mainnetController.grantRole(mainnetController.FREEZER(), freezer);
        rateLimits.grantRole(rateLimits.CONTROLLER(),            address(mainnetController));

        for (uint256 i; i < relayers.length; ++i) {
            mainnetController.grantRole(mainnetController.RELAYER(), relayers[i]);
        }

        for (uint256 i; i < mintRecipients.length; ++i) {
            mainnetController.setMintRecipient(mintRecipients[i].domain, mintRecipients[i].mintRecipient);
        }

        IVaultLike(ilkInst.vault).rely(address(almProxy));
        IBufferLike(IVaultLike(ilkInst.vault).buffer()).approve(address(usds), address(almProxy), type(uint256).max);

        uint256 usdsMaxAmount = 5_000_000e18;
        uint256 usdsSlope     = uint256(1_000_000e18) / 4 hours;
        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;

        bytes32 domainKeyBase = RateLimitHelpers.makeUint32Key(
            mainnetController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE
        );

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_MINT(),    usdsMaxAmount, usdsSlope);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_TO_USDC(), usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDC_TO_CCTP(), usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(domainKeyBase,                          usdcMaxAmount, usdcSlope);

        vm.stopPrank();

        /*** Step 6: Label addresses ***/

        vm.label(buffer,         "buffer");
        vm.label(Ethereum.SUSDS, "susds");
        vm.label(address(usdc),  "usdc");
        vm.label(address(usds),  "usds");
        vm.label(vault,          "vault");
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 20917850; //  October 7, 2024
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _setControllerEntered() internal virtual {
        vm.store(address(mainnetController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        _assertReentrancyGuardWrittenToTwice(address(mainnetController));
    }

    function _assertReentrancyGuardWrittenToTwice(address controller) internal {
        ( , bytes32[] memory writeSlots ) = vm.accesses(controller);

        uint256 count = 0;

        for (uint256 i = 0; i < writeSlots.length; ++i) {
            if (writeSlots[i] != _REENTRANCY_GUARD_SLOT) continue;

            ++count;
        }

        assertEq(count, 2);
        assertEq(vm.load(controller, _REENTRANCY_GUARD_SLOT), _REENTRANCY_GUARD_NOT_ENTERED);
    }

    function _pauseProxyInitAlmSystem(address psm, address almProxy) internal {
        vm.prank(Ethereum.PAUSE_PROXY);
        IPSMLike(psm).kiss(almProxy);  // To allow using no fee functionality
    }

    /**********************************************************************************************/
    /*** Facet wiring helpers.                                                                  ***/
    /**********************************************************************************************/

    function _wireDAIUSDSFacet() internal {
        address daiUSDSFacet = address(new DAIUSDSFacet({
            dai_     : Ethereum.DAI,
            daiUSDS_ : Ethereum.DAI_USDS,
            usds_    : Ethereum.USDS
        }));

        vm.label(daiUSDSFacet, "DAIUSDSFacet");

        // "Controller.swapUSDSToDAI()" -> "DAIUSDSFacet.swapUSDSToDAI()"
        mainnetController.setFacet(
            IMainnetControllerFull.swapUSDSToDAI.selector,
            daiUSDSFacet,
            IDAIUSDSFacet.swapUSDSToDAI.selector
        );

        // "Controller.swapDAIToUSDS()" -> "DAIUSDSFacet.swapDAIToUSDS()"
        mainnetController.setFacet(
            IMainnetControllerFull.swapDAIToUSDS.selector,
            daiUSDSFacet,
            IDAIUSDSFacet.swapDAIToUSDS.selector
        );
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        // "Controller.transferAsset()" -> "TransferAssetFacet.transfer()"
        mainnetController.setFacet(
            IMainnetControllerFull.transferAsset.selector,
            transferAssetFacet,
            ITransferAssetFacet.transfer.selector
        );

        // "Controller.LIMIT_ASSET_TRANSFER()" -> "TransferAssetFacet.LIMIT_TRANSFER()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_ASSET_TRANSFER.selector,
            transferAssetFacet,
            ITransferAssetFacet.LIMIT_TRANSFER.selector
        );
    }

    function _wireWEETHFacet() internal {
        address weethFacet = address(new WEETHFacet(Ethereum.WETH, Ethereum.WEETH));

        vm.label(weethFacet, "WEETHFacet");

        // "Controller.depositToWeETH()" -> "WEETHFacet.deposit()"
        mainnetController.setFacet(
            IMainnetControllerFull.depositToWeETH.selector,
            weethFacet,
            IWEETHFacet.deposit.selector
        );

        // "Controller.requestWithdrawFromWeETH()" -> "WEETHFacet.requestWithdraw()"
        mainnetController.setFacet(
            IMainnetControllerFull.requestWithdrawFromWeETH.selector,
            weethFacet,
            IWEETHFacet.requestWithdraw.selector
        );

        // "Controller.claimWithdrawalFromWeETH()" -> "WEETHFacet.claimWithdrawal()"
        mainnetController.setFacet(
            IMainnetControllerFull.claimWithdrawalFromWeETH.selector,
            weethFacet,
            IWEETHFacet.claimWithdrawal.selector
        );

        // "Controller.LIMIT_WEETH_DEPOSIT()" -> "WEETHFacet.LIMIT_DEPOSIT()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_WEETH_DEPOSIT.selector,
            weethFacet,
            IWEETHFacet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_WEETH_REQUEST_WITHDRAW()" -> "WEETHFacet.LIMIT_REQUEST_WITHDRAW()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_WEETH_REQUEST_WITHDRAW.selector,
            weethFacet,
            IWEETHFacet.LIMIT_REQUEST_WITHDRAW.selector
        );
    }

    function _wireWSTETHFacet() internal {
        address wstethFacet = address(new WSTETHFacet(
            Ethereum.WETH,
            Ethereum.WSTETH_WITHDRAW_QUEUE,
            Ethereum.WSTETH
        ));

        vm.label(wstethFacet, "WSTETHFacet");

        // "Controller.depositToWstETH()" -> "WSTETHFacet.deposit()"
        mainnetController.setFacet(
            IMainnetControllerFull.depositToWstETH.selector,
            wstethFacet,
            IWSTETHFacet.deposit.selector
        );

        // "Controller.requestWithdrawFromWstETH()" -> "WSTETHFacet.requestWithdraw()"
        mainnetController.setFacet(
            IMainnetControllerFull.requestWithdrawFromWstETH.selector,
            wstethFacet,
            IWSTETHFacet.requestWithdraw.selector
        );

        // "Controller.claimWithdrawalFromWstETH()" -> "WSTETHFacet.claimWithdrawal()"
        mainnetController.setFacet(
            IMainnetControllerFull.claimWithdrawalFromWstETH.selector,
            wstethFacet,
            IWSTETHFacet.claimWithdrawal.selector
        );

        // "Controller.LIMIT_WSTETH_DEPOSIT()" -> "WSTETHFacet.LIMIT_DEPOSIT()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_WSTETH_DEPOSIT.selector,
            wstethFacet,
            IWSTETHFacet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_WSTETH_REQUEST_WITHDRAW()" -> "WSTETHFacet.LIMIT_REQUEST_WITHDRAW()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_WSTETH_REQUEST_WITHDRAW.selector,
            wstethFacet,
            IWSTETHFacet.LIMIT_REQUEST_WITHDRAW.selector
        );
    }

    function _wireUSDEFacet() internal {
        address usdeFacet = address(new USDEFacet(
            ETHENA_MINTER,
            address(susde),
            address(usdc),
            address(usde)
        ));

        vm.label(usdeFacet, "USDEFacet");

        // "Controller.cooldownAssetsSUSDe()" -> "IUSDEFacet.cooldownAssets()"
        mainnetController.setFacet(
            IMainnetControllerFull.cooldownAssetsSUSDe.selector,
            usdeFacet,
            IUSDEFacet.cooldownAssets.selector
        );

        // "Controller.cooldownSharesSUSDe()" -> "IUSDEFacet.cooldownShares()"
        mainnetController.setFacet(
            IMainnetControllerFull.cooldownSharesSUSDe.selector,
            usdeFacet,
            IUSDEFacet.cooldownShares.selector
        );

        // "Controller.prepareUSDeMint()" -> "IUSDEFacet.prepareMint()"
        mainnetController.setFacet(
            IMainnetControllerFull.prepareUSDeMint.selector,
            usdeFacet,
            IUSDEFacet.prepareMint.selector
        );

        // "Controller.prepareUSDeBurn()" -> "IUSDEFacet.prepareBurn()"
        mainnetController.setFacet(
            IMainnetControllerFull.prepareUSDeBurn.selector,
            usdeFacet,
            IUSDEFacet.prepareBurn.selector
        );

        // "Controller.removeDelegatedSigner()" -> "IUSDEFacet.removeDelegatedSigner()"
        mainnetController.setFacet(
            IMainnetControllerFull.removeDelegatedSigner.selector,
            usdeFacet,
            IUSDEFacet.removeDelegatedSigner.selector
        );

        // "Controller.setDelegatedSigner()" -> "IUSDEFacet.setDelegatedSigner()"
        mainnetController.setFacet(
            IMainnetControllerFull.setDelegatedSigner.selector,
            usdeFacet,
            IUSDEFacet.setDelegatedSigner.selector
        );

        // "Controller.unstakeSUSDe()" -> "IUSDEFacet.unstakeSUSDE()"
        mainnetController.setFacet(
            IMainnetControllerFull.unstakeSUSDe.selector,
            usdeFacet,
            IUSDEFacet.unstakeSUSDE.selector
        );

        // "Controller.LIMIT_USDE_BURN()" -> "IUSDEFacet.LIMIT_USDE_BURN()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_USDE_BURN.selector,
            usdeFacet,
            IUSDEFacet.LIMIT_USDE_BURN.selector
        );

        // "Controller.LIMIT_USDE_MINT()" -> "IUSDEFacet.LIMIT_USDE_MINT()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_USDE_MINT.selector,
            usdeFacet,
            IUSDEFacet.LIMIT_USDE_MINT.selector
        );

        // "Controller.LIMIT_SUSDE_COOLDOWN()" -> "IUSDEFacet.LIMIT_SUSDE_COOLDOWN()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_SUSDE_COOLDOWN.selector,
            usdeFacet,
            IUSDEFacet.LIMIT_SUSDE_COOLDOWN.selector
        );
    }

    function _wireWrapProxyETHFacet() internal {
        address wrapProxyETHFacet = address(new WrapProxyETHFacet(Ethereum.WETH));

        vm.label(wrapProxyETHFacet, "WrapProxyETHFacet");

        // "Controller.wrapAllProxyETH()" -> "WrapProxyETHFacet.wrapAll()"
        mainnetController.setFacet(
            IMainnetControllerFull.wrapAllProxyETH.selector,
            wrapProxyETHFacet,
            IWrapProxyETHFacet.wrapAll.selector
        );
    }

    function _wireUSDSFacet() internal {
        address usdsFacet = address(new USDSFacet(vault, address(usds)));

        vm.label(usdsFacet, "USDSFacet");

        // "Controller.mintUSDS()" -> "USDSFacet.mint()"
        mainnetController.setFacet(
            IMainnetControllerFull.mintUSDS.selector,
            usdsFacet,
            IUSDSFacet.mint.selector
        );

        // "Controller.burnUSDS()" -> "USDSFacet.burn()"
        mainnetController.setFacet(
            IMainnetControllerFull.burnUSDS.selector,
            usdsFacet,
            IUSDSFacet.burn.selector
        );

        // "Controller.LIMIT_USDS_MINT()" -> "USDSFacet.LIMIT_MINT()"
        mainnetController.setFacet(
            IMainnetControllerFull.LIMIT_USDS_MINT.selector,
            usdsFacet,
            IUSDSFacet.LIMIT_MINT.selector
        );
    }

}
