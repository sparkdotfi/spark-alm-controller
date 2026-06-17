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

import { DomainHelpers } from "../../lib/xchain-helpers/src/testing/Domain.sol";

import { IFacet } from "../../src/facets/IFacet.sol";

import { IAaveFacet }          from "../../src/facets/aave/IAaveFacet.sol";
import { IBasinFacet }         from "../../src/facets/basin/IBasinFacet.sol";
import { ICCTPFacet }          from "../../src/facets/cctp/ICCTPFacet.sol";
import { ICentrifugeFacet }    from "../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { ICurveFacet }         from "../../src/facets/curve/ICurveFacet.sol";
import { IDAIUSDSFacet }       from "../../src/facets/dai-usds/IDAIUSDSFacet.sol";
import { IERC4626Facet }       from "../../src/facets/erc4626/IERC4626Facet.sol";
import { IERC7540Facet }       from "../../src/facets/erc7540/IERC7540Facet.sol";
import { IEthenaFacet }        from "../../src/facets/ethena/IEthenaFacet.sol";
import { IFarmFacet }          from "../../src/facets/farm/IFarmFacet.sol";
import { ILayerZeroFacet }     from "../../src/facets/layer-zero/ILayerZeroFacet.sol";
import { IMapleFacet }         from "../../src/facets/maple/IMapleFacet.sol";
import { IMerklFacet }         from "../../src/facets/merkl/IMerklFacet.sol";
import { INFATHaloFacet }      from "../../src/facets/nfat-halo/INFATHaloFacet.sol";
import { INFATPrimeFacet }     from "../../src/facets/nfat-prime/INFATPrimeFacet.sol";
import { IOTCFacet }           from "../../src/facets/otc/IOTCFacet.sol";
import { IPendleFacet }        from "../../src/facets/pendle/IPendleFacet.sol";
import { IPSMFacet }           from "../../src/facets/psm/IPSMFacet.sol";
import { ISparkVaultFacet }    from "../../src/facets/spark-vault/ISparkVaultFacet.sol";
import { ISuperstateFacet }    from "../../src/facets/superstate/ISuperstateFacet.sol";
import { ITransferAssetFacet } from "../../src/facets/transfer-asset/ITransferAssetFacet.sol";
import { IUniswapV3Facet }     from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";
import { IUniswapV4Facet }     from "../../src/facets/uniswap-v4/IUniswapV4Facet.sol";
import { IUSDSFacet }          from "../../src/facets/usds/IUSDSFacet.sol";
import { IWEETHFacet }         from "../../src/facets/weeth/IWEETHFacet.sol";
import { IWrapProxyETHFacet }  from "../../src/facets/wrap-proxy-eth/IWrapProxyETHFacet.sol";
import { IWSTETHFacet }        from "../../src/facets/wsteth/IWSTETHFacet.sol";

import { AaveFacet }          from "../../src/facets/aave/AaveFacet.sol";
import { BasinFacet }         from "../../src/facets/basin/BasinFacet.sol";
import { CCTPFacet }          from "../../src/facets/cctp/CCTPFacet.sol";
import { CentrifugeFacet }    from "../../src/facets/centrifuge/CentrifugeFacet.sol";
import { CurveFacet }         from "../../src/facets/curve/CurveFacet.sol";
import { DAIUSDSFacet }       from "../../src/facets/dai-usds/DAIUSDSFacet.sol";
import { ERC4626Facet }       from "../../src/facets/erc4626/ERC4626Facet.sol";
import { ERC7540Facet }       from "../../src/facets/erc7540/ERC7540Facet.sol";
import { EthenaFacet }        from "../../src/facets/ethena/EthenaFacet.sol";
import { FarmFacet }          from "../../src/facets/farm/FarmFacet.sol";
import { LayerZeroFacet }     from "../../src/facets/layer-zero/LayerZeroFacet.sol";
import { MapleFacet }         from "../../src/facets/maple/MapleFacet.sol";
import { MerklFacet }         from "../../src/facets/merkl/MerklFacet.sol";
import { NFATHaloFacet }      from "../../src/facets/nfat-halo/NFATHaloFacet.sol";
import { NFATPrimeFacet }     from "../../src/facets/nfat-prime/NFATPrimeFacet.sol";
import { OTCFacet }           from "../../src/facets/otc/OTCFacet.sol";
import { PendleFacet }        from "../../src/facets/pendle/PendleFacet.sol";
import { PSMFacet }           from "../../src/facets/psm/PSMFacet.sol";
import { SparkVaultFacet }    from "../../src/facets/spark-vault/SparkVaultFacet.sol";
import { SuperstateFacet }    from "../../src/facets/superstate/SuperstateFacet.sol";
import { TransferAssetFacet } from "../../src/facets/transfer-asset/TransferAssetFacet.sol";
import { UniswapV3Facet }     from "../../src/facets/uniswap-v3/UniswapV3Facet.sol";
import { UniswapV4Facet }     from "../../src/facets/uniswap-v4/UniswapV4Facet.sol";
import { USDSFacet }          from "../../src/facets/usds/USDSFacet.sol";
import { WEETHFacet }         from "../../src/facets/weeth/WEETHFacet.sol";
import { WrapProxyETHFacet }  from "../../src/facets/wrap-proxy-eth/WrapProxyETHFacet.sol";
import { WSTETHFacet }        from "../../src/facets/wsteth/WSTETHFacet.sol";

import { IAccessControls }         from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }               from "../../src/interfaces/IALMProxy.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";
import { IRateLimits }             from "../../src/interfaces/IRateLimits.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

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

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    address internal constant UNISWAP_V3_ROUTER           = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address internal constant UNISWAP_V3_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant ilk = "ILK-A";

    bytes32 constant ALLOCATOR_ROLE       = keccak256("ALLOCATOR_ROLE");
    bytes32 constant ALLOCATOR_ADMIN_ROLE = keccak256("ALLOCATOR_ADMIN_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE   = 0x00;

    bytes32 constant PSM_ILK = 0x4c4954452d50534d2d555344432d410000000000000000000000000000000000;

    uint256 constant INK           = 1e12 * 1e18;  // Ink initialization amount
    uint256 constant SEVEN_PCT_APY = 1.000000002145441671308778766e27;  // 7% APY (current DSR)
    uint256 constant EIGHT_PCT_APY = 1.000000002440418608258400030e27;  // 8% APY (current DSR + 1%)

    // NOTE: From https://docs.uniswap.org/contracts/v4/deployments (Ethereum Mainnet).
    address internal constant _PERMIT2                     = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _UNISWAP_V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _UNISWAP_V4_ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

    address allocator      = Ethereum.ALM_RELAYER_MULTISIG;
    address allocatorAdmin = Ethereum.ALM_FREEZER_MULTISIG;

    address backstopAllocator = makeAddr("backstopAllocator");  // TODO: Replace with real backstop

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

    Beacon                 beacon;
    IAccessControls        accessControls;
    IALMProxy              almProxy;
    IMainnetControllerFull mainnetController;
    IRateLimits            rateLimits;
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

        beacon  = new Beacon(Ethereum.PAUSE_PROXY);
        factory = new PAUFactory(address(beacon));

        rateLimits     = IRateLimits(factory.deployRateLimits(Ethereum.SPARK_PROXY));
        accessControls = IAccessControls(factory.deployAccessControls(Ethereum.SPARK_PROXY));
        almProxy       = IALMProxy(factory.deployALMProxy(Ethereum.SPARK_PROXY));

        mainnetController = IMainnetControllerFull(
            payable(factory.deployController(address(accessControls), address(almProxy), address(rateLimits)))
        );

        vm.startPrank(Ethereum.SPARK_PROXY);

        almProxy.grantRole(almProxy.CONTROLLER(),     address(mainnetController));
        rateLimits.grantRole(rateLimits.CONTROLLER(), address(mainnetController));

        vm.stopPrank();

        vm.startPrank(Ethereum.PAUSE_PROXY);

        // Facet wiring
        _wireAaveFacet();
        _wireBasinFacet();
        _wireCCTPFacet();
        _wireCentrifugeFacet();
        _wireCurveFacet();
        _wireDAIUSDSFacet();
        _wireERC4626Facet();
        _wireERC7540Facet();
        _wireEthenaFacet();
        _wireFarmFacet();
        _wireLayerZeroFacet();
        _wireMapleFacet();
        _wireMerklFacet();
        _wireNFATHaloFacet();
        _wireNFATPrimeFacet();
        _wireOTCFacet();
        _wirePendleFacet();
        _wirePSMFacet();
        _wireSparkVaultFacet();
        _wireSuperstateFacet();
        _wireTransferAssetFacet();
        _wireUniswapV3Facet();
        _wireUniswapV4Facet();
        _wireUSDSFacet();
        _wireWEETHFacet();
        _wireWrapProxyETHFacet();
        _wireWSTETHFacet();

        vm.stopPrank();

        // Step 4: Initialize through Sky governance (Sky spell payload)

        _pauseProxyInitAlmSystem(Ethereum.PSM, address(almProxy));

        // Step 5: Initialize through Spark governance (Spark spell payload)

        vm.startPrank(Ethereum.SPARK_PROXY);

        accessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        accessControls.grantRole(ALLOCATOR_ROLE,       backstopAllocator);
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role
        //       logic that calls into AccessControls to perform grants and revocations.
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        bytes32[] memory integrationIds = new bytes32[](27);
        integrationIds[0]  = "AAVE_FACET";
        integrationIds[1]  = "BASIN_FACET";
        integrationIds[2]  = "CCTP_FACET";
        integrationIds[3]  = "CENTRIFUGE_FACET";
        integrationIds[4]  = "CURVE_FACET";
        integrationIds[5]  = "DAIUSDS_FACET";
        integrationIds[6]  = "ERC4626_FACET";
        integrationIds[7]  = "ERC7540_FACET";
        integrationIds[8]  = "FARM_FACET";
        integrationIds[9]  = "LAYER_ZERO_FACET";
        integrationIds[10] = "MAPLE_FACET";
        integrationIds[11] = "MERKL_FACET";
        integrationIds[12] = "OTC_FACET";
        integrationIds[13] = "PENDLE_FACET";
        integrationIds[14] = "PSM_FACET";
        integrationIds[15] = "SPARK_VAULT_FACET";
        integrationIds[16] = "SUPERSTATE_FACET";
        integrationIds[17] = "TRANSFER_ASSET_FACET";
        integrationIds[18] = "UNISWAP_V3_FACET";
        integrationIds[19] = "UNISWAP_V4_FACET";
        integrationIds[20] = "ETHENA_FACET";
        integrationIds[21] = "USDS_FACET";
        integrationIds[22] = "WEETH_FACET";
        integrationIds[23] = "WRAP_PROXY_ETH_FACET";
        integrationIds[24] = "WSTETH_FACET";
        integrationIds[25] = "NFAT_HALO_FACET";
        integrationIds[26] = "NFAT_PRIME_FACET";

        mainnetController.updateIntegrations(integrationIds);

        IVaultLike(ilkInst.vault).rely(address(almProxy));
        IBufferLike(IVaultLike(ilkInst.vault).buffer()).approve(address(usds), address(almProxy), type(uint256).max);

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(
            mainnetController.usds_mintRateLimitKey(),
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );

        rateLimits.setRateLimitData(
            mainnetController.psm_usdcToUSDSSwapRateLimitKey(),
            5_000_000e6,
            uint256(1_000_000e6) / 4 hours
        );

        rateLimits.setRateLimitData(
            mainnetController.psm_usdsToUSDCSwapRateLimitKey(),
            5_000_000e6,
            uint256(1_000_000e6) / 4 hours
        );

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

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        vm.label(aaveFacet, "AaveFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](7);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_setMaxSlippage.selector,
            IAaveFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_getMaxSlippage.selector,
            IAaveFacet.getMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_deposit.selector,
            IAaveFacet.deposit.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_withdraw.selector,
            IAaveFacet.withdraw.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_getDepositRateLimitKey.selector,
            IAaveFacet.getDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_getWithdrawRateLimitKey.selector,
            IAaveFacet.getWithdrawRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.aave_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : aaveFacet,
            wires : wires
        });

        beacon.setIntegration("AAVE_FACET", config);
    }

    function _wireBasinFacet() internal {
        address basinFacet = address(new BasinFacet());

        vm.label(basinFacet, "BasinFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.basin_deposit.selector,
            IBasinFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.basin_withdraw.selector,
            IBasinFacet.withdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.basin_getDepositRateLimitKey.selector,
            IBasinFacet.getDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.basin_getWithdrawRateLimitKey.selector,
            IBasinFacet.getWithdrawRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.basin_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : basinFacet,
            wires : wires
        });

        beacon.setIntegration("BASIN_FACET", config);
    }

    function _wireCentrifugeFacet() internal {
        // NOTE: We are NOT wiring DEPOSIT, REDEEM keys, as they already wired in _wireERC7540Facet.

        address centrifugeFacet = address(new CentrifugeFacet());

        vm.label(centrifugeFacet, "CentrifugeFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](14);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_setRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_cancelDepositRequest.selector,
            ICentrifugeFacet.cancelDepositRequest.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_claimCancelDepositRequest.selector,
            ICentrifugeFacet.claimCancelDepositRequest.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_cancelRedeemRequest.selector,
            ICentrifugeFacet.cancelRedeemRequest.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_claimCancelRedeemRequest.selector,
            ICentrifugeFacet.claimCancelRedeemRequest.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_transferShares.selector,
            ICentrifugeFacet.transferShares.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_getRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_getCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getCancelDepositRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_getClaimCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelDepositRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_getCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_getClaimCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelRedeemRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_getTransferRateLimitKey.selector,
            ICentrifugeFacet.getTransferRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.centrifuge_REQUEST_ID.selector,
            ICentrifugeFacet.REQUEST_ID.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : centrifugeFacet,
            wires : wires
        });

        beacon.setIntegration("CENTRIFUGE_FACET", config);
    }

    function _wireCurveFacet() internal {
        address curveFacet = address(new CurveFacet());

        vm.label(curveFacet, "CurveFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](11);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_setMaxSlippage.selector,
            ICurveFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_getMaxSlippage.selector,
            ICurveFacet.getMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_swap.selector,
            ICurveFacet.swap.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_addLiquidity.selector,
            ICurveFacet.addLiquidity.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_removeLiquidity.selector,
            ICurveFacet.removeLiquidity.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_getAggregateDepositRateLimitKey.selector,
            ICurveFacet.getAggregateDepositRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_getAssetDepositRateLimitKey.selector,
            ICurveFacet.getAssetDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_getSwapRateLimitKey.selector,
            ICurveFacet.getSwapRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_getAggregateWithdrawRateLimitKey.selector,
            ICurveFacet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_getAssetWithdrawRateLimitKey.selector,
            ICurveFacet.getAssetWithdrawRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.curve_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : curveFacet,
            wires : wires
        });

        beacon.setIntegration("CURVE_FACET", config);
    }

    function _wireCCTPFacet() internal {
        address cctpFacet = address(new CCTPFacet(CCTP_MESSENGER, Ethereum.USDC));

        vm.label(cctpFacet, "CCTPFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](10);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_setDomainParameters.selector,
            ICCTPFacet.setDomainParameters.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_transfer.selector,
            ICCTPFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_toCCTPRateLimitKey.selector,
            ICCTPFacet.toCCTPRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_getDomainParameters.selector,
            ICCTPFacet.getDomainParameters.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_getToDomainRateLimitKey.selector,
            ICCTPFacet.getToDomainRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_DESTINATION_CALLER.selector,
            ICCTPFacet.DESTINATION_CALLER.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_MIN_FINALITY_THRESHOLD.selector,
            ICCTPFacet.MIN_FINALITY_THRESHOLD.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_cctp.selector,
            ICCTPFacet.cctp.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cctp_usdc.selector,
            ICCTPFacet.usdc.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : cctpFacet,
            wires : wires
        });

        beacon.setIntegration("CCTP_FACET", config);
    }

    function _wireDAIUSDSFacet() internal {
        address daiUSDSFacet = address(new DAIUSDSFacet({
            dai_     : Ethereum.DAI,
            daiUSDS_ : Ethereum.DAI_USDS,
            usds_    : Ethereum.USDS
        }));

        vm.label(daiUSDSFacet, "DAIUSDSFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_swapUSDSToDAI.selector,
            IDAIUSDSFacet.swapUSDSToDAI.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_swapDAIToUSDS.selector,
            IDAIUSDSFacet.swapDAIToUSDS.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_daiToUSDSSwapRateLimitKey.selector,
            IDAIUSDSFacet.daiToUSDSSwapRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_usdsToDAISwapRateLimitKey.selector,
            IDAIUSDSFacet.usdsToDAISwapRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_dai.selector,
            IDAIUSDSFacet.dai.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_daiUSDS.selector,
            IDAIUSDSFacet.daiUSDS.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiUSDS_usds.selector,
            IDAIUSDSFacet.usds.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : daiUSDSFacet,
            wires : wires
        });

        beacon.setIntegration("DAIUSDS_FACET", config);
    }

    function _wireNFATHaloFacet() internal {
        address nfatHaloFacet = address(new NFATHaloFacet());

        vm.label(nfatHaloFacet, "NFATHaloFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](12);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_setMaxAnnualGrowthRate.selector,
            INFATHaloFacet.setMaxAnnualGrowthRate.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_issue.selector,
            INFATHaloFacet.issue.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_repayPrincipal.selector,
            INFATHaloFacet.repayPrincipal.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_repayInterest.selector,
            INFATHaloFacet.repayInterest.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getMaxAnnualGrowthRate.selector,
            INFATHaloFacet.getMaxAnnualGrowthRate.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getFacilityState.selector,
            INFATHaloFacet.getFacilityState.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getPosition.selector,
            INFATHaloFacet.getPosition.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getCurrentMaxOutstandingInterest.selector,
            INFATHaloFacet.getCurrentMaxOutstandingInterest.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getIssueRateLimitKey.selector,
            INFATHaloFacet.getIssueRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getRepayInterestRateLimitKey.selector,
            INFATHaloFacet.getRepayInterestRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_getRepayPrincipalRateLimitKey.selector,
            INFATHaloFacet.getRepayPrincipalRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatHalo_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : nfatHaloFacet,
            wires : wires
        });

        beacon.setIntegration("NFAT_HALO_FACET", config);
    }

    function _wireNFATPrimeFacet() internal {
        address nfatPrimeFacet = address(new NFATPrimeFacet());

        vm.label(nfatPrimeFacet, "NFATPrimeFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](7);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_subscribe.selector,
            INFATPrimeFacet.subscribe.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_withdraw.selector,
            INFATPrimeFacet.withdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_collect.selector,
            INFATPrimeFacet.collect.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_getSubscribeRateLimitKey.selector,
            INFATPrimeFacet.getSubscribeRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_getCollectRateLimitKey.selector,
            INFATPrimeFacet.getCollectRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_getWithdrawRateLimitKey.selector,
            INFATPrimeFacet.getWithdrawRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.nfatPrime_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : nfatPrimeFacet,
            wires : wires
        });

        beacon.setIntegration("NFAT_PRIME_FACET", config);
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](9);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_setMaxExchangeRate.selector,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_deposit.selector,
            IERC4626Facet.deposit.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_withdraw.selector,
            IERC4626Facet.withdraw.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_redeem.selector,
            IERC4626Facet.redeem.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_EXCHANGE_RATE_PRECISION.selector,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_getMaxExchangeRate.selector,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_getDepositRateLimitKey.selector,
            IERC4626Facet.getDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_getWithdrawRateLimitKey.selector,
            IERC4626Facet.getWithdrawRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc4626_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : erc4626Facet,
            wires : wires
        });

        beacon.setIntegration("ERC4626_FACET", config);
    }

    function _wireERC7540Facet() internal {
        address erc7540Facet = address(new ERC7540Facet());

        vm.label(erc7540Facet, "ERC7540Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](9);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_requestDeposit.selector,
            IERC7540Facet.requestDeposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_claimDeposit.selector,
            IERC7540Facet.claimDeposit.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_requestRedeem.selector,
            IERC7540Facet.requestRedeem.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_claimRedeem.selector,
            IERC7540Facet.claimRedeem.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_getRequestDepositRateLimitKey.selector,
            IERC7540Facet.getRequestDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_getClaimDepositRateLimitKey.selector,
            IERC7540Facet.getClaimDepositRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_getRequestRedeemRateLimitKey.selector,
            IERC7540Facet.getRequestRedeemRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_getClaimRedeemRateLimitKey.selector,
            IERC7540Facet.getClaimRedeemRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.erc7540_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : erc7540Facet,
            wires : wires
        });

        beacon.setIntegration("ERC7540_FACET", config);
    }

    function _wireEthenaFacet() internal {
        address ethenaFacet = address(new EthenaFacet(
            ETHENA_MINTER,
            address(susde),
            address(usdc),
            address(usde)
        ));

        vm.label(ethenaFacet, "EthenaFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](18);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_setDelegatedSigner.selector,
            IEthenaFacet.setDelegatedSigner.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_removeDelegatedSigner.selector,
            IEthenaFacet.removeDelegatedSigner.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_prepareMint.selector,
            IEthenaFacet.prepareMint.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_prepareBurn.selector,
            IEthenaFacet.prepareBurn.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_cooldownAssets.selector,
            IEthenaFacet.cooldownAssets.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_cooldownShares.selector,
            IEthenaFacet.cooldownShares.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_unstake.selector,
            IEthenaFacet.unstake.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_setDelegatedSignerRateLimitKey.selector,
            IEthenaFacet.setDelegatedSignerRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_removeDelegatedSignerRateLimitKey.selector,
            IEthenaFacet.removeDelegatedSignerRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_mintRateLimitKey.selector,
            IEthenaFacet.mintRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_burnRateLimitKey.selector,
            IEthenaFacet.burnRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_cooldownRateLimitKey.selector,
            IEthenaFacet.cooldownRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_unstakeRateLimitKey.selector,
            IEthenaFacet.unstakeRateLimitKey.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[14] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_minter.selector,
            IEthenaFacet.minter.selector
        );

        wires[15] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_susde.selector,
            IEthenaFacet.susde.selector
        );

        wires[16] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_usdc.selector,
            IEthenaFacet.usdc.selector
        );

        wires[17] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.ethena_usde.selector,
            IEthenaFacet.usde.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : ethenaFacet,
            wires : wires
        });

        beacon.setIntegration("ETHENA_FACET", config);
    }

    function _wireFarmFacet() internal {
        address farmFacet = address(new FarmFacet());

        vm.label(farmFacet, "FarmFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](7);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_deposit.selector,
            IFarmFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_claimReward.selector,
            IFarmFacet.claimReward.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_withdraw.selector,
            IFarmFacet.withdraw.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_getClaimRewardRateLimitKey.selector,
            IFarmFacet.getClaimRewardRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_getDepositRateLimitKey.selector,
            IFarmFacet.getDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_getWithdrawRateLimitKey.selector,
            IFarmFacet.getWithdrawRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.farm_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : farmFacet,
            wires : wires
        });

        beacon.setIntegration("FARM_FACET", config);
    }

    function _wireLayerZeroFacet() internal {
        address layerZeroFacet = address(new LayerZeroFacet());

        vm.label(layerZeroFacet, "LayerZeroFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZero_setRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZero_transfer.selector,
            ILayerZeroFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZero_getRecipient.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZero_getTransferRateLimitKey.selector,
            ILayerZeroFacet.getTransferRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZero_quoteTransfer.selector,
            ILayerZeroFacet.quoteTransfer.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZero_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : layerZeroFacet,
            wires : wires
        });

        beacon.setIntegration("LAYER_ZERO_FACET", config);
    }

    function _wireMapleFacet() internal {
        address mapleFacet = address(new MapleFacet());

        vm.label(mapleFacet, "MapleFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.maple_requestRedemption.selector,
            IMapleFacet.requestRedemption.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.maple_cancelRedemption.selector,
            IMapleFacet.cancelRedemption.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.maple_getCancelRedeemRateLimitKey.selector,
            IMapleFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.maple_getRequestRedeemRateLimitKey.selector,
            IMapleFacet.getRequestRedeemRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.maple_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : mapleFacet,
            wires : wires
        });

        beacon.setIntegration("MAPLE_FACET", config);
    }

    function _wireMerklFacet() internal {
        address merklFacet = address(new MerklFacet());

        vm.label(merklFacet, "MerklFacet");

        IEnumerableIntegrations.Wire[] memory merklWires = new IEnumerableIntegrations.Wire[](3);

        merklWires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.merkl_toggleOperator.selector,
            IMerklFacet.toggleOperator.selector
        );

        merklWires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.merkl_getToggleOperatorRateLimitKey.selector,
            IMerklFacet.getToggleOperatorRateLimitKey.selector
        );

        merklWires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.merkl_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : merklFacet,
            wires : merklWires
        });

        beacon.setIntegration("MERKL_FACET", config);
    }

    function _wireOTCFacet() internal {
        address otcFacet = address(new OTCFacet());

        vm.label(otcFacet, "OTCFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](14);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_setMaxSlippage.selector,
            IOTCFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_setBuffer.selector,
            IOTCFacet.setBuffer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_setRechargeRate.selector,
            IOTCFacet.setRechargeRate.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_send.selector,
            IOTCFacet.send.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_claim.selector,
            IOTCFacet.claim.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getBuffer.selector,
            IOTCFacet.getBuffer.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getMaxSlippage.selector,
            IOTCFacet.getMaxSlippage.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getRechargeRate.selector,
            IOTCFacet.getRechargeRate.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getState.selector,
            IOTCFacet.getState.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getClaimWithRecharge.selector,
            IOTCFacet.getClaimWithRecharge.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getIsSwapReady.selector,
            IOTCFacet.getIsSwapReady.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getSendRateLimitKey.selector,
            IOTCFacet.getSendRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_getClaimRateLimitKey.selector,
            IOTCFacet.getClaimRateLimitKey.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otc_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : otcFacet,
            wires : wires
        });

        beacon.setIntegration("OTC_FACET", config);
    }

    function _wirePendleFacet() internal {
        address pendleFacet = address(new PendleFacet(GroveEthereum.PENDLE_ROUTER));

        vm.label(pendleFacet, "PendleFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.pendle_redeem.selector,
            IPendleFacet.redeem.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.pendle_getRedeemRateLimitKey.selector,
            IPendleFacet.getRedeemRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.pendle_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.pendle_router.selector,
            IPendleFacet.router.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : pendleFacet,
            wires : wires
        });

        beacon.setIntegration("PENDLE_FACET", config);
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](11);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_swapUSDSToUSDC.selector,
            IPSMFacet.swapUSDSToUSDC.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_swapUSDCToUSDS.selector,
            IPSMFacet.swapUSDCToUSDS.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_to18ConversionFactor.selector,
            IPSMFacet.to18ConversionFactor.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_usdcToUSDSSwapRateLimitKey.selector,
            IPSMFacet.usdcToUSDSSwapRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_usdsToUSDCSwapRateLimitKey.selector,
            IPSMFacet.usdsToUSDCSwapRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_dai.selector,
            IPSMFacet.dai.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_daiUSDS.selector,
            IPSMFacet.daiUSDS.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_psm.selector,
            IPSMFacet.psm.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_usdc.selector,
            IPSMFacet.usdc.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psm_usds.selector,
            IPSMFacet.usds.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : psmFacet,
            wires : wires
        });

        beacon.setIntegration("PSM_FACET", config);
    }

    function _wireSparkVaultFacet() internal {
        address sparkVaultFacet = address(new SparkVaultFacet());

        vm.label(sparkVaultFacet, "SparkVaultFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](3);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.sparkVault_take.selector,
            ISparkVaultFacet.take.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.sparkVault_getTakeRateLimitKey.selector,
            ISparkVaultFacet.getTakeRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.sparkVault_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : sparkVaultFacet,
            wires : wires
        });

        beacon.setIntegration("SPARK_VAULT_FACET", config);
    }

    function _wireSuperstateFacet() internal {
        address superstateFacet = address(new SuperstateFacet(Ethereum.USDC, Ethereum.USTB));

        vm.label(superstateFacet, "SuperstateFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.superstate_subscribe.selector,
            ISuperstateFacet.subscribe.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.superstate_subscribeRateLimitKey.selector,
            ISuperstateFacet.subscribeRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.superstate_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.superstate_usdc.selector,
            ISuperstateFacet.usdc.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.superstate_ustb.selector,
            ISuperstateFacet.ustb.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : superstateFacet,
            wires : wires
        });

        beacon.setIntegration("SUPERSTATE_FACET", config);
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](3);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferAsset_transfer.selector,
            ITransferAssetFacet.transfer.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferAsset_getTransferRateLimitKey.selector,
            ITransferAssetFacet.getTransferRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferAsset_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : transferAssetFacet,
            wires : wires
        });

        beacon.setIntegration("TRANSFER_ASSET_FACET", config);
    }

    function _wireUniswapV3Facet() internal {
        address uniswapV3Facet = address(new UniswapV3Facet(UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_ROUTER));

        vm.label(uniswapV3Facet, "UniswapV3Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](23);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_setMaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_setMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_setLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_setLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_setTWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_swap.selector,
            IUniswapV3Facet.swap.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_addLiquidity.selector,
            IUniswapV3Facet.addLiquidity.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_removeLiquidity.selector,
            IUniswapV3Facet.removeLiquidity.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getAggregateDepositRateLimitKey.selector,
            IUniswapV3Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getAssetDepositRateLimitKey.selector,
            IUniswapV3Facet.getAssetDepositRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getMaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getSwapRateLimitKey.selector,
            IUniswapV3Facet.getSwapRateLimitKey.selector
        );

        wires[14] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getTWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        wires[15] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getAggregateWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[16] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_getAssetWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getAssetWithdrawRateLimitKey.selector
        );

        wires[17] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[18] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_MAX_TICK_DELTA.selector,
            IUniswapV3Facet.MAX_TICK_DELTA.selector
        );

        wires[19] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_MIN_TICK.selector,
            IUniswapV3Facet.MIN_TICK.selector
        );

        wires[20] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_MAX_TICK.selector,
            IUniswapV3Facet.MAX_TICK.selector
        );

        wires[21] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_positionManager.selector,
            IUniswapV3Facet.positionManager.selector
        );

        wires[22] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV3_router.selector,
            IUniswapV3Facet.router.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : uniswapV3Facet,
            wires : wires
        });

        beacon.setIntegration("UNISWAP_V3_FACET", config);
    }

    function _wireUniswapV4Facet() internal {
        address uniswapV4Facet = address(new UniswapV4Facet({
            permit2_         : _PERMIT2,
            positionManager_ : _UNISWAP_V4_POSITION_MANAGER,
            router_          : _UNISWAP_V4_ROUTER
        }));

        vm.label(uniswapV4Facet, "UniswapV4Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](17);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_setMaxSlippage.selector,
            IUniswapV4Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_setTickLimits.selector,
            IUniswapV4Facet.setTickLimits.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_mintPosition.selector,
            IUniswapV4Facet.mintPosition.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_increasePosition.selector,
            IUniswapV4Facet.increasePosition.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_decreasePosition.selector,
            IUniswapV4Facet.decreasePosition.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_swap.selector,
            IUniswapV4Facet.swap.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getAggregateDepositRateLimitKey.selector,
            IUniswapV4Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getAssetDepositRateLimitKey.selector,
            IUniswapV4Facet.getAssetDepositRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getMaxSlippage.selector,
            IUniswapV4Facet.getMaxSlippage.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getSwapRateLimitKey.selector,
            IUniswapV4Facet.getSwapRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getTickLimits.selector,
            IUniswapV4Facet.getTickLimits.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getAggregateWithdrawRateLimitKey.selector,
            IUniswapV4Facet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_getAssetWithdrawRateLimitKey.selector,
            IUniswapV4Facet.getAssetWithdrawRateLimitKey.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[14] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_permit2.selector,
            IUniswapV4Facet.permit2.selector
        );

        wires[15] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_positionManager.selector,
            IUniswapV4Facet.positionManager.selector
        );

        wires[16] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4_router.selector,
            IUniswapV4Facet.router.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : uniswapV4Facet,
            wires : wires
        });

        beacon.setIntegration("UNISWAP_V4_FACET", config);
    }

    function _wireUSDSFacet() internal {
        address usdsFacet = address(new USDSFacet(address(usds)));

        vm.label(usdsFacet, "USDSFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_setVault.selector,
            IUSDSFacet.setVault.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_mint.selector,
            IUSDSFacet.mint.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_burn.selector,
            IUSDSFacet.burn.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_vault.selector,
            IUSDSFacet.vault.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_mintRateLimitKey.selector,
            IUSDSFacet.mintRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_burnRateLimitKey.selector,
            IUSDSFacet.burnRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usds_usds.selector,
            IUSDSFacet.usds.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : usdsFacet,
            wires : wires
        });

        beacon.setIntegration("USDS_FACET", config);
    }

    function _wireWEETHFacet() internal {
        address weethFacet = address(new WEETHFacet(Ethereum.WEETH, Ethereum.WETH));

        vm.label(weethFacet, "WEETHFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](9);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_deposit.selector,
            IWEETHFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_requestWithdraw.selector,
            IWEETHFacet.requestWithdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_claimWithdrawal.selector,
            IWEETHFacet.claimWithdrawal.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_getDepositRateLimitKey.selector,
            IWEETHFacet.getDepositRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_getRequestWithdrawRateLimitKey.selector,
            IWEETHFacet.getRequestWithdrawRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_getClaimWithdrawRateLimitKey.selector,
            IWEETHFacet.getClaimWithdrawRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_weeth.selector,
            IWEETHFacet.weeth.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.weeth_weth.selector,
            IWEETHFacet.weth.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : weethFacet,
            wires : wires
        });

        beacon.setIntegration("WEETH_FACET", config);
    }

    function _wireWrapProxyETHFacet() internal {
        address wrapProxyETHFacet = address(new WrapProxyETHFacet(Ethereum.WETH));

        vm.label(wrapProxyETHFacet, "WrapProxyETHFacet");

        IEnumerableIntegrations.Wire[] memory wrapWires = new IEnumerableIntegrations.Wire[](4);

        wrapWires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wrapProxyETH_wrapAll.selector,
            IWrapProxyETHFacet.wrapAll.selector
        );

        wrapWires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wrapProxyETH_wrapRateLimitKey.selector,
            IWrapProxyETHFacet.wrapRateLimitKey.selector
        );

        wrapWires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wrapProxyETH_VERSION.selector,
            IFacet.VERSION.selector
        );

        wrapWires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wrapProxyETH_weth.selector,
            IWrapProxyETHFacet.weth.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : wrapProxyETHFacet,
            wires : wrapWires
        });

        beacon.setIntegration("WRAP_PROXY_ETH_FACET", config);
    }

    function _wireWSTETHFacet() internal {
        address wstethFacet = address(new WSTETHFacet(
            Ethereum.WETH,
            Ethereum.WSTETH_WITHDRAW_QUEUE,
            Ethereum.WSTETH
        ));

        vm.label(wstethFacet, "WSTETHFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](10);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_deposit.selector,
            IWSTETHFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_requestWithdraw.selector,
            IWSTETHFacet.requestWithdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_claimWithdrawal.selector,
            IWSTETHFacet.claimWithdrawal.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_depositRateLimitKey.selector,
            IWSTETHFacet.depositRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_requestWithdrawRateLimitKey.selector,
            IWSTETHFacet.requestWithdrawRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_claimWithdrawRateLimitKey.selector,
            IWSTETHFacet.claimWithdrawRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_weth.selector,
            IWSTETHFacet.weth.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_withdrawQueue.selector,
            IWSTETHFacet.withdrawQueue.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wsteth_wsteth.selector,
            IWSTETHFacet.wsteth.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : wstethFacet,
            wires : wires
        });

        beacon.setIntegration("WSTETH_FACET", config);
    }

}
