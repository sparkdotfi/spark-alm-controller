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

import { IAaveFacet }          from "../../src/interfaces/facets/IAaveFacet.sol";
import { ICCTPFacet }          from "../../src/interfaces/facets/ICCTPFacet.sol";
import { IDAIUSDSFacet }       from "../../src/interfaces/facets/IDAIUSDSFacet.sol";
import { IERC4626Facet }       from "../../src/interfaces/facets/IERC4626Facet.sol";
import { IERC7540Facet }       from "../../src/interfaces/facets/IERC7540Facet.sol";
import { IFarmFacet }          from "../../src/interfaces/facets/IFarmFacet.sol";
import { IMapleFacet }         from "../../src/interfaces/facets/IMapleFacet.sol";
import { IPendleFacet }        from "../../src/interfaces/facets/IPendleFacet.sol";
import { IPSMFacet }           from "../../src/interfaces/facets/IPSMFacet.sol";
import { ISparkVaultFacet }    from "../../src/interfaces/facets/ISparkVaultFacet.sol";
import { ISuperstateFacet }    from "../../src/interfaces/facets/ISuperstateFacet.sol";
import { ITransferAssetFacet } from "../../src/interfaces/facets/ITransferAssetFacet.sol";
import { IUniswapV4Facet }     from "../../src/interfaces/facets/IUniswapV4Facet.sol";
import { IUSDEFacet }          from "../../src/interfaces/facets/IUSDEFacet.sol";
import { IUSDSFacet }          from "../../src/interfaces/facets/IUSDSFacet.sol";
import { IWEETHFacet }         from "../../src/interfaces/facets/IWEETHFacet.sol";
import { IWrapProxyETHFacet }  from "../../src/interfaces/facets/IWrapProxyETHFacet.sol";
import { IWSTETHFacet }        from "../../src/interfaces/facets/IWSTETHFacet.sol";

import { AaveFacet }          from "../../src/libraries/AaveLib.sol";
import { CCTPFacet }          from "../../src/libraries/CCTPLib.sol";
import { DAIUSDSFacet }       from "../../src/libraries/DAIUSDSLib.sol";
import { ERC4626Facet }       from "../../src/libraries/ERC4626Lib.sol";
import { ERC7540Facet }       from "../../src/libraries/ERC7540Lib.sol";
import { FarmFacet }          from "../../src/libraries/FarmLib.sol";
import { MapleFacet }         from "../../src/libraries/MapleLib.sol";
import { PendleFacet }        from "../../src/libraries/PendleLib.sol";
import { PSMFacet }           from "../../src/libraries/PSMLib.sol";
import { SparkVaultFacet }    from "../../src/libraries/SparkVaultLib.sol";
import { SuperstateFacet }    from "../../src/libraries/SuperstateLib.sol";
import { TransferAssetFacet } from "../../src/libraries/TransferAssetLib.sol";
import { UniswapV4Facet }     from "../../src/libraries/UniswapV4Lib.sol";
import { USDEFacet }          from "../../src/libraries/USDELib.sol";
import { USDSFacet }          from "../../src/libraries/USDSLib.sol";
import { WEETHFacet }         from "../../src/libraries/WEETHLib.sol";
import { WrapProxyETHFacet }  from "../../src/libraries/WrapProxyETHLib.sol";
import { WSTETHFacet }        from "../../src/libraries/WSTETHLib.sol";

import { AccessControls }    from "../../src/AccessControls.sol";
import { ALMProxy }          from "../../src/ALMProxy.sol";
import { MainnetController } from "../../src/MainnetController.sol";
import { RateLimitHelpers }  from "../../src/RateLimitHelpers.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

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

    // NOTE: From https://docs.uniswap.org/contracts/v4/deployments (Ethereum Mainnet).
    address internal constant _PERMIT2                     = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _UNISWAP_V4_POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _UNISWAP_V4_ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;

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

        mainnetController = IMainnetControllerFull(payable(new MainnetController({
            admin_          : Ethereum.SPARK_PROXY,
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits),
            accessControls_ : address(accessControls),
            vault_          : ilkInst.vault,
            psm_            : Ethereum.PSM,
            daiUsds_        : Ethereum.DAI_USDS,
            cctp_           : CCTP_MESSENGER
        })));

        CONTROLLER = almProxy.CONTROLLER();
        FREEZER    = mainnetController.FREEZER();
        RELAYER    = mainnetController.RELAYER();

        vm.startPrank(Ethereum.SPARK_PROXY);

        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), backstopRelayer);

        // Facet wiring

        _wireAaveFacet();
        _wireCCTPFacet();
        _wireDAIUSDSFacet();
        _wireERC4626Facet();
        _wireERC7540Facet();
        _wireFarmFacet();
        _wireMapleFacet();
        _wirePendleFacet();
        _wirePSMFacet();
        _wireSparkVaultFacet();
        _wireSuperstateFacet();
        _wireTransferAssetFacet();
        _wireUSDEFacet();
        _wireUSDSFacet();
        _wireUniswapV4Facet();
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
            mainnetController.setCCTPMintRecipient(mintRecipients[i].domain, mintRecipients[i].mintRecipient);
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
    /*** Facet wiring helpers                                                                   ***/
    /**********************************************************************************************/

    function _wireCCTPFacet() internal {
        address cctpFacet = address(new CCTPFacet(CCTP_MESSENGER, Ethereum.USDC));

        vm.label(cctpFacet, "CCTPFacet");

        // Controller.setCCTPMaxFeeCap() -> CCTPFacet.setMaxFeeCap()
        mainnetController.setDispatch(
            IMainnetControllerFull.setCCTPMaxFeeCap.selector,
            cctpFacet,
            ICCTPFacet.setMaxFeeCap.selector
        );

        // Controller.setCCTPMintRecipient() -> CCTPFacet.setMintRecipient()
        mainnetController.setDispatch(
            IMainnetControllerFull.setCCTPMintRecipient.selector,
            cctpFacet,
            ICCTPFacet.setMintRecipient.selector
        );

        // Controller.getCCTPMaxFeeCap() -> CCTPFacet.getMaxFeeCap()
        mainnetController.setDispatch(
            IMainnetControllerFull.getCCTPMaxFeeCap.selector,
            cctpFacet,
            ICCTPFacet.getMaxFeeCap.selector
        );

        // Controller.getCCTPMintRecipient() -> CCTPFacet.getMintRecipient()
        mainnetController.setDispatch(
            IMainnetControllerFull.getCCTPMintRecipient.selector,
            cctpFacet,
            ICCTPFacet.getMintRecipient.selector
        );

        // Controller.transferUSDCToCCTP(uint256,uint32) -> CCTPFacet.transfer(uint256,uint32)
        mainnetController.setDispatch(
            IMainnetControllerFull.transferUSDCToCCTP.selector,
            cctpFacet,
            ICCTPFacet.transfer.selector
        );

        // Controller.transferUSDCToCCTPWithFee(uint256,uint256,uint32) -> CCTPFacet.transferWithFee(uint256,uint256,uint32)
        mainnetController.setDispatch(
            IMainnetControllerFull.transferUSDCToCCTPWithFee.selector,
            cctpFacet,
            ICCTPFacet.transferWithFee.selector
        );

        // Controller.LIMIT_USDC_TO_CCTP() -> CCTPFacet.LIMIT_TO_CCTP()
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_USDC_TO_CCTP.selector,
            cctpFacet,
            ICCTPFacet.LIMIT_TO_CCTP.selector
        );

        // Controller.LIMIT_USDC_TO_DOMAIN() -> CCTPFacet.LIMIT_TO_DOMAIN()
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_USDC_TO_DOMAIN.selector,
            cctpFacet,
            ICCTPFacet.LIMIT_TO_DOMAIN.selector
        );
    }

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        vm.label(aaveFacet, "AaveFacet");

        // Controller.setAaveMaxSlippage() -> AaveFacet.setMaxSlippage()
        mainnetController.setDispatch(
            IMainnetControllerFull.setAaveMaxSlippage.selector,
            aaveFacet,
            IAaveFacet.setMaxSlippage.selector
        );

        // Controller.getAaveMaxSlippage() -> AaveFacet.getMaxSlippage()
        mainnetController.setDispatch(
            IMainnetControllerFull.getAaveMaxSlippage.selector,
            aaveFacet,
            IAaveFacet.getMaxSlippage.selector
        );

        // "Controller.depositAave()" -> "AaveFacet.deposit()"
        mainnetController.setDispatch(
            IMainnetControllerFull.depositAave.selector,
            aaveFacet,
            IAaveFacet.deposit.selector
        );

        // "Controller.withdrawAave()" -> "AaveFacet.withdraw()"
        mainnetController.setDispatch(
            IMainnetControllerFull.withdrawAave.selector,
            aaveFacet,
            IAaveFacet.withdraw.selector
        );

        // "Controller.LIMIT_AAVE_DEPOSIT()" -> "AaveFacet.LIMIT_DEPOSIT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_AAVE_DEPOSIT.selector,
            aaveFacet,
            IAaveFacet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_AAVE_WITHDRAW()" -> "AaveFacet.LIMIT_WITHDRAW()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_AAVE_WITHDRAW.selector,
            aaveFacet,
            IAaveFacet.LIMIT_WITHDRAW.selector
        );
    }

    function _wireDAIUSDSFacet() internal {
        address daiUSDSFacet = address(new DAIUSDSFacet({
            dai_     : Ethereum.DAI,
            daiUSDS_ : Ethereum.DAI_USDS,
            usds_    : Ethereum.USDS
        }));

        vm.label(daiUSDSFacet, "DAIUSDSFacet");

        // "Controller.swapUSDSToDAI()" -> "DAIUSDSFacet.swapUSDSToDAI()"
        mainnetController.setDispatch(
            IMainnetControllerFull.swapUSDSToDAI.selector,
            daiUSDSFacet,
            IDAIUSDSFacet.swapUSDSToDAI.selector
        );

        // "Controller.swapDAIToUSDS()" -> "DAIUSDSFacet.swapDAIToUSDS()"
        mainnetController.setDispatch(
            IMainnetControllerFull.swapDAIToUSDS.selector,
            daiUSDSFacet,
            IDAIUSDSFacet.swapDAIToUSDS.selector
        );
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        // "Controller.setMaxExchangeRate()" -> "ERC4626Facet.setMaxExchangeRate()"
        mainnetController.setDispatch(
            IMainnetControllerFull.setMaxExchangeRate.selector,
            erc4626Facet,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        // "Controller.maxExchangeRates()" -> "ERC4626Facet.getMaxExchangeRate()"
        mainnetController.setDispatch(
            IMainnetControllerFull.maxExchangeRates.selector,
            erc4626Facet,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        // "Controller.depositERC4626()" -> "ERC4626Facet.deposit()"
        mainnetController.setDispatch(
            IMainnetControllerFull.depositERC4626.selector,
            erc4626Facet,
            IERC4626Facet.deposit.selector
        );

        // "Controller.withdrawERC4626()" -> "ERC4626Facet.withdraw()"
        mainnetController.setDispatch(
            IMainnetControllerFull.withdrawERC4626.selector,
            erc4626Facet,
            IERC4626Facet.withdraw.selector
        );

        // "Controller.redeemERC4626()" -> "ERC4626Facet.redeem()"
        mainnetController.setDispatch(
            IMainnetControllerFull.redeemERC4626.selector,
            erc4626Facet,
            IERC4626Facet.redeem.selector
        );

        // "Controller.LIMIT_4626_DEPOSIT()" -> "ERC4626Facet.LIMIT_DEPOSIT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_4626_DEPOSIT.selector,
            erc4626Facet,
            IERC4626Facet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_4626_WITHDRAW()" -> "ERC4626Facet.LIMIT_WITHDRAW()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_4626_WITHDRAW.selector,
            erc4626Facet,
            IERC4626Facet.LIMIT_WITHDRAW.selector
        );

        // "Controller.EXCHANGE_RATE_PRECISION()" -> "ERC4626Facet.EXCHANGE_RATE_PRECISION()"
        mainnetController.setDispatch(
            IMainnetControllerFull.EXCHANGE_RATE_PRECISION.selector,
            erc4626Facet,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );
    }

    function _wireERC7540Facet() internal {
        address erc7540Facet = address(new ERC7540Facet());

        vm.label(erc7540Facet, "ERC7540Facet");

        // "Controller.requestDepositERC7540()" -> "ERC7540Facet.requestDeposit()"
        mainnetController.setDispatch(
            IMainnetControllerFull.requestDepositERC7540.selector,
            erc7540Facet,
            IERC7540Facet.requestDeposit.selector
        );

        // "Controller.claimDepositERC7540()" -> "ERC7540Facet.claimDeposit()"
        mainnetController.setDispatch(
            IMainnetControllerFull.claimDepositERC7540.selector,
            erc7540Facet,
            IERC7540Facet.claimDeposit.selector
        );

        // "Controller.requestRedeemERC7540()" -> "ERC7540Facet.requestRedeem()"
        mainnetController.setDispatch(
            IMainnetControllerFull.requestRedeemERC7540.selector,
            erc7540Facet,
            IERC7540Facet.requestRedeem.selector
        );

        // "Controller.claimRedeemERC7540()" -> "ERC7540Facet.claimRedeem()"
        mainnetController.setDispatch(
            IMainnetControllerFull.claimRedeemERC7540.selector,
            erc7540Facet,
            IERC7540Facet.claimRedeem.selector
        );

        // "Controller.LIMIT_7540_DEPOSIT()" -> "ERC7540Facet.LIMIT_DEPOSIT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_7540_DEPOSIT.selector,
            erc7540Facet,
            IERC7540Facet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_7540_REDEEM()" -> "ERC7540Facet.LIMIT_REDEEM()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_7540_REDEEM.selector,
            erc7540Facet,
            IERC7540Facet.LIMIT_REDEEM.selector
        );
    }

    function _wireFarmFacet() internal {
        address farmFacet = address(new FarmFacet());

        vm.label(farmFacet, "FarmFacet");

        // "Controller.depositToFarm()" -> "FarmFacet.deposit()"
        mainnetController.setDispatch(
            IMainnetControllerFull.depositToFarm.selector,
            farmFacet,
            IFarmFacet.deposit.selector
        );

        // "Controller.withdrawFromFarm()" -> "FarmFacet.withdraw()"
        mainnetController.setDispatch(
            IMainnetControllerFull.withdrawFromFarm.selector,
            farmFacet,
            IFarmFacet.withdraw.selector
        );

        // "Controller.LIMIT_FARM_DEPOSIT()" -> "FarmFacet.LIMIT_DEPOSIT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_FARM_DEPOSIT.selector,
            farmFacet,
            IFarmFacet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_FARM_WITHDRAW()" -> "FarmFacet.LIMIT_WITHDRAW()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_FARM_WITHDRAW.selector,
            farmFacet,
            IFarmFacet.LIMIT_WITHDRAW.selector
        );
    }

    function _wireSparkVaultFacet() internal {
        address sparkVaultFacet = address(new SparkVaultFacet());

        vm.label(sparkVaultFacet, "SparkVaultFacet");

        // "Controller.takeFromSparkVault()" -> "SparkVaultFacet.take()"
        mainnetController.setDispatch(
            IMainnetControllerFull.takeFromSparkVault.selector,
            sparkVaultFacet,
            ISparkVaultFacet.take.selector
        );

        // "Controller.LIMIT_SPARK_VAULT_TAKE()" -> "SparkVaultFacet.LIMIT_TAKE()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_SPARK_VAULT_TAKE.selector,
            sparkVaultFacet,
            ISparkVaultFacet.LIMIT_TAKE.selector
        );
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

        // "Controller.swapUSDSToUSDC()" -> "PSMFacet.swapUSDSToUSDC()"
        mainnetController.setDispatch(
            IMainnetControllerFull.swapUSDSToUSDC.selector,
            psmFacet,
            IPSMFacet.swapUSDSToUSDC.selector
        );

        // "Controller.swapUSDCToUSDS()" -> "PSMFacet.swapUSDCToUSDS()"
        mainnetController.setDispatch(
            IMainnetControllerFull.swapUSDCToUSDS.selector,
            psmFacet,
            IPSMFacet.swapUSDCToUSDS.selector
        );

        // "Controller.psmTo18ConversionFactor()" -> "PSMFacet.to18ConversionFactor()"
        mainnetController.setDispatch(
            IMainnetControllerFull.psmTo18ConversionFactor.selector,
            psmFacet,
            IPSMFacet.to18ConversionFactor.selector
        );

        // "Controller.LIMIT_USDS_TO_USDC()" -> "PSMFacet.LIMIT_USDS_TO_USDC()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_USDS_TO_USDC.selector,
            psmFacet,
            IPSMFacet.LIMIT_USDS_TO_USDC.selector
        );
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        // "Controller.transferAsset()" -> "TransferAssetFacet.transfer()"
        mainnetController.setDispatch(
            IMainnetControllerFull.transferAsset.selector,
            transferAssetFacet,
            ITransferAssetFacet.transfer.selector
        );

        // "Controller.LIMIT_ASSET_TRANSFER()" -> "TransferAssetFacet.LIMIT_TRANSFER()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_ASSET_TRANSFER.selector,
            transferAssetFacet,
            ITransferAssetFacet.LIMIT_TRANSFER.selector
        );
    }

    function _wireMapleFacet() internal {
        address mapleFacet = address(new MapleFacet());

        vm.label(mapleFacet, "MapleFacet");

        // "Controller.requestMapleRedemption()" -> "MapleFacet.requestRedemption()"
        mainnetController.setDispatch(
            IMainnetControllerFull.requestMapleRedemption.selector,
            mapleFacet,
            IMapleFacet.requestRedemption.selector
        );

        // "Controller.cancelMapleRedemption()" -> "MapleFacet.cancelRedemption()"
        mainnetController.setDispatch(
            IMainnetControllerFull.cancelMapleRedemption.selector,
            mapleFacet,
            IMapleFacet.cancelRedemption.selector
        );

        // "Controller.LIMIT_MAPLE_REDEEM()" -> "MapleFacet.LIMIT_REDEEM()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_MAPLE_REDEEM.selector,
            mapleFacet,
            IMapleFacet.LIMIT_REDEEM.selector
        );
    }

    function _wirePendleFacet() internal {
        address pendleFacet = address(new PendleFacet(GroveEthereum.PENDLE_ROUTER));

        vm.label(pendleFacet, "PendleFacet");

        // "Controller.redeemPendlePT()" -> "PendleFacet.redeem()"
        mainnetController.setDispatch(
            IMainnetControllerFull.redeemPendlePT.selector,
            pendleFacet,
            IPendleFacet.redeem.selector
        );

        // "Controller.LIMIT_PENDLE_PT_REDEEM()" -> "PendleFacet.LIMIT_REDEEM()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_PENDLE_PT_REDEEM.selector,
            pendleFacet,
            IPendleFacet.LIMIT_REDEEM.selector
        );
    }

    function _wireSuperstateFacet() internal {
        address superstateFacet = address(new SuperstateFacet(Ethereum.USDC, Ethereum.USTB));

        vm.label(superstateFacet, "SuperstateFacet");

        // "Controller.subscribeSuperstate()" -> "SuperstateFacet.subscribe()"
        mainnetController.setDispatch(
            IMainnetControllerFull.subscribeSuperstate.selector,
            superstateFacet,
            ISuperstateFacet.subscribe.selector
        );

        // "Controller.LIMIT_SUPERSTATE_SUBSCRIBE()" -> "SuperstateFacet.LIMIT_SUBSCRIBE()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_SUPERSTATE_SUBSCRIBE.selector,
            superstateFacet,
            ISuperstateFacet.LIMIT_SUBSCRIBE.selector
        );
    }

    function _wireWEETHFacet() internal {
        address weethFacet = address(new WEETHFacet(Ethereum.WETH, Ethereum.WEETH));

        vm.label(weethFacet, "WEETHFacet");

        // "Controller.depositToWeETH()" -> "WEETHFacet.deposit()"
        mainnetController.setDispatch(
            IMainnetControllerFull.depositToWeETH.selector,
            weethFacet,
            IWEETHFacet.deposit.selector
        );

        // "Controller.requestWithdrawFromWeETH()" -> "WEETHFacet.requestWithdraw()"
        mainnetController.setDispatch(
            IMainnetControllerFull.requestWithdrawFromWeETH.selector,
            weethFacet,
            IWEETHFacet.requestWithdraw.selector
        );

        // "Controller.claimWithdrawalFromWeETH()" -> "WEETHFacet.claimWithdrawal()"
        mainnetController.setDispatch(
            IMainnetControllerFull.claimWithdrawalFromWeETH.selector,
            weethFacet,
            IWEETHFacet.claimWithdrawal.selector
        );

        // "Controller.LIMIT_WEETH_DEPOSIT()" -> "WEETHFacet.LIMIT_DEPOSIT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_WEETH_DEPOSIT.selector,
            weethFacet,
            IWEETHFacet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_WEETH_REQUEST_WITHDRAW()" -> "WEETHFacet.LIMIT_REQUEST_WITHDRAW()"
        mainnetController.setDispatch(
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
        mainnetController.setDispatch(
            IMainnetControllerFull.depositToWstETH.selector,
            wstethFacet,
            IWSTETHFacet.deposit.selector
        );

        // "Controller.requestWithdrawFromWstETH()" -> "WSTETHFacet.requestWithdraw()"
        mainnetController.setDispatch(
            IMainnetControllerFull.requestWithdrawFromWstETH.selector,
            wstethFacet,
            IWSTETHFacet.requestWithdraw.selector
        );

        // "Controller.claimWithdrawalFromWstETH()" -> "WSTETHFacet.claimWithdrawal()"
        mainnetController.setDispatch(
            IMainnetControllerFull.claimWithdrawalFromWstETH.selector,
            wstethFacet,
            IWSTETHFacet.claimWithdrawal.selector
        );

        // "Controller.LIMIT_WSTETH_DEPOSIT()" -> "WSTETHFacet.LIMIT_DEPOSIT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_WSTETH_DEPOSIT.selector,
            wstethFacet,
            IWSTETHFacet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_WSTETH_REQUEST_WITHDRAW()" -> "WSTETHFacet.LIMIT_REQUEST_WITHDRAW()"
        mainnetController.setDispatch(
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
        mainnetController.setDispatch(
            IMainnetControllerFull.cooldownAssetsSUSDe.selector,
            usdeFacet,
            IUSDEFacet.cooldownAssets.selector
        );

        // "Controller.cooldownSharesSUSDe()" -> "IUSDEFacet.cooldownShares()"
        mainnetController.setDispatch(
            IMainnetControllerFull.cooldownSharesSUSDe.selector,
            usdeFacet,
            IUSDEFacet.cooldownShares.selector
        );

        // "Controller.prepareUSDeMint()" -> "IUSDEFacet.prepareMint()"
        mainnetController.setDispatch(
            IMainnetControllerFull.prepareUSDeMint.selector,
            usdeFacet,
            IUSDEFacet.prepareMint.selector
        );

        // "Controller.prepareUSDeBurn()" -> "IUSDEFacet.prepareBurn()"
        mainnetController.setDispatch(
            IMainnetControllerFull.prepareUSDeBurn.selector,
            usdeFacet,
            IUSDEFacet.prepareBurn.selector
        );

        // "Controller.removeDelegatedSigner()" -> "IUSDEFacet.removeDelegatedSigner()"
        mainnetController.setDispatch(
            IMainnetControllerFull.removeDelegatedSigner.selector,
            usdeFacet,
            IUSDEFacet.removeDelegatedSigner.selector
        );

        // "Controller.setDelegatedSigner()" -> "IUSDEFacet.setDelegatedSigner()"
        mainnetController.setDispatch(
            IMainnetControllerFull.setDelegatedSigner.selector,
            usdeFacet,
            IUSDEFacet.setDelegatedSigner.selector
        );

        // "Controller.unstakeSUSDe()" -> "IUSDEFacet.unstakeSUSDE()"
        mainnetController.setDispatch(
            IMainnetControllerFull.unstakeSUSDe.selector,
            usdeFacet,
            IUSDEFacet.unstakeSUSDE.selector
        );

        // "Controller.LIMIT_USDE_BURN()" -> "IUSDEFacet.LIMIT_USDE_BURN()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_USDE_BURN.selector,
            usdeFacet,
            IUSDEFacet.LIMIT_USDE_BURN.selector
        );

        // "Controller.LIMIT_USDE_MINT()" -> "IUSDEFacet.LIMIT_USDE_MINT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_USDE_MINT.selector,
            usdeFacet,
            IUSDEFacet.LIMIT_USDE_MINT.selector
        );

        // "Controller.LIMIT_SUSDE_COOLDOWN()" -> "IUSDEFacet.LIMIT_SUSDE_COOLDOWN()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_SUSDE_COOLDOWN.selector,
            usdeFacet,
            IUSDEFacet.LIMIT_SUSDE_COOLDOWN.selector
        );
    }

    function _wireWrapProxyETHFacet() internal {
        address wrapProxyETHFacet = address(new WrapProxyETHFacet(Ethereum.WETH));

        vm.label(wrapProxyETHFacet, "WrapProxyETHFacet");

        // "Controller.wrapAllProxyETH()" -> "WrapProxyETHFacet.wrapAll()"
        mainnetController.setDispatch(
            IMainnetControllerFull.wrapAllProxyETH.selector,
            wrapProxyETHFacet,
            IWrapProxyETHFacet.wrapAll.selector
        );
    }

    function _wireUSDSFacet() internal {
        address usdsFacet = address(new USDSFacet(vault, address(usds)));

        vm.label(usdsFacet, "USDSFacet");

        // "Controller.mintUSDS()" -> "USDSFacet.mint()"
        mainnetController.setDispatch(
            IMainnetControllerFull.mintUSDS.selector,
            usdsFacet,
            IUSDSFacet.mint.selector
        );

        // "Controller.burnUSDS()" -> "USDSFacet.burn()"
        mainnetController.setDispatch(
            IMainnetControllerFull.burnUSDS.selector,
            usdsFacet,
            IUSDSFacet.burn.selector
        );

        // "Controller.LIMIT_USDS_MINT()" -> "USDSFacet.LIMIT_MINT()"
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_USDS_MINT.selector,
            usdsFacet,
            IUSDSFacet.LIMIT_MINT.selector
        );
    }

    function _wireUniswapV4Facet() internal {
        address uniswapV4Facet = address(new UniswapV4Facet({
            permit2_         : _PERMIT2,
            positionManager_ : _UNISWAP_V4_POSITION_MANAGER,
            router_          : _UNISWAP_V4_ROUTER
        }));

        vm.label(uniswapV4Facet, "UniswapV4Facet");

        // Controller.decreaseLiquidityUniswapV4 -> IUniswapV4Facet.decreasePosition
        mainnetController.setDispatch(
            IMainnetControllerFull.decreaseLiquidityUniswapV4.selector,
            uniswapV4Facet,
            IUniswapV4Facet.decreasePosition.selector
        );

        // Controller.increaseLiquidityUniswapV4 -> IUniswapV4Facet.increasePosition
        mainnetController.setDispatch(
            IMainnetControllerFull.increaseLiquidityUniswapV4.selector,
            uniswapV4Facet,
            IUniswapV4Facet.increasePosition.selector
        );

        // Controller.mintPositionUniswapV4 -> IUniswapV4Facet.mintPosition
        mainnetController.setDispatch(
            IMainnetControllerFull.mintPositionUniswapV4.selector,
            uniswapV4Facet,
            IUniswapV4Facet.mintPosition.selector
        );

        // Controller.setUniswapV4MaxSlippage -> IUniswapV4Facet.setMaxSlippage
        mainnetController.setDispatch(
            IMainnetControllerFull.setUniswapV4MaxSlippage.selector,
            uniswapV4Facet,
            IUniswapV4Facet.setMaxSlippage.selector
        );

        // Controller.setUniswapV4TickLimits -> IUniswapV4Facet.setTickLimits
        mainnetController.setDispatch(
            IMainnetControllerFull.setUniswapV4TickLimits.selector,
            uniswapV4Facet,
            IUniswapV4Facet.setTickLimits.selector
        );

        // Controller.swapUniswapV4 -> IUniswapV4Facet.swap
        mainnetController.setDispatch(
            IMainnetControllerFull.swapUniswapV4.selector,
            uniswapV4Facet,
            IUniswapV4Facet.swap.selector
        );

        // Controller.LIMIT_UNISWAP_V4_DEPOSIT -> IUniswapV4Facet.LIMIT_DEPOSIT
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_UNISWAP_V4_DEPOSIT.selector,
            uniswapV4Facet,
            IUniswapV4Facet.LIMIT_DEPOSIT.selector
        );

        // Controller.LIMIT_UNISWAP_V4_WITHDRAW -> IUniswapV4Facet.LIMIT_WITHDRAW
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_UNISWAP_V4_WITHDRAW.selector,
            uniswapV4Facet,
            IUniswapV4Facet.LIMIT_WITHDRAW.selector
        );

        // Controller.LIMIT_UNISWAP_V4_SWAP -> IUniswapV4Facet.LIMIT_SWAP
        mainnetController.setDispatch(
            IMainnetControllerFull.LIMIT_UNISWAP_V4_SWAP.selector,
            uniswapV4Facet,
            IUniswapV4Facet.LIMIT_SWAP.selector
        );

        // Controller.uniswapV4MaxSlippages -> IUniswapV4Facet.getMaxSlippage
        mainnetController.setDispatch(
            IMainnetControllerFull.uniswapV4MaxSlippages.selector,
            uniswapV4Facet,
            IUniswapV4Facet.getMaxSlippage.selector
        );

        // Controller.uniswapV4TickLimits -> IUniswapV4Facet.getTickLimits
        mainnetController.setDispatch(
            IMainnetControllerFull.uniswapV4TickLimits.selector,
            uniswapV4Facet,
            IUniswapV4Facet.getTickLimits.selector
        );
    }
}
