// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { Base as GroveBase } from "../../lib/grove-address-registry/src/Base.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "../../lib/spark-psm/src/PSM3.sol";

import { CCTPForwarder } from "../../lib/xchain-helpers/src/forwarders/CCTPForwarder.sol";

import { IAaveFacet }          from "../../src/facets/aave/IAaveFacet.sol";
import { ICurveFacet }         from "../../src/facets/curve/ICurveFacet.sol";
import { IERC4626Facet }       from "../../src/facets/erc4626/IERC4626Facet.sol";
import { IMerklFacet }         from "../../src/facets/merkl/IMerklFacet.sol";
import { IPendleFacet }        from "../../src/facets/pendle/IPendleFacet.sol";
import { IPSM3Facet }          from "../../src/facets/psm3/IPSM3Facet.sol";
import { ISparkVaultFacet }    from "../../src/facets/spark-vault/ISparkVaultFacet.sol";
import { ITransferAssetFacet } from "../../src/facets/transfer-asset/ITransferAssetFacet.sol";
import { IUniswapV3Facet }     from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

import { AaveFacet }          from "../../src/facets/aave/AaveFacet.sol";
import { CurveFacet }         from "../../src/facets/curve/CurveFacet.sol";
import { ERC4626Facet }       from "../../src/facets/erc4626/ERC4626Facet.sol";
import { MerklFacet }         from "../../src/facets/merkl/MerklFacet.sol";
import { PendleFacet }        from "../../src/facets/pendle/PendleFacet.sol";
import { PSM3Facet }          from "../../src/facets/psm3/PSM3Facet.sol";
import { SparkVaultFacet }    from "../../src/facets/spark-vault/SparkVaultFacet.sol";
import { TransferAssetFacet } from "../../src/facets/transfer-asset/TransferAssetFacet.sol";
import { UniswapV3Facet }     from "../../src/facets/uniswap-v3/UniswapV3Facet.sol";

import { makeAddressKey } from "../../src/libraries/RateLimitHelpers.sol";

import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { RateLimits }     from "../../src/RateLimits.sol";
import { AccessControls } from "../../src/AccessControls.sol";
import { PAUFactory }     from "../../src/PAUFactory.sol";

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

    address internal constant UNISWAP_V3_ROUTER           = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant UNISWAP_V3_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = bytes32(uint256(0));
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant RELAYER_ROLE       = keccak256("RELAYER");

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
    PAUFactory             factory;

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

        factory = new PAUFactory(SPARK_EXECUTOR, SPARK_EXECUTOR);

        foreignController = IForeignControllerFull(payable(new Controller({
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits),
            accessControls_ : address(accessControls),
            factory_        : address(factory)
        })));

        vm.startPrank(SPARK_EXECUTOR);

        accessControls.grantRole(accessControls.FREEZER_ROLE(), freezer);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), relayer);

        almProxy.grantRole(almProxy.CONTROLLER(), address(foreignController));

        rateLimits.grantRole(rateLimits.CONTROLLER(), address(foreignController));

        // Facet wiring
        _wireAaveFacet();
        _wireCurveFacet();
        _wireERC4626Facet();
        _wireMerklFacet();
        _wirePendleFacet();
        _wirePSM3Facet();
        _wireSparkVaultFacet();
        _wireTransferAssetFacet();
        _wireUniswapV3Facet();

        vm.stopPrank();

        /*** Step 4: Configure ALM system parameters through Spark governance ***/

        vm.startPrank(SPARK_EXECUTOR);

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;
        uint256 usdsMaxAmount = 5_000_000e18;
        uint256 usdsSlope     = uint256(1_000_000e18) / 4 hours;

        bytes32 depositKey  = foreignController.LIMIT_PSM_DEPOSIT();
        bytes32 withdrawKey = foreignController.LIMIT_PSM_WITHDRAW();

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(makeAddressKey(depositKey,  address(usdcBase)),  usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(makeAddressKey(withdrawKey, address(usdcBase)),  usdcMaxAmount, usdcSlope);
        rateLimits.setRateLimitData(makeAddressKey(depositKey,  address(usdsBase)),  usdsMaxAmount, usdsSlope);
        rateLimits.setRateLimitData(makeAddressKey(depositKey,  address(susdsBase)), usdsMaxAmount, usdsSlope);

        rateLimits.setUnlimitedRateLimitData(makeAddressKey(withdrawKey, address(usdsBase)));
        rateLimits.setUnlimitedRateLimitData(makeAddressKey(withdrawKey, address(susdsBase)));

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal pure virtual returns (uint256) {
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

    function _wireCurveFacet() internal {
        address curveFacet = address(new CurveFacet());

        factory.setValidFacet(curveFacet, true);

        vm.label(curveFacet, "CurveFacet");

        // Controller.setCurveMaxSlippage() -> CurveFacet.setMaxSlippage()
        foreignController.setDispatch(
            IForeignControllerFull.setCurveMaxSlippage.selector,
            curveFacet,
            ICurveFacet.setMaxSlippage.selector
        );

        // Controller.getCurveMaxSlippage() -> CurveFacet.getMaxSlippage()
        foreignController.setDispatch(
            IForeignControllerFull.getCurveMaxSlippage.selector,
            curveFacet,
            ICurveFacet.getMaxSlippage.selector
        );

        // Controller.swapCurve() -> CurveFacet.swap()
        foreignController.setDispatch(
            IForeignControllerFull.swapCurve.selector,
            curveFacet,
            ICurveFacet.swap.selector
        );

        // Controller.addLiquidityCurve() -> CurveFacet.addLiquidity()
        foreignController.setDispatch(
            IForeignControllerFull.addLiquidityCurve.selector,
            curveFacet,
            ICurveFacet.addLiquidity.selector
        );

        // Controller.removeLiquidityCurve() -> CurveFacet.removeLiquidity()
        foreignController.setDispatch(
            IForeignControllerFull.removeLiquidityCurve.selector,
            curveFacet,
            ICurveFacet.removeLiquidity.selector
        );

        // Controller.LIMIT_CURVE_DEPOSIT() -> CurveFacet.LIMIT_DEPOSIT()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_CURVE_DEPOSIT.selector,
            curveFacet,
            ICurveFacet.LIMIT_DEPOSIT.selector
        );

        // Controller.LIMIT_CURVE_SWAP() -> CurveFacet.LIMIT_SWAP()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_CURVE_SWAP.selector,
            curveFacet,
            ICurveFacet.LIMIT_SWAP.selector
        );

        // Controller.LIMIT_CURVE_WITHDRAW() -> CurveFacet.LIMIT_WITHDRAW()
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_CURVE_WITHDRAW.selector,
            curveFacet,
            ICurveFacet.LIMIT_WITHDRAW.selector
        );
    }

    function _wireMerklFacet() internal {
        address merklFacet = address(new MerklFacet(GroveBase.MERKL_DISTRIBUTOR));

        factory.setValidFacet(merklFacet, true);

        vm.label(merklFacet, "MerklFacet");

        // "Controller.toggleOperatorMerkl()" -> "MerklFacet.toggleOperator()"
        foreignController.setDispatch(
            IForeignControllerFull.toggleOperatorMerkl.selector,
            merklFacet,
            IMerklFacet.toggleOperator.selector
        );
    }

    function _wirePendleFacet() internal {
        address pendleFacet = address(new PendleFacet(GroveBase.PENDLE_ROUTER));

        factory.setValidFacet(pendleFacet, true);

        vm.label(pendleFacet, "PendleFacet");

        // "Controller.redeemPendlePT()" -> "PendleFacet.redeem()"
        foreignController.setDispatch(
            IForeignControllerFull.redeemPendlePT.selector,
            pendleFacet,
            IPendleFacet.redeem.selector
        );

        // "Controller.LIMIT_PENDLE_PT_REDEEM()" -> "PendleFacet.LIMIT_REDEEM()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_PENDLE_PT_REDEEM.selector,
            pendleFacet,
            IPendleFacet.LIMIT_REDEEM.selector
        );
    }

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        factory.setValidFacet(aaveFacet, true);

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

        factory.setValidFacet(erc4626Facet, true);

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

        factory.setValidFacet(sparkVaultFacet, true);

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

        factory.setValidFacet(transferAssetFacet, true);

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

        factory.setValidFacet(psm3Facet, true);

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

    function _wireUniswapV3Facet() internal {
        address uniswapV3Facet = address(new UniswapV3Facet(UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_ROUTER));

        factory.setValidFacet(uniswapV3Facet, true);

        vm.label(uniswapV3Facet, "UniswapV3Facet");

        // Controller.addLiquidityUniswapV3 -> UniswapV3Facet.addLiquidity
        foreignController.setDispatch(
            IForeignControllerFull.addLiquidityUniswapV3.selector,
            uniswapV3Facet,
            IUniswapV3Facet.addLiquidity.selector
        );

        // Controller.removeLiquidityUniswapV3 -> UniswapV3Facet.removeLiquidity
        foreignController.setDispatch(
            IForeignControllerFull.removeLiquidityUniswapV3.selector,
            uniswapV3Facet,
            IUniswapV3Facet.removeLiquidity.selector
        );

        // Controller.swapUniswapV3 -> UniswapV3Facet.swap
        foreignController.setDispatch(
            IForeignControllerFull.swapUniswapV3.selector,
            uniswapV3Facet,
            IUniswapV3Facet.swap.selector
        );

        // Controller.setUniswapV3MaxSlippage -> UniswapV3Facet.setMaxSlippage
        foreignController.setDispatch(
            IForeignControllerFull.setUniswapV3MaxSlippage.selector,
            uniswapV3Facet,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        // Controller.setUniswapV3PoolMaxTickDelta -> UniswapV3Facet.setMaxTickDelta
        foreignController.setDispatch(
            IForeignControllerFull.setUniswapV3PoolMaxTickDelta.selector,
            uniswapV3Facet,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        // Controller.setUniswapV3AddLiquidityLowerTickBound -> UniswapV3Facet.setLiquidityLowerTickBound
        foreignController.setDispatch(
            IForeignControllerFull.setUniswapV3AddLiquidityLowerTickBound.selector,
            uniswapV3Facet,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        // Controller.setUniswapV3AddLiquidityUpperTickBound -> UniswapV3Facet.setLiquidityUpperTickBound
        foreignController.setDispatch(
            IForeignControllerFull.setUniswapV3AddLiquidityUpperTickBound.selector,
            uniswapV3Facet,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        // Controller.setUniswapV3TWAPSecondsAgo -> UniswapV3Facet.setTWAPSecondsAgo
        foreignController.setDispatch(
            IForeignControllerFull.setUniswapV3TWAPSecondsAgo.selector,
            uniswapV3Facet,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        // Controller.LIMIT_UNISWAP_V3_DEPOSIT -> UniswapV3Facet.LIMIT_DEPOSIT
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_UNISWAP_V3_DEPOSIT.selector,
            uniswapV3Facet,
            IUniswapV3Facet.LIMIT_DEPOSIT.selector
        );

        // Controller.LIMIT_UNISWAP_V3_SWAP -> UniswapV3Facet.LIMIT_SWAP
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_UNISWAP_V3_SWAP.selector,
            uniswapV3Facet,
            IUniswapV3Facet.LIMIT_SWAP.selector
        );

        // Controller.LIMIT_UNISWAP_V3_WITHDRAW -> UniswapV3Facet.LIMIT_WITHDRAW
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_UNISWAP_V3_WITHDRAW.selector,
            uniswapV3Facet,
            IUniswapV3Facet.LIMIT_WITHDRAW.selector
        );

        // Controller.getUniswapV3MaxSlippage -> UniswapV3Facet.getMaxSlippag
        foreignController.setDispatch(
            IForeignControllerFull.getUniswapV3MaxSlippage.selector,
            uniswapV3Facet,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        // Controller.getUniswapV3PoolMaxTickDelta -> UniswapV3Facet.getMaxTickDelta
        foreignController.setDispatch(
            IForeignControllerFull.getUniswapV3PoolMaxTickDelta.selector,
            uniswapV3Facet,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        // Controller.getUniswapV3AddLiquidityTickBounds -> UniswapV3Facet.getLiquidityTickBounds
        foreignController.setDispatch(
            IForeignControllerFull.getUniswapV3AddLiquidityTickBounds.selector,
            uniswapV3Facet,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        // Controller.getUniswapV3TWAPSecondsAgo -> UniswapV3Facet.getTWAPSecondsAgo
        foreignController.setDispatch(
            IForeignControllerFull.getUniswapV3TWAPSecondsAgo.selector,
            uniswapV3Facet,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

    }

}
