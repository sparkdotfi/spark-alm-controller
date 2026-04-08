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

import { Ethereum as GroveEthereum } from "../../lib/grove-address-registry/src/Ethereum.sol";

import { CCTPForwarder } from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";
import { DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { IAaveFacet }          from "../../src/facets/aave/IAaveFacet.sol";
import { ICCTPFacet }          from "../../src/facets/cctp/ICCTPFacet.sol";
import { ICentrifugeFacet }    from "../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { ICurveFacet }         from "../../src/facets/curve/ICurveFacet.sol";
import { IDAIUSDSFacet }       from "../../src/facets/dai-usds/IDAIUSDSFacet.sol";
import { IERC4626Facet }       from "../../src/facets/erc4626/IERC4626Facet.sol";
import { IERC7540Facet }       from "../../src/facets/erc7540/IERC7540Facet.sol";
import { IFarmFacet }          from "../../src/facets/farm/IFarmFacet.sol";
import { ILayerZeroFacet }     from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { IMapleFacet }         from "../../src/facets/maple/IMapleFacet.sol";
import { IMerklFacet }         from "../../src/facets/merkl/IMerklFacet.sol";
import { IOTCFacet }           from "../../src/facets/otc/IOTCFacet.sol";
import { IPendleFacet }        from "../../src/facets/pendle/IPendleFacet.sol";
import { IPSMFacet }           from "../../src/facets/psm/IPSMFacet.sol";
import { ISparkVaultFacet }    from "../../src/facets/spark-vault/ISparkVaultFacet.sol";
import { ISuperstateFacet }    from "../../src/facets/superstate/ISuperstateFacet.sol";
import { ITransferAssetFacet } from "../../src/facets/transfer-asset/ITransferAssetFacet.sol";
import { IUniswapV3Facet }     from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";
import { IUniswapV4Facet }     from "../../src/facets/uniswap-v4/IUniswapV4Facet.sol";
import { IUSDEFacet }          from "../../src/facets/usde/IUSDEFacet.sol";
import { IUSDSFacet }          from "../../src/facets/usds/IUSDSFacet.sol";
import { IWEETHFacet }         from "../../src/facets/weeth/IWEETHFacet.sol";
import { IWrapProxyETHFacet }  from "../../src/facets/wrap-proxy-eth/IWrapProxyETHFacet.sol";
import { IWSTETHFacet }        from "../../src/facets/wsteth/IWSTETHFacet.sol";

import { AaveFacet }          from "../../src/facets/aave/AaveFacet.sol";
import { CCTPFacet }          from "../../src/facets/cctp/CCTPFacet.sol";
import { CentrifugeFacet }    from "../../src/facets/centrifuge/CentrifugeFacet.sol";
import { CurveFacet }         from "../../src/facets/curve/CurveFacet.sol";
import { DAIUSDSFacet }       from "../../src/facets/dai-usds/DAIUSDSFacet.sol";
import { ERC4626Facet }       from "../../src/facets/erc4626/ERC4626Facet.sol";
import { ERC7540Facet }       from "../../src/facets/erc7540/ERC7540Facet.sol";
import { FarmFacet }          from "../../src/facets/farm/FarmFacet.sol";
import { LayerZeroFacet }     from "../../src/facets/layer-zero/LayerZeroFacet.sol";
import { MapleFacet }         from "../../src/facets/maple/MapleFacet.sol";
import { MerklFacet }         from "../../src/facets/merkl/MerklFacet.sol";
import { OTCFacet }           from "../../src/facets/otc/OTCFacet.sol";
import { PendleFacet }        from "../../src/facets/pendle/PendleFacet.sol";
import { PSMFacet }           from "../../src/facets/psm/PSMFacet.sol";
import { SparkVaultFacet }    from "../../src/facets/spark-vault/SparkVaultFacet.sol";
import { SuperstateFacet }    from "../../src/facets/superstate/SuperstateFacet.sol";
import { TransferAssetFacet } from "../../src/facets/transfer-asset/TransferAssetFacet.sol";
import { UniswapV3Facet }     from "../../src/facets/uniswap-v3/UniswapV3Facet.sol";
import { UniswapV4Facet }     from "../../src/facets/uniswap-v4/UniswapV4Facet.sol";
import { USDEFacet }          from "../../src/facets/usde/USDEFacet.sol";
import { USDSFacet }          from "../../src/facets/usds/USDSFacet.sol";
import { WEETHFacet }         from "../../src/facets/weeth/WEETHFacet.sol";
import { WrapProxyETHFacet }  from "../../src/facets/wrap-proxy-eth/WrapProxyETHFacet.sol";
import { WSTETHFacet }        from "../../src/facets/wsteth/WSTETHFacet.sol";

import { makeUint32Key } from "../../src/libraries/RateLimitHelpers.sol";

import { IController } from "../../src/interfaces/IController.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { PAUFactory }     from "../../src/PAUFactory.sol";
import { RateLimits }     from "../../src/RateLimits.sol";

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

    function silo() external view returns (address);

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

    address internal constant UNISWAP_V3_ROUTER           = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant ilk = "ILK-A";

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant RELAYER_ROLE       = keccak256("RELAYER");

    bytes32 constant PSM_ILK = 0x4c4954452d50534d2d555344432d410000000000000000000000000000000000;

    uint256 constant INK           = 1e12 * 1e18;  // Ink initialization amount
    uint256 constant SEVEN_PCT_APY = 1.000000002145441671308778766e27;  // 7% APY (current DSR)
    uint256 constant EIGHT_PCT_APY = 1.000000002440418608258400030e27;  // 8% APY (current DSR + 1%)

    // NOTE: From https://docs.uniswap.org/contracts/v4/deployments (Ethereum Mainnet).
    address internal constant _PERMIT2                     = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _UNISWAP_V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _UNISWAP_V4_ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    address freezer = Ethereum.ALM_FREEZER_MULTISIG;
    address relayer = Ethereum.ALM_RELAYER_MULTISIG;

    address backstopRelayer = makeAddr("backstopRelayer");  // TODO: Replace with real backstop

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
    RateLimits             rateLimits;
    PAUFactory             factory;

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

        factory = new PAUFactory(Ethereum.SPARK_PROXY, Ethereum.SPARK_PROXY);

        mainnetController = IMainnetControllerFull(payable(new Controller({
            accessControls_ : address(accessControls),
            factory_        : address(factory),
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits)
        })));

        vm.startPrank(Ethereum.SPARK_PROXY);

        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), backstopRelayer);

        almProxy.grantRole(almProxy.CONTROLLER(), address(mainnetController));

        rateLimits.grantRole(rateLimits.CONTROLLER(), address(mainnetController));

        // Facet wiring
        _wireAaveFacet();
        _wireCCTPFacet();
        _wireCentrifugeFacet();
        _wireCurveFacet();
        _wireDAIUSDSFacet();
        _wireERC4626Facet();
        _wireERC7540Facet();
        _wireFarmFacet();
        _wireLayerZeroFacet();
        _wireMapleFacet();
        _wireMerklFacet();
        _wireOTCFacet();
        _wirePendleFacet();
        _wirePSMFacet();
        _wireSparkVaultFacet();
        _wireSuperstateFacet();
        _wireTransferAssetFacet();
        _wireUniswapV3Facet();
        _wireUniswapV4Facet();
        _wireUSDEFacet();
        _wireUSDSFacet();
        _wireWEETHFacet();
        _wireWrapProxyETHFacet();
        _wireWSTETHFacet();

        vm.stopPrank();

        MintRecipient[] memory mintRecipients = new MintRecipient[](1);

        mintRecipients[0] = MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : bytes32(uint256(uint160(makeAddr("baseAlmProxy"))))
        });

        // Step 4: Initialize through Sky governance (Sky spell payload)

        _pauseProxyInitAlmSystem(Ethereum.PSM, address(almProxy));

        // Step 5: Initialize through Spark governance (Spark spell payload)

        vm.startPrank(Ethereum.SPARK_PROXY);

        for (uint256 i; i < mintRecipients.length; ++i) {
            mainnetController.setCCTPMintRecipient(mintRecipients[i].domain, mintRecipients[i].mintRecipient);
        }

        IVaultLike(ilkInst.vault).rely(address(almProxy));
        IBufferLike(IVaultLike(ilkInst.vault).buffer()).approve(address(usds), address(almProxy), type(uint256).max);

        uint256 usdsMaxAmount = 5_000_000e18;
        uint256 usdsSlope     = uint256(1_000_000e18) / 4 hours;
        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;

        bytes32 domainKeyBase = makeUint32Key(
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
    function _getBlock() internal pure virtual returns (uint256) {
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
    /*** Facet wiring helpers                                                                   ***/
    /**********************************************************************************************/

    function _wireCentrifugeFacet() internal {
        // NOTE: We are NOT wiring DEPOSIT, REDEEM keys, as they already wired in _wireERC7540Facet.

        address centrifugeFacet = address(new CentrifugeFacet());

        vm.label(centrifugeFacet, "CentrifugeFacet");

        factory.setValidFacet(centrifugeFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](8);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setCentrifugeRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.cancelCentrifugeDepositRequest.selector,
            ICentrifugeFacet.cancelDepositRequest.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.claimCentrifugeCancelDepositRequest.selector,
            ICentrifugeFacet.claimCancelDepositRequest.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.cancelCentrifugeRedeemRequest.selector,
            ICentrifugeFacet.cancelRedeemRequest.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.claimCentrifugeCancelRedeemRequest.selector,
            ICentrifugeFacet.claimCancelRedeemRequest.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.transferSharesCentrifuge.selector,
            ICentrifugeFacet.transferShares.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.LIMIT_CENTRIFUGE_TRANSFER.selector,
            ICentrifugeFacet.LIMIT_TRANSFER.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.getCentrifugeRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        mainnetController.addWires(centrifugeFacet, wires);
    }

    function _wireCurveFacet() internal {
        address curveFacet = address(new CurveFacet());

        vm.label(curveFacet, "CurveFacet");

        factory.setValidFacet(curveFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](8);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setCurveMaxSlippage.selector,
            ICurveFacet.setMaxSlippage.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.getCurveMaxSlippage.selector,
            ICurveFacet.getMaxSlippage.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.swapCurve.selector,
            ICurveFacet.swap.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.addLiquidityCurve.selector,
            ICurveFacet.addLiquidity.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.removeLiquidityCurve.selector,
            ICurveFacet.removeLiquidity.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.LIMIT_CURVE_DEPOSIT.selector,
            ICurveFacet.LIMIT_DEPOSIT.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.LIMIT_CURVE_SWAP.selector,
            ICurveFacet.LIMIT_SWAP.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.LIMIT_CURVE_WITHDRAW.selector,
            ICurveFacet.LIMIT_WITHDRAW.selector
        );

        mainnetController.addWires(curveFacet, wires);
    }

    function _wireCCTPFacet() internal {
        address cctpFacet = address(new CCTPFacet(CCTP_MESSENGER, Ethereum.USDC));

        vm.label(cctpFacet, "CCTPFacet");

        factory.setValidFacet(cctpFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](8);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setCCTPMaxFeeCap.selector,
            ICCTPFacet.setMaxFeeCap.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.setCCTPMintRecipient.selector,
            ICCTPFacet.setMintRecipient.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.getCCTPMaxFeeCap.selector,
            ICCTPFacet.maxFeeCap.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.getCCTPMintRecipient.selector,
            ICCTPFacet.getMintRecipient.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.transferUSDCToCCTP.selector,
            ICCTPFacet.transfer.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.transferUSDCToCCTPWithFee.selector,
            ICCTPFacet.transferWithFee.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.LIMIT_USDC_TO_CCTP.selector,
            ICCTPFacet.LIMIT_TO_CCTP.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.LIMIT_USDC_TO_DOMAIN.selector,
            ICCTPFacet.LIMIT_TO_DOMAIN.selector
        );

        mainnetController.addWires(cctpFacet, wires);
    }

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        vm.label(aaveFacet, "AaveFacet");

        factory.setValidFacet(aaveFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](6);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setAaveMaxSlippage.selector,
            IAaveFacet.setMaxSlippage.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.getAaveMaxSlippage.selector,
            IAaveFacet.getMaxSlippage.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.depositAave.selector,
            IAaveFacet.deposit.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.withdrawAave.selector,
            IAaveFacet.withdraw.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.LIMIT_AAVE_DEPOSIT.selector,
            IAaveFacet.LIMIT_DEPOSIT.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.LIMIT_AAVE_WITHDRAW.selector,
            IAaveFacet.LIMIT_WITHDRAW.selector
        );

        mainnetController.addWires(aaveFacet, wires);
    }

    function _wireDAIUSDSFacet() internal {
        address daiUSDSFacet = address(new DAIUSDSFacet({
            dai_     : Ethereum.DAI,
            daiUSDS_ : Ethereum.DAI_USDS,
            usds_    : Ethereum.USDS
        }));

        vm.label(daiUSDSFacet, "DAIUSDSFacet");

        factory.setValidFacet(daiUSDSFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IMainnetControllerFull.swapUSDSToDAI.selector,
            IDAIUSDSFacet.swapUSDSToDAI.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.swapDAIToUSDS.selector,
            IDAIUSDSFacet.swapDAIToUSDS.selector
        );

        mainnetController.addWires(daiUSDSFacet, wires);
    }

    function _wireMerklFacet() internal {
        address merklFacet = address(new MerklFacet(GroveEthereum.MERKL_DISTRIBUTOR));

        vm.label(merklFacet, "MerklFacet");

        factory.setValidFacet(merklFacet, true);

        mainnetController.addWire(
            merklFacet,
            IController.Wire(
                IMainnetControllerFull.toggleOperatorMerkl.selector,
                IMerklFacet.toggleOperator.selector
            )
        );
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        factory.setValidFacet(erc4626Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](8);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setMaxExchangeRate.selector,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.maxExchangeRates.selector,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.depositERC4626.selector,
            IERC4626Facet.deposit.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.withdrawERC4626.selector,
            IERC4626Facet.withdraw.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.redeemERC4626.selector,
            IERC4626Facet.redeem.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.LIMIT_4626_DEPOSIT.selector,
            IERC4626Facet.LIMIT_DEPOSIT.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.LIMIT_4626_WITHDRAW.selector,
            IERC4626Facet.LIMIT_WITHDRAW.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.EXCHANGE_RATE_PRECISION.selector,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );

        mainnetController.addWires(erc4626Facet, wires);
    }

    function _wireERC7540Facet() internal {
        address erc7540Facet = address(new ERC7540Facet());

        vm.label(erc7540Facet, "ERC7540Facet");

        factory.setValidFacet(erc7540Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](6);

        wires[0] = IController.Wire(
            IMainnetControllerFull.requestDepositERC7540.selector,
            IERC7540Facet.requestDeposit.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.claimDepositERC7540.selector,
            IERC7540Facet.claimDeposit.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.requestRedeemERC7540.selector,
            IERC7540Facet.requestRedeem.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.claimRedeemERC7540.selector,
            IERC7540Facet.claimRedeem.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.LIMIT_7540_DEPOSIT.selector,
            IERC7540Facet.LIMIT_DEPOSIT.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.LIMIT_7540_REDEEM.selector,
            IERC7540Facet.LIMIT_REDEEM.selector
        );

        mainnetController.addWires(erc7540Facet, wires);
    }

    function _wireFarmFacet() internal {
        address farmFacet = address(new FarmFacet());

        vm.label(farmFacet, "FarmFacet");

        factory.setValidFacet(farmFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](4);

        wires[0] = IController.Wire(
            IMainnetControllerFull.depositToFarm.selector,
            IFarmFacet.deposit.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.withdrawFromFarm.selector,
            IFarmFacet.withdraw.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.LIMIT_FARM_DEPOSIT.selector,
            IFarmFacet.LIMIT_DEPOSIT.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.LIMIT_FARM_WITHDRAW.selector,
            IFarmFacet.LIMIT_WITHDRAW.selector
        );

        mainnetController.addWires(farmFacet, wires);
    }

    function _wireLayerZeroFacet() internal {
        address layerZeroFacet = address(new LayerZeroFacet());

        vm.label(layerZeroFacet, "LayerZeroFacet");

        factory.setValidFacet(layerZeroFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](4);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setLayerZeroRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.transferTokenLayerZero.selector,
            ILayerZeroFacet.transfer.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.LIMIT_LAYERZERO_TRANSFER.selector,
            ILayerZeroFacet.LIMIT_TRANSFER.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.layerZeroRecipients.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        mainnetController.addWires(layerZeroFacet, wires);
    }

    function _wireOTCFacet() internal {
        address otcFacet = address(new OTCFacet());

        vm.label(otcFacet, "OTCFacet");

        factory.setValidFacet(otcFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](11);

        wires[0] = IController.Wire(
            IMainnetControllerFull.setOTCMaxSlippage.selector,
            IOTCFacet.setMaxSlippage.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.setOTCBuffer.selector,
            IOTCFacet.setBuffer.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.setOTCRechargeRate.selector,
            IOTCFacet.setRechargeRate.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.setOTCWhitelistedAsset.selector,
            IOTCFacet.setIsWhitelisted.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.otcSend.selector,
            IOTCFacet.send.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.otcClaim.selector,
            IOTCFacet.claim.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.LIMIT_OTC_SWAP.selector,
            IOTCFacet.LIMIT_SWAP.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.getOtcClaimWithRecharge.selector,
            IOTCFacet.getClaimWithRecharge.selector
        );

        wires[8] = IController.Wire(
            IMainnetControllerFull.isOtcSwapReady.selector,
            IOTCFacet.isSwapReady.selector
        );

        wires[9] = IController.Wire(
            IMainnetControllerFull.otcs.selector,
            IOTCFacet.getState.selector
        );

        wires[10] = IController.Wire(
            IMainnetControllerFull.otcWhitelistedAssets.selector,
            IOTCFacet.getIsWhitelisted.selector
        );

        mainnetController.addWires(otcFacet, wires);
    }

    function _wireSparkVaultFacet() internal {
        address sparkVaultFacet = address(new SparkVaultFacet());

        vm.label(sparkVaultFacet, "SparkVaultFacet");

        factory.setValidFacet(sparkVaultFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IMainnetControllerFull.takeFromSparkVault.selector,
            ISparkVaultFacet.take.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.LIMIT_SPARK_VAULT_TAKE.selector,
            ISparkVaultFacet.LIMIT_TAKE.selector
        );

        mainnetController.addWires(sparkVaultFacet, wires);
    }

    function _wirePSMFacet() internal {
        address psmFacet = address(new PSMFacet(
            Ethereum.DAI,
            Ethereum.DAI_USDS,
            Ethereum.PSM,
            Ethereum.USDC,
            Ethereum.USDS
        ));

        vm.label(psmFacet, "PSMFacet");

        factory.setValidFacet(psmFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](4);

        wires[0] = IController.Wire(
            IMainnetControllerFull.swapUSDSToUSDC.selector,
            IPSMFacet.swapUSDSToUSDC.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.swapUSDCToUSDS.selector,
            IPSMFacet.swapUSDCToUSDS.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.psmTo18ConversionFactor.selector,
            IPSMFacet.to18ConversionFactor.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.LIMIT_USDS_TO_USDC.selector,
            IPSMFacet.LIMIT_USDS_TO_USDC.selector
        );

        mainnetController.addWires(psmFacet, wires);
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        factory.setValidFacet(transferAssetFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IMainnetControllerFull.transferAsset.selector,
            ITransferAssetFacet.transfer.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.LIMIT_ASSET_TRANSFER.selector,
            ITransferAssetFacet.LIMIT_TRANSFER.selector
        );

        mainnetController.addWires(transferAssetFacet, wires);
    }

    function _wireMapleFacet() internal {
        address mapleFacet = address(new MapleFacet());

        vm.label(mapleFacet, "MapleFacet");

        factory.setValidFacet(mapleFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](3);

        wires[0] = IController.Wire(
            IMainnetControllerFull.requestMapleRedemption.selector,
            IMapleFacet.requestRedemption.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.cancelMapleRedemption.selector,
            IMapleFacet.cancelRedemption.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.LIMIT_MAPLE_REDEEM.selector,
            IMapleFacet.LIMIT_REDEEM.selector
        );

        mainnetController.addWires(mapleFacet, wires);
    }

    function _wirePendleFacet() internal {
        address pendleFacet = address(new PendleFacet(GroveEthereum.PENDLE_ROUTER));

        vm.label(pendleFacet, "PendleFacet");

        factory.setValidFacet(pendleFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IMainnetControllerFull.redeemPendlePT.selector,
            IPendleFacet.redeem.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.LIMIT_PENDLE_PT_REDEEM.selector,
            IPendleFacet.LIMIT_REDEEM.selector
        );

        mainnetController.addWires(pendleFacet, wires);
    }

    function _wireSuperstateFacet() internal {
        address superstateFacet = address(new SuperstateFacet(Ethereum.USDC, Ethereum.USTB));

        vm.label(superstateFacet, "SuperstateFacet");

        factory.setValidFacet(superstateFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IMainnetControllerFull.subscribeSuperstate.selector,
            ISuperstateFacet.subscribe.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.LIMIT_SUPERSTATE_SUBSCRIBE.selector,
            ISuperstateFacet.LIMIT_SUBSCRIBE.selector
        );

        mainnetController.addWires(superstateFacet, wires);
    }

    function _wireWEETHFacet() internal {
        address weethFacet = address(new WEETHFacet(Ethereum.WETH, Ethereum.WEETH));

        vm.label(weethFacet, "WEETHFacet");

        factory.setValidFacet(weethFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](5);

        wires[0] = IController.Wire(
            IMainnetControllerFull.depositToWeETH.selector,
            IWEETHFacet.deposit.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.requestWithdrawFromWeETH.selector,
            IWEETHFacet.requestWithdraw.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.claimWithdrawalFromWeETH.selector,
            IWEETHFacet.claimWithdrawal.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.LIMIT_WEETH_DEPOSIT.selector,
            IWEETHFacet.LIMIT_DEPOSIT.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.LIMIT_WEETH_REQUEST_WITHDRAW.selector,
            IWEETHFacet.LIMIT_REQUEST_WITHDRAW.selector
        );

        mainnetController.addWires(weethFacet, wires);
    }

    function _wireWSTETHFacet() internal {
        address wstethFacet = address(new WSTETHFacet(
            Ethereum.WETH,
            Ethereum.WSTETH_WITHDRAW_QUEUE,
            Ethereum.WSTETH
        ));

        vm.label(wstethFacet, "WSTETHFacet");

        factory.setValidFacet(wstethFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](5);

        wires[0] = IController.Wire(
            IMainnetControllerFull.depositToWstETH.selector,
            IWSTETHFacet.deposit.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.requestWithdrawFromWstETH.selector,
            IWSTETHFacet.requestWithdraw.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.claimWithdrawalFromWstETH.selector,
            IWSTETHFacet.claimWithdrawal.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.LIMIT_WSTETH_DEPOSIT.selector,
            IWSTETHFacet.LIMIT_DEPOSIT.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.LIMIT_WSTETH_REQUEST_WITHDRAW.selector,
            IWSTETHFacet.LIMIT_REQUEST_WITHDRAW.selector
        );

        mainnetController.addWires(wstethFacet, wires);
    }

    function _wireUSDEFacet() internal {
        address usdeFacet = address(new USDEFacet(
            ETHENA_MINTER,
            address(susde),
            address(usdc),
            address(usde)
        ));

        vm.label(usdeFacet, "USDEFacet");

        factory.setValidFacet(usdeFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](10);

        wires[0] = IController.Wire(
            IMainnetControllerFull.cooldownAssetsSUSDe.selector,
            IUSDEFacet.cooldownAssets.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.cooldownSharesSUSDe.selector,
            IUSDEFacet.cooldownShares.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.prepareUSDeMint.selector,
            IUSDEFacet.prepareMint.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.prepareUSDeBurn.selector,
            IUSDEFacet.prepareBurn.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.removeDelegatedSigner.selector,
            IUSDEFacet.removeDelegatedSigner.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.setDelegatedSigner.selector,
            IUSDEFacet.setDelegatedSigner.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.unstakeSUSDe.selector,
            IUSDEFacet.unstakeSUSDE.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.LIMIT_USDE_BURN.selector,
            IUSDEFacet.LIMIT_USDE_BURN.selector
        );

        wires[8] = IController.Wire(
            IMainnetControllerFull.LIMIT_USDE_MINT.selector,
            IUSDEFacet.LIMIT_USDE_MINT.selector
        );

        wires[9] = IController.Wire(
            IMainnetControllerFull.LIMIT_SUSDE_COOLDOWN.selector,
            IUSDEFacet.LIMIT_SUSDE_COOLDOWN.selector
        );

        mainnetController.addWires(usdeFacet, wires);
    }

    function _wireWrapProxyETHFacet() internal {
        address wrapProxyETHFacet = address(new WrapProxyETHFacet(Ethereum.WETH));

        vm.label(wrapProxyETHFacet, "WrapProxyETHFacet");

        factory.setValidFacet(wrapProxyETHFacet, true);

        mainnetController.addWire(
            wrapProxyETHFacet,
            IController.Wire(
                IMainnetControllerFull.wrapAllProxyETH.selector,
                IWrapProxyETHFacet.wrapAll.selector
            )
        );
    }

    function _wireUSDSFacet() internal {
        address usdsFacet = address(new USDSFacet(vault, address(usds)));

        vm.label(usdsFacet, "USDSFacet");

        factory.setValidFacet(usdsFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](3);

        wires[0] = IController.Wire(
            IMainnetControllerFull.mintUSDS.selector,
            IUSDSFacet.mint.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.burnUSDS.selector,
            IUSDSFacet.burn.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.LIMIT_USDS_MINT.selector,
            IUSDSFacet.LIMIT_MINT.selector
        );

        mainnetController.addWires(usdsFacet, wires);
    }

    function _wireUniswapV4Facet() internal {
        address uniswapV4Facet = address(new UniswapV4Facet({
            permit2_         : _PERMIT2,
            positionManager_ : _UNISWAP_V4_POSITION_MANAGER,
            router_          : _UNISWAP_V4_ROUTER
        }));

        vm.label(uniswapV4Facet, "UniswapV4Facet");

        factory.setValidFacet(uniswapV4Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](11);

        wires[0] = IController.Wire(
            IMainnetControllerFull.decreaseLiquidityUniswapV4.selector,
            IUniswapV4Facet.decreasePosition.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.increaseLiquidityUniswapV4.selector,
            IUniswapV4Facet.increasePosition.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.mintPositionUniswapV4.selector,
            IUniswapV4Facet.mintPosition.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.setUniswapV4MaxSlippage.selector,
            IUniswapV4Facet.setMaxSlippage.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.setUniswapV4TickLimits.selector,
            IUniswapV4Facet.setTickLimits.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.swapUniswapV4.selector,
            IUniswapV4Facet.swap.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.LIMIT_UNISWAP_V4_DEPOSIT.selector,
            IUniswapV4Facet.LIMIT_DEPOSIT.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.LIMIT_UNISWAP_V4_WITHDRAW.selector,
            IUniswapV4Facet.LIMIT_WITHDRAW.selector
        );

        wires[8] = IController.Wire(
            IMainnetControllerFull.LIMIT_UNISWAP_V4_SWAP.selector,
            IUniswapV4Facet.LIMIT_SWAP.selector
        );

        wires[9] = IController.Wire(
            IMainnetControllerFull.uniswapV4MaxSlippages.selector,
            IUniswapV4Facet.getMaxSlippage.selector
        );

        wires[10] = IController.Wire(
            IMainnetControllerFull.uniswapV4TickLimits.selector,
            IUniswapV4Facet.getTickLimits.selector
        );

        mainnetController.addWires(uniswapV4Facet, wires);
    }

    function _wireUniswapV3Facet() internal {
        address uniswapV3Facet = address(new UniswapV3Facet(UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_ROUTER));

        vm.label(uniswapV3Facet, "UniswapV3Facet");

        factory.setValidFacet(uniswapV3Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](15);

        wires[0] = IController.Wire(
            IMainnetControllerFull.addLiquidityUniswapV3.selector,
            IUniswapV3Facet.addLiquidity.selector
        );

        wires[1] = IController.Wire(
            IMainnetControllerFull.removeLiquidityUniswapV3.selector,
            IUniswapV3Facet.removeLiquidity.selector
        );

        wires[2] = IController.Wire(
            IMainnetControllerFull.swapUniswapV3.selector,
            IUniswapV3Facet.swap.selector
        );

        wires[3] = IController.Wire(
            IMainnetControllerFull.setUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[4] = IController.Wire(
            IMainnetControllerFull.setUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[5] = IController.Wire(
            IMainnetControllerFull.setUniswapV3AddLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[6] = IController.Wire(
            IMainnetControllerFull.setUniswapV3AddLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[7] = IController.Wire(
            IMainnetControllerFull.setUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[8] = IController.Wire(
            IMainnetControllerFull.LIMIT_UNISWAP_V3_DEPOSIT.selector,
            IUniswapV3Facet.LIMIT_DEPOSIT.selector
        );

        wires[9] = IController.Wire(
            IMainnetControllerFull.LIMIT_UNISWAP_V3_SWAP.selector,
            IUniswapV3Facet.LIMIT_SWAP.selector
        );

        wires[10] = IController.Wire(
            IMainnetControllerFull.LIMIT_UNISWAP_V3_WITHDRAW.selector,
            IUniswapV3Facet.LIMIT_WITHDRAW.selector
        );

        wires[11] = IController.Wire(
            IMainnetControllerFull.getUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[12] = IController.Wire(
            IMainnetControllerFull.getUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[13] = IController.Wire(
            IMainnetControllerFull.getUniswapV3AddLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[14] = IController.Wire(
            IMainnetControllerFull.getUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        mainnetController.addWires(uniswapV3Facet, wires);
    }

}
