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

import { IController } from "../../src/interfaces/IController.sol";

import { AccessControls } from "../../src/AccessControls.sol";
import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { PAUFactory }     from "../../src/PAUFactory.sol";
import { RateLimits }     from "../../src/RateLimits.sol";

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
            accessControls_ : address(accessControls),
            factory_        : address(factory),
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits)
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

        vm.label(curveFacet, "CurveFacet");

        factory.setValidFacet(curveFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](8);

        wires[0] = IController.Wire(
            IForeignControllerFull.setCurveMaxSlippage.selector,
            ICurveFacet.setMaxSlippage.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.getCurveMaxSlippage.selector,
            ICurveFacet.getMaxSlippage.selector
        );

        wires[2] = IController.Wire(
            IForeignControllerFull.swapCurve.selector,
            ICurveFacet.swap.selector
        );

        wires[3] = IController.Wire(
            IForeignControllerFull.addLiquidityCurve.selector,
            ICurveFacet.addLiquidity.selector
        );

        wires[4] = IController.Wire(
            IForeignControllerFull.removeLiquidityCurve.selector,
            ICurveFacet.removeLiquidity.selector
        );

        wires[5] = IController.Wire(
            IForeignControllerFull.LIMIT_CURVE_DEPOSIT.selector,
            ICurveFacet.LIMIT_DEPOSIT.selector
        );

        wires[6] = IController.Wire(
            IForeignControllerFull.LIMIT_CURVE_SWAP.selector,
            ICurveFacet.LIMIT_SWAP.selector
        );

        wires[7] = IController.Wire(
            IForeignControllerFull.LIMIT_CURVE_WITHDRAW.selector,
            ICurveFacet.LIMIT_WITHDRAW.selector
        );

        foreignController.addWires(curveFacet, wires);
    }

    function _wireMerklFacet() internal {
        address merklFacet = address(new MerklFacet(GroveBase.MERKL_DISTRIBUTOR));

        factory.setValidFacet(merklFacet, true);

        vm.label(merklFacet, "MerklFacet");

        foreignController.addWire(
            merklFacet,
            IController.Wire(
                IForeignControllerFull.toggleOperatorMerkl.selector,
                IMerklFacet.toggleOperator.selector
            )
        );
    }

    function _wirePendleFacet() internal {
        address pendleFacet = address(new PendleFacet(GroveBase.PENDLE_ROUTER));

        vm.label(pendleFacet, "PendleFacet");

        factory.setValidFacet(pendleFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IForeignControllerFull.redeemPendlePT.selector,
            IPendleFacet.redeem.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.LIMIT_PENDLE_PT_REDEEM.selector,
            IPendleFacet.LIMIT_REDEEM.selector
        );

        foreignController.addWires(pendleFacet, wires);
    }

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        vm.label(aaveFacet, "AaveFacet");

        factory.setValidFacet(aaveFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](6);

        wires[0] = IController.Wire(
            IForeignControllerFull.setAaveMaxSlippage.selector,
            IAaveFacet.setMaxSlippage.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.getAaveMaxSlippage.selector,
            IAaveFacet.getMaxSlippage.selector
        );

        wires[2] = IController.Wire(
            IForeignControllerFull.depositAave.selector,
            IAaveFacet.deposit.selector
        );

        wires[3] = IController.Wire(
            IForeignControllerFull.withdrawAave.selector,
            IAaveFacet.withdraw.selector
        );

        wires[4] = IController.Wire(
            IForeignControllerFull.LIMIT_AAVE_DEPOSIT.selector,
            IAaveFacet.LIMIT_DEPOSIT.selector
        );

        wires[5] = IController.Wire(
            IForeignControllerFull.LIMIT_AAVE_WITHDRAW.selector,
            IAaveFacet.LIMIT_WITHDRAW.selector
        );

        foreignController.addWires(aaveFacet, wires);
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        factory.setValidFacet(erc4626Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](8);

        wires[0] = IController.Wire(
            IForeignControllerFull.setMaxExchangeRate.selector,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.maxExchangeRates.selector,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        wires[2] = IController.Wire(
            IForeignControllerFull.depositERC4626.selector,
            IERC4626Facet.deposit.selector
        );

        wires[3] = IController.Wire(
            IForeignControllerFull.withdrawERC4626.selector,
            IERC4626Facet.withdraw.selector
        );

        wires[4] = IController.Wire(
            IForeignControllerFull.redeemERC4626.selector,
            IERC4626Facet.redeem.selector
        );

        wires[5] = IController.Wire(
            IForeignControllerFull.LIMIT_4626_DEPOSIT.selector,
            IERC4626Facet.LIMIT_DEPOSIT.selector
        );

        wires[6] = IController.Wire(
            IForeignControllerFull.LIMIT_4626_WITHDRAW.selector,
            IERC4626Facet.LIMIT_WITHDRAW.selector
        );

        wires[7] = IController.Wire(
            IForeignControllerFull.EXCHANGE_RATE_PRECISION.selector,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );

        foreignController.addWires(erc4626Facet, wires);
    }

    function _wireSparkVaultFacet() internal {
        address sparkVaultFacet = address(new SparkVaultFacet());

        vm.label(sparkVaultFacet, "SparkVaultFacet");

        factory.setValidFacet(sparkVaultFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IForeignControllerFull.takeFromSparkVault.selector,
            ISparkVaultFacet.take.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.LIMIT_SPARK_VAULT_TAKE.selector,
            ISparkVaultFacet.LIMIT_TAKE.selector
        );

        foreignController.addWires(sparkVaultFacet, wires);
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        factory.setValidFacet(transferAssetFacet, true);

        IController.Wire[] memory wires = new IController.Wire[](2);

        wires[0] = IController.Wire(
            IForeignControllerFull.transferAsset.selector,
            ITransferAssetFacet.transfer.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.LIMIT_ASSET_TRANSFER.selector,
            ITransferAssetFacet.LIMIT_TRANSFER.selector
        );

        foreignController.addWires(transferAssetFacet, wires);
    }

    function _wirePSM3Facet() internal {
        address psm3Facet = address(new PSM3Facet(address(psmBase)));

        vm.label(psm3Facet, "PSM3Facet");

        factory.setValidFacet(psm3Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](4);

        wires[0] = IController.Wire(
            IForeignControllerFull.depositPSM.selector,
            IPSM3Facet.deposit.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.withdrawPSM.selector,
            IPSM3Facet.withdraw.selector
        );

        wires[2] = IController.Wire(
            IForeignControllerFull.LIMIT_PSM_DEPOSIT.selector,
            IPSM3Facet.LIMIT_DEPOSIT.selector
        );

        wires[3] = IController.Wire(
            IForeignControllerFull.LIMIT_PSM_WITHDRAW.selector,
            IPSM3Facet.LIMIT_WITHDRAW.selector
        );

        foreignController.addWires(psm3Facet, wires);
    }

    function _wireUniswapV3Facet() internal {
        address uniswapV3Facet = address(new UniswapV3Facet(UNISWAP_V3_POSITION_MANAGER, UNISWAP_V3_ROUTER));

        vm.label(uniswapV3Facet, "UniswapV3Facet");

        factory.setValidFacet(uniswapV3Facet, true);

        IController.Wire[] memory wires = new IController.Wire[](15);

        wires[0] = IController.Wire(
            IForeignControllerFull.addLiquidityUniswapV3.selector,
            IUniswapV3Facet.addLiquidity.selector
        );

        wires[1] = IController.Wire(
            IForeignControllerFull.removeLiquidityUniswapV3.selector,
            IUniswapV3Facet.removeLiquidity.selector
        );

        wires[2] = IController.Wire(
            IForeignControllerFull.swapUniswapV3.selector,
            IUniswapV3Facet.swap.selector
        );

        wires[3] = IController.Wire(
            IForeignControllerFull.setUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[4] = IController.Wire(
            IForeignControllerFull.setUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[5] = IController.Wire(
            IForeignControllerFull.setUniswapV3AddLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[6] = IController.Wire(
            IForeignControllerFull.setUniswapV3AddLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[7] = IController.Wire(
            IForeignControllerFull.setUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[8] = IController.Wire(
            IForeignControllerFull.LIMIT_UNISWAP_V3_DEPOSIT.selector,
            IUniswapV3Facet.LIMIT_DEPOSIT.selector
        );

        wires[9] = IController.Wire(
            IForeignControllerFull.LIMIT_UNISWAP_V3_SWAP.selector,
            IUniswapV3Facet.LIMIT_SWAP.selector
        );

        wires[10] = IController.Wire(
            IForeignControllerFull.LIMIT_UNISWAP_V3_WITHDRAW.selector,
            IUniswapV3Facet.LIMIT_WITHDRAW.selector
        );

        wires[11] = IController.Wire(
            IForeignControllerFull.getUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[12] = IController.Wire(
            IForeignControllerFull.getUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[13] = IController.Wire(
            IForeignControllerFull.getUniswapV3AddLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[14] = IController.Wire(
            IForeignControllerFull.getUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        foreignController.addWires(uniswapV3Facet, wires);
    }

}
