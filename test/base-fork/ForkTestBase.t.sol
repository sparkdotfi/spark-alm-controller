// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "../../lib/spark-psm/src/PSM3.sol";

import { CCTPForwarder } from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";

import { IAaveFacet }          from "../../src/interfaces/facets/IAaveFacet.sol";
import { IERC4626Facet }       from "../../src/interfaces/facets/IERC4626Facet.sol";
import { IPSM3Facet }          from "../../src/interfaces/facets/IPSM3Facet.sol";
import { ISparkVaultFacet }    from "../../src/interfaces/facets/ISparkVaultFacet.sol";
import { ITransferAssetFacet } from "../../src/interfaces/facets/ITransferAssetFacet.sol";

import { AaveFacet }          from "../../src/libraries/AaveLib.sol";
import { ERC4626Facet }       from "../../src/libraries/ERC4626Lib.sol";
import { PSM3Facet }          from "../../src/libraries/PSM3Lib.sol";
import { SparkVaultFacet }    from "../../src/libraries/SparkVaultLib.sol";
import { TransferAssetFacet } from "../../src/libraries/TransferAssetLib.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimitHelpers }  from "../../src/RateLimitHelpers.sol";
import { RateLimits }        from "../../src/RateLimits.sol";
import { AccessControls }    from "../../src/AccessControls.sol";

import { IForeignControllerFull }  from "../interfaces/IForeignControllerFull.sol";

abstract contract ForkTestBase is Test {

    // TODO: Refactor to use live addresses

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

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 CONTROLLER;
    bytes32 FREEZER;
    bytes32 RELAYER;

    address freezer = Base.ALM_FREEZER_MULTISIG;
    address relayer = Base.ALM_RELAYER_MULTISIG;

    address pocket = makeAddr("pocket");

    /**********************************************************************************************/
    /*** Base addresses                                                                         ***/
    /**********************************************************************************************/

    address constant SPARK_EXECUTOR      = Base.SPARK_EXECUTOR;
    address constant CCTP_MESSENGER_BASE = Base.CCTP_TOKEN_MESSENGER;
    address constant SSR_ORACLE          = Base.SSR_AUTH_ORACLE;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    AccessControls         accessControls;
    ALMProxy               almProxy;
    IForeignControllerFull foreignController;
    RateLimits             rateLimits;

    /**********************************************************************************************/
    /*** Casted addresses for testing                                                           ***/
    /**********************************************************************************************/

    IERC20 usdsBase;
    IERC20 susdsBase;
    IERC20 usdcBase;

    IPSM3 psmBase;

    /**********************************************************************************************/
    /*** Test setup                                                                             ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        /*** Step 1: Set up environment, deploy mock addresses ***/

        vm.createSelectFork(getChain('base').rpcUrl, _getBlock());

        usdsBase  = IERC20(address(new ERC20Mock()));
        susdsBase = IERC20(address(new ERC20Mock()));
        usdcBase  = IERC20(Base.USDC);

        /*** Step 2: Deploy and configure PSM with a pocket ***/

        deal(address(usdsBase), address(this), 1e18);  // For seeding PSM during deployment

        psmBase = IPSM3(PSM3Deploy.deploy(
            SPARK_EXECUTOR, Base.USDC, address(usdsBase), address(susdsBase), SSR_ORACLE
        ));

        vm.prank(SPARK_EXECUTOR);
        psmBase.setPocket(pocket);

        vm.prank(pocket);
        usdcBase.approve(address(psmBase), type(uint256).max);

        /*** Step 3: Deploy ALM system ***/

        almProxy   = new ALMProxy(SPARK_EXECUTOR);
        rateLimits = new RateLimits(SPARK_EXECUTOR);

        accessControls = new AccessControls(SPARK_EXECUTOR);

        foreignController = IForeignControllerFull(payable(new ForeignController({
            admin_          : SPARK_EXECUTOR,
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits),
            accessControls_ : address(accessControls),
            psm_            : address(psmBase),
            usdc_           : Base.USDC,
            cctp_           : CCTP_MESSENGER_BASE
        })));

        CONTROLLER = almProxy.CONTROLLER();
        FREEZER    = foreignController.FREEZER();
        RELAYER    = foreignController.RELAYER();

        vm.startPrank(SPARK_EXECUTOR);

        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);

        // Facet wiring

        _wireAaveFacet();
        _wireERC4626Facet();
        _wirePSM3Facet();
        _wireSparkVaultFacet();
        _wireTransferAssetFacet();

        vm.stopPrank();

        /*** Step 3: Configure ALM system through Spark governance (Spark spell payload) ***/

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;

        MintRecipient[] memory mintRecipients = new MintRecipient[](1);

        mintRecipients[0] = MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(makeAddr("ethereumAlmProxy"))))
        });

        vm.startPrank(SPARK_EXECUTOR);

        almProxy.grantRole(almProxy.CONTROLLER(),                address(foreignController));
        foreignController.grantRole(foreignController.FREEZER(), freezer);
        rateLimits.grantRole(rateLimits.CONTROLLER(),            address(foreignController));

        for (uint256 i; i < relayers.length; ++i) {
            foreignController.grantRole(foreignController.RELAYER(), relayers[i]);
        }

        for (uint256 i; i < mintRecipients.length; ++i) {
            foreignController.setMintRecipient(mintRecipients[i].domain, mintRecipients[i].mintRecipient);
        }

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;
        uint256 usdsMaxAmount = 5_000_000e18;
        uint256 usdsSlope     = uint256(1_000_000e18) / 4 hours;

        bytes32 depositKey  = foreignController.LIMIT_PSM_DEPOSIT();
        bytes32 withdrawKey = foreignController.LIMIT_PSM_WITHDRAW();

        bytes32 domainKeyEthereum = RateLimitHelpers.makeUint32Key(
            foreignController.LIMIT_USDC_TO_DOMAIN(),
            CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM
        );

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(depositKey,  address(usdcBase)),  usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(withdrawKey, address(usdcBase)),  usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(depositKey,  address(usdsBase)),  usdsMaxAmount, usdsSlope);
        rateLimits.setRateLimitData(RateLimitHelpers.makeAddressKey(depositKey,  address(susdsBase)), usdsMaxAmount, usdsSlope);
        rateLimits.setRateLimitData(foreignController.LIMIT_USDC_TO_CCTP(),                           usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(domainKeyEthereum,                                                usdcMaxAmount, usdcSlope);

        rateLimits.setUnlimitedRateLimitData(RateLimitHelpers.makeAddressKey(withdrawKey, address(usdsBase)));
        rateLimits.setUnlimitedRateLimitData(RateLimitHelpers.makeAddressKey(withdrawKey, address(susdsBase)));

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 20782500;  // October 8, 2024
    }

    function _setControllerEntered() internal {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        ( , bytes32[] memory writeSlots ) = vm.accesses(address(foreignController));

        uint256 count = 0;

        for (uint256 i = 0; i < writeSlots.length; ++i) {
            if (writeSlots[i] != _REENTRANCY_GUARD_SLOT) continue;

            ++count;
        }

        assertEq(count, 2);
        assertEq(vm.load(address(foreignController), _REENTRANCY_GUARD_SLOT), _REENTRANCY_GUARD_NOT_ENTERED);
    }

    function _absSubtraction(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /**********************************************************************************************/
    /*** Facet wiring helpers.                                                                  ***/
    /**********************************************************************************************/

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        vm.label(aaveFacet, "AaveFacet");

        // Controller.setAaveMaxSlippage() -> AaveFacet.setMaxSlippage()
        foreignController.setDispatch(
            IForeignControllerFull.setAaveMaxSlippage.selector,
            aaveFacet,
            IAaveFacet.setMaxSlippage.selector
        );

        // Controller.getAaveMaxSlippage() -> AaveFacet.getMaxSlippage()
        foreignController.setDispatch(
            IForeignControllerFull.getAaveMaxSlippage.selector,
            aaveFacet,
            IAaveFacet.getMaxSlippage.selector
        );

        // Controller.depositAave() -> AaveFacet.deposit()
        foreignController.setDispatch(
            IForeignControllerFull.depositAave.selector,
            aaveFacet,
            IAaveFacet.deposit.selector
        );

        // Controller.withdrawAave() -> AaveFacet.withdraw()
        foreignController.setDispatch(
            IForeignControllerFull.withdrawAave.selector,
            aaveFacet,
            IAaveFacet.withdraw.selector
        );

        // Controller.LIMIT_AAVE_DEPOSIT() -> AaveFacet.LIMIT_DEPOSIT()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_AAVE_DEPOSIT.selector,
            aaveFacet,
            IAaveFacet.LIMIT_DEPOSIT.selector
        );

        // Controller.LIMIT_AAVE_WITHDRAW() -> AaveFacet.LIMIT_WITHDRAW()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_AAVE_WITHDRAW.selector,
            aaveFacet,
            IAaveFacet.LIMIT_WITHDRAW.selector
        );
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        // Controller.setMaxExchangeRate() -> ERC4626Facet.setMaxExchangeRate()
        foreignController.setDispatch(
            IForeignControllerFull.setMaxExchangeRate.selector,
            erc4626Facet,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        // Controller.maxExchangeRates() -> ERC4626Facet.getMaxExchangeRate()
        foreignController.setDispatch(
            IForeignControllerFull.maxExchangeRates.selector,
            erc4626Facet,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        // Controller.depositERC4626() -> ERC4626Facet.deposit()
        foreignController.setDispatch(
            IForeignControllerFull.depositERC4626.selector,
            erc4626Facet,
            IERC4626Facet.deposit.selector
        );

        // Controller.withdrawERC4626() -> ERC4626Facet.withdraw()
        foreignController.setDispatch(
            IForeignControllerFull.withdrawERC4626.selector,
            erc4626Facet,
            IERC4626Facet.withdraw.selector
        );

        // Controller.redeemERC4626() -> ERC4626Facet.redeem()
        foreignController.setDispatch(
            IForeignControllerFull.redeemERC4626.selector,
            erc4626Facet,
            IERC4626Facet.redeem.selector
        );

        // Controller.LIMIT_4626_DEPOSIT() -> ERC4626Facet.LIMIT_DEPOSIT()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_4626_DEPOSIT.selector,
            erc4626Facet,
            IERC4626Facet.LIMIT_DEPOSIT.selector
        );

        // Controller.LIMIT_4626_WITHDRAW() -> ERC4626Facet.LIMIT_WITHDRAW()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_4626_WITHDRAW.selector,
            erc4626Facet,
            IERC4626Facet.LIMIT_WITHDRAW.selector
        );

        // Controller.EXCHANGE_RATE_PRECISION() -> ERC4626Facet.EXCHANGE_RATE_PRECISION()
        foreignController.setDispatch(
            IForeignControllerFull.EXCHANGE_RATE_PRECISION.selector,
            erc4626Facet,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );
    }

    function _wireSparkVaultFacet() internal {
        address sparkVaultFacet = address(new SparkVaultFacet());

        vm.label(sparkVaultFacet, "SparkVaultFacet");

        // "Controller.takeFromSparkVault()" -> "SparkVaultFacet.take()"
        foreignController.setDispatch(
            IForeignControllerFull.takeFromSparkVault.selector,
            sparkVaultFacet,
            ISparkVaultFacet.take.selector
        );

        // "Controller.LIMIT_SPARK_VAULT_TAKE()" -> "SparkVaultFacet.LIMIT_TAKE()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_SPARK_VAULT_TAKE.selector,
            sparkVaultFacet,
            ISparkVaultFacet.LIMIT_TAKE.selector
        );
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        // "Controller.transferAsset()" -> "TransferAssetFacet.transfer()"
        foreignController.setDispatch(
            IForeignControllerFull.transferAsset.selector,
            transferAssetFacet,
            ITransferAssetFacet.transfer.selector
        );

        // "Controller.LIMIT_ASSET_TRANSFER()" -> "TransferAssetFacet.LIMIT_TRANSFER()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_ASSET_TRANSFER.selector,
            transferAssetFacet,
            ITransferAssetFacet.LIMIT_TRANSFER.selector
        );
    }

    function _wirePSM3Facet() internal {
        address psm3Facet = address(new PSM3Facet(address(psmBase)));

        vm.label(psm3Facet, "PSM3Facet");

        // "Controller.depositPSM()" -> "PSM3Facet.deposit()"
        foreignController.setDispatch(
            IForeignControllerFull.depositPSM.selector,
            psm3Facet,
            IPSM3Facet.deposit.selector
        );

        // "Controller.withdrawPSM()" -> "PSM3Facet.withdraw()"
        foreignController.setDispatch(
            IForeignControllerFull.withdrawPSM.selector,
            psm3Facet,
            IPSM3Facet.withdraw.selector
        );

        // "Controller.LIMIT_PSM_DEPOSIT()" -> "PSM3Facet.LIMIT_DEPOSIT()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_PSM_DEPOSIT.selector,
            psm3Facet,
            IPSM3Facet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_PSM_WITHDRAW()" -> "PSM3Facet.LIMIT_WITHDRAW()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_PSM_WITHDRAW.selector,
            psm3Facet,
            IPSM3Facet.LIMIT_WITHDRAW.selector
        );
    }

}
