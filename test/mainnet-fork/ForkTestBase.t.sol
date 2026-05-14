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

        mainnetController = IMainnetControllerFull(payable(factory.deploy(Ethereum.SPARK_PROXY)));
        accessControls    = IAccessControls(mainnetController.accessControls());
        almProxy          = IALMProxy(payable(mainnetController.proxy()));
        rateLimits        = IRateLimits(mainnetController.rateLimits());

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

        bytes32[] memory integrationIds = new bytes32[](25);
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

        mainnetController.updateIntegrations(integrationIds);

        IVaultLike(ilkInst.vault).rely(address(almProxy));
        IBufferLike(IVaultLike(ilkInst.vault).buffer()).approve(address(usds), address(almProxy), type(uint256).max);

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(
            mainnetController.usdsMintRateLimitKey(),
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours
        );

        rateLimits.setRateLimitData(
            mainnetController.psmUSDCToUSDSSwapRateLimitKey(),
            5_000_000e6,
            uint256(1_000_000e6) / 4 hours
        );

        rateLimits.setRateLimitData(
            mainnetController.psmUSDSToUSDCSwapRateLimitKey(),
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setAaveMaxSlippage.selector,
            IAaveFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getAaveMaxSlippage.selector,
            IAaveFacet.getMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.depositAave.selector,
            IAaveFacet.deposit.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.withdrawAave.selector,
            IAaveFacet.withdraw.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getAaveDepositRateLimitKey.selector,
            IAaveFacet.getDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getAaveWithdrawRateLimitKey.selector,
            IAaveFacet.getWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.depositBasin.selector,
            IBasinFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.withdrawBasin.selector,
            IBasinFacet.withdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getBasinDepositRateLimitKey.selector,
            IBasinFacet.getDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getBasinWithdrawRateLimitKey.selector,
            IBasinFacet.getWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](12);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setCentrifugeRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cancelCentrifugeDepositRequest.selector,
            ICentrifugeFacet.cancelDepositRequest.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimCentrifugeCancelDepositRequest.selector,
            ICentrifugeFacet.claimCancelDepositRequest.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cancelCentrifugeRedeemRequest.selector,
            ICentrifugeFacet.cancelRedeemRequest.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimCentrifugeCancelRedeemRequest.selector,
            ICentrifugeFacet.claimCancelRedeemRequest.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferSharesCentrifuge.selector,
            ICentrifugeFacet.transferShares.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCentrifugeRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCentrifugeCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getCancelDepositRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCentrifugeClaimCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelDepositRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCentrifugeCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCentrifugeClaimCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelRedeemRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCentrifugeTransferRateLimitKey.selector,
            ICentrifugeFacet.getTransferRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](9);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setCurveMaxSlippage.selector,
            ICurveFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCurveMaxSlippage.selector,
            ICurveFacet.getMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapCurve.selector,
            ICurveFacet.swap.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.addLiquidityCurve.selector,
            ICurveFacet.addLiquidity.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.removeLiquidityCurve.selector,
            ICurveFacet.removeLiquidity.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCurveAggregateDepositRateLimitKey.selector,
            ICurveFacet.getAggregateDepositRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCurveAssetDepositRateLimitKey.selector,
            ICurveFacet.getAssetDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCurveSwapRateLimitKey.selector,
            ICurveFacet.getSwapRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCurveWithdrawRateLimitKey.selector,
            ICurveFacet.getWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setCCTPDomainParameters.selector,
            ICCTPFacet.setDomainParameters.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferUSDCToCCTP.selector,
            ICCTPFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.toCCTPRateLimitKey.selector,
            ICCTPFacet.toCCTPRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCCTPDomainParameters.selector,
            ICCTPFacet.getDomainParameters.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getCCTPToDomainRateLimitKey.selector,
            ICCTPFacet.getToDomainRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapUSDSToDAI.selector,
            IDAIUSDSFacet.swapUSDSToDAI.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapDAIToUSDS.selector,
            IDAIUSDSFacet.swapDAIToUSDS.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.daiToUSDSSwapRateLimitKey.selector,
            IDAIUSDSFacet.daiToUSDSSwapRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdsToDAISwapRateLimitKey.selector,
            IDAIUSDSFacet.usdsToDAISwapRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : daiUSDSFacet,
            wires : wires
        });

        beacon.setIntegration("DAIUSDS_FACET", config);
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setMaxExchangeRate.selector,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.depositERC4626.selector,
            IERC4626Facet.deposit.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.withdrawERC4626.selector,
            IERC4626Facet.withdraw.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.redeemERC4626.selector,
            IERC4626Facet.redeem.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.EXCHANGE_RATE_PRECISION.selector,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.maxExchangeRates.selector,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getERC4626DepositRateLimitKey.selector,
            IERC4626Facet.getDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getERC4626WithdrawRateLimitKey.selector,
            IERC4626Facet.getWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.requestDepositERC7540.selector,
            IERC7540Facet.requestDeposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimDepositERC7540.selector,
            IERC7540Facet.claimDeposit.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.requestRedeemERC7540.selector,
            IERC7540Facet.requestRedeem.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimRedeemERC7540.selector,
            IERC7540Facet.claimRedeem.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getERC7540RequestDepositRateLimitKey.selector,
            IERC7540Facet.getRequestDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getERC7540ClaimDepositRateLimitKey.selector,
            IERC7540Facet.getClaimDepositRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getERC7540RequestRedeemRateLimitKey.selector,
            IERC7540Facet.getRequestRedeemRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getERC7540ClaimRedeemRateLimitKey.selector,
            IERC7540Facet.getClaimRedeemRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](13);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setEthenaDelegatedSigner.selector,
            IEthenaFacet.setDelegatedSigner.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.removeEthenaDelegatedSigner.selector,
            IEthenaFacet.removeDelegatedSigner.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.prepareUSDeMint.selector,
            IEthenaFacet.prepareMint.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.prepareUSDeBurn.selector,
            IEthenaFacet.prepareBurn.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cooldownAssetsSUSDe.selector,
            IEthenaFacet.cooldownAssets.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cooldownSharesSUSDe.selector,
            IEthenaFacet.cooldownShares.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.unstakeSUSDe.selector,
            IEthenaFacet.unstake.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setEthenaDelegatedSignerRateLimitKey.selector,
            IEthenaFacet.setDelegatedSignerRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.removeEthenaDelegatedSignerRateLimitKey.selector,
            IEthenaFacet.removeDelegatedSignerRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdeMintRateLimitKey.selector,
            IEthenaFacet.mintRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdeBurnRateLimitKey.selector,
            IEthenaFacet.burnRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdeCooldownRateLimitKey.selector,
            IEthenaFacet.cooldownRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdeUnstakeRateLimitKey.selector,
            IEthenaFacet.unstakeRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.depositToFarm.selector,
            IFarmFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimRewardFromFarm.selector,
            IFarmFacet.claimReward.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.withdrawFromFarm.selector,
            IFarmFacet.withdraw.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getFarmClaimRewardRateLimitKey.selector,
            IFarmFacet.getClaimRewardRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getFarmDepositRateLimitKey.selector,
            IFarmFacet.getDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getFarmWithdrawRateLimitKey.selector,
            IFarmFacet.getWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setLayerZeroRecipient.selector,
            ILayerZeroFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferTokenLayerZero.selector,
            ILayerZeroFacet.transfer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.layerZeroRecipients.selector,
            ILayerZeroFacet.getRecipient.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getLayerZeroTransferRateLimitKey.selector,
            ILayerZeroFacet.getTransferRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.quoteTransferLayerZero.selector,
            ILayerZeroFacet.quoteTransfer.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.requestMapleRedemption.selector,
            IMapleFacet.requestRedemption.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.cancelMapleRedemption.selector,
            IMapleFacet.cancelRedemption.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getMapleCancelRedeemRateLimitKey.selector,
            IMapleFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getMapleRequestRedeemRateLimitKey.selector,
            IMapleFacet.getRequestRedeemRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory merklWires = new IEnumerableIntegrations.Wire[](2);

        merklWires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.toggleOperatorMerkl.selector,
            IMerklFacet.toggleOperator.selector
        );

        merklWires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getMerklToggleOperatorRateLimitKey.selector,
            IMerklFacet.getToggleOperatorRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](13);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setOTCMaxSlippage.selector,
            IOTCFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setOTCBuffer.selector,
            IOTCFacet.setBuffer.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setOTCRechargeRate.selector,
            IOTCFacet.setRechargeRate.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otcSend.selector,
            IOTCFacet.send.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otcClaim.selector,
            IOTCFacet.claim.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getOTCBuffer.selector,
            IOTCFacet.getBuffer.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getOTCMaxSlippage.selector,
            IOTCFacet.getMaxSlippage.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getOTCRechargeRate.selector,
            IOTCFacet.getRechargeRate.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.otcs.selector,
            IOTCFacet.getState.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getOtcClaimWithRecharge.selector,
            IOTCFacet.getClaimWithRecharge.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.isOtcSwapReady.selector,
            IOTCFacet.getIsSwapReady.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getOTCSendRateLimitKey.selector,
            IOTCFacet.getSendRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getOTCClaimRateLimitKey.selector,
            IOTCFacet.getClaimRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.redeemPendlePT.selector,
            IPendleFacet.redeem.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getPendleRedeemRateLimitKey.selector,
            IPendleFacet.getRedeemRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](5);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapUSDSToUSDC.selector,
            IPSMFacet.swapUSDSToUSDC.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapUSDCToUSDS.selector,
            IPSMFacet.swapUSDCToUSDS.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psmTo18ConversionFactor.selector,
            IPSMFacet.to18ConversionFactor.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psmUSDCToUSDSSwapRateLimitKey.selector,
            IPSMFacet.usdcToUSDSSwapRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.psmUSDSToUSDCSwapRateLimitKey.selector,
            IPSMFacet.usdsToUSDCSwapRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.takeFromSparkVault.selector,
            ISparkVaultFacet.take.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getSparkVaultTakeRateLimitKey.selector,
            ISparkVaultFacet.getTakeRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.subscribeSuperstate.selector,
            ISuperstateFacet.subscribe.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.superstateSubscribeRateLimitKey.selector,
            ISuperstateFacet.subscribeRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.transferAsset.selector,
            ITransferAssetFacet.transfer.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getTransferAssetTransferRateLimitKey.selector,
            ITransferAssetFacet.getTransferRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](17);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV3AddLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV3AddLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapUniswapV3.selector,
            IUniswapV3Facet.swap.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.addLiquidityUniswapV3.selector,
            IUniswapV3Facet.addLiquidity.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.removeLiquidityUniswapV3.selector,
            IUniswapV3Facet.removeLiquidity.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3AggregateDepositRateLimitKey.selector,
            IUniswapV3Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3AssetDepositRateLimitKey.selector,
            IUniswapV3Facet.getAssetDepositRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3AddLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3SwapRateLimitKey.selector,
            IUniswapV3Facet.getSwapRateLimitKey.selector
        );

        wires[14] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        wires[15] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3AggregateWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[16] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV3AssetWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getAssetWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](13);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV4MaxSlippage.selector,
            IUniswapV4Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUniswapV4TickLimits.selector,
            IUniswapV4Facet.setTickLimits.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.mintPositionUniswapV4.selector,
            IUniswapV4Facet.mintPosition.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.increaseLiquidityUniswapV4.selector,
            IUniswapV4Facet.increasePosition.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.decreaseLiquidityUniswapV4.selector,
            IUniswapV4Facet.decreasePosition.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.swapUniswapV4.selector,
            IUniswapV4Facet.swap.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV4AggregateDepositRateLimitKey.selector,
            IUniswapV4Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV4AssetDepositRateLimitKey.selector,
            IUniswapV4Facet.getAssetDepositRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4MaxSlippages.selector,
            IUniswapV4Facet.getMaxSlippage.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV4SwapRateLimitKey.selector,
            IUniswapV4Facet.getSwapRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.uniswapV4TickLimits.selector,
            IUniswapV4Facet.getTickLimits.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV4AggregateWithdrawRateLimitKey.selector,
            IUniswapV4Facet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getUniswapV4AssetWithdrawRateLimitKey.selector,
            IUniswapV4Facet.getAssetWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.setUSDSVault.selector,
            IUSDSFacet.setVault.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.mintUSDS.selector,
            IUSDSFacet.mint.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.burnUSDS.selector,
            IUSDSFacet.burn.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdsVault.selector,
            IUSDSFacet.vault.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdsMintRateLimitKey.selector,
            IUSDSFacet.mintRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.usdsBurnRateLimitKey.selector,
            IUSDSFacet.burnRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.depositToWeETH.selector,
            IWEETHFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.requestWithdrawFromWeETH.selector,
            IWEETHFacet.requestWithdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimWithdrawalFromWeETH.selector,
            IWEETHFacet.claimWithdrawal.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getWEETHDepositRateLimitKey.selector,
            IWEETHFacet.getDepositRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getWEETHRequestWithdrawRateLimitKey.selector,
            IWEETHFacet.getRequestWithdrawRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.getWEETHClaimWithdrawRateLimitKey.selector,
            IWEETHFacet.getClaimWithdrawRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wrapWires = new IEnumerableIntegrations.Wire[](2);

        wrapWires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wrapAllProxyETH.selector,
            IWrapProxyETHFacet.wrapAll.selector
        );

        wrapWires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wrapAllProxyETHRateLimitKey.selector,
            IWrapProxyETHFacet.wrapRateLimitKey.selector
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

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.depositToWstETH.selector,
            IWSTETHFacet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.requestWithdrawFromWstETH.selector,
            IWSTETHFacet.requestWithdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.claimWithdrawalFromWstETH.selector,
            IWSTETHFacet.claimWithdrawal.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wstethDepositRateLimitKey.selector,
            IWSTETHFacet.depositRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wstethRequestWithdrawRateLimitKey.selector,
            IWSTETHFacet.requestWithdrawRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IMainnetControllerFull.wstethClaimWithdrawRateLimitKey.selector,
            IWSTETHFacet.claimWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : wstethFacet,
            wires : wires
        });

        beacon.setIntegration("WSTETH_FACET", config);
    }

}
