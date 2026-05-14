// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Base } from "../../lib/spark-address-registry/src/Base.sol";

import { Base as GroveBase } from "../../lib/grove-address-registry/src/Base.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "../../lib/spark-psm/src/PSM3.sol";

import { IAaveFacet }          from "../../src/facets/aave/IAaveFacet.sol";
import { IERC4626Facet }       from "../../src/facets/erc4626/IERC4626Facet.sol";
import { IMerklFacet }         from "../../src/facets/merkl/IMerklFacet.sol";
import { IPendleFacet }        from "../../src/facets/pendle/IPendleFacet.sol";
import { IPSM3Facet }          from "../../src/facets/psm3/IPSM3Facet.sol";
import { ISparkVaultFacet }    from "../../src/facets/spark-vault/ISparkVaultFacet.sol";
import { ITransferAssetFacet } from "../../src/facets/transfer-asset/ITransferAssetFacet.sol";
import { IUniswapV3Facet }     from "../../src/facets/uniswap-v3/IUniswapV3Facet.sol";

import { AaveFacet }          from "../../src/facets/aave/AaveFacet.sol";
import { ERC4626Facet }       from "../../src/facets/erc4626/ERC4626Facet.sol";
import { MerklFacet }         from "../../src/facets/merkl/MerklFacet.sol";
import { PendleFacet }        from "../../src/facets/pendle/PendleFacet.sol";
import { PSM3Facet }          from "../../src/facets/psm3/PSM3Facet.sol";
import { SparkVaultFacet }    from "../../src/facets/spark-vault/SparkVaultFacet.sol";
import { TransferAssetFacet } from "../../src/facets/transfer-asset/TransferAssetFacet.sol";
import { UniswapV3Facet }     from "../../src/facets/uniswap-v3/UniswapV3Facet.sol";

import { IAccessControls }         from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }               from "../../src/interfaces/IALMProxy.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";
import { IRateLimits }             from "../../src/interfaces/IRateLimits.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

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

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _REENTRANCY_GUARD_SLOT        = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;
    bytes32 internal constant _REENTRANCY_GUARD_NOT_ENTERED = bytes32(uint256(1));
    bytes32 internal constant _REENTRANCY_GUARD_ENTERED     = bytes32(uint256(2));

    bytes32 constant ALLOCATOR_ROLE       = keccak256("ALLOCATOR_ROLE");
    bytes32 constant ALLOCATOR_ADMIN_ROLE = keccak256("ALLOCATOR_ADMIN_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE   = 0x00;

    address allocator      = Base.ALM_RELAYER_MULTISIG;
    address allocatorAdmin = Base.ALM_FREEZER_MULTISIG;

    address pocket   = makeAddr("pocket");
    address skyAdmin = makeAddr("skyAdmin");

    /**********************************************************************************************/
    /*** Base addresses                                                                         ***/
    /**********************************************************************************************/

    address constant SPARK_EXECUTOR = Base.SPARK_EXECUTOR;
    address constant SSR_ORACLE     = Base.SSR_AUTH_ORACLE;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    Beacon                 beacon;
    IAccessControls        accessControls;
    IALMProxy              almProxy;
    IForeignControllerFull foreignController;
    IRateLimits            rateLimits;
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

        beacon  = new Beacon(skyAdmin);
        factory = new PAUFactory(address(beacon));

        foreignController = IForeignControllerFull(payable(factory.deploy(SPARK_EXECUTOR)));
        accessControls    = IAccessControls(foreignController.accessControls());
        almProxy          = IALMProxy(payable(foreignController.proxy()));
        rateLimits        = IRateLimits(foreignController.rateLimits());

        vm.startPrank(skyAdmin);

        // Facet wiring
        _wireAaveFacet();
        _wireERC4626Facet();
        _wireMerklFacet();
        _wirePendleFacet();
        _wirePSM3Facet();
        _wireSparkVaultFacet();
        _wireTransferAssetFacet();
        _wireUniswapV3Facet();

        vm.stopPrank();

        vm.startPrank(SPARK_EXECUTOR);

        accessControls.grantRole(ALLOCATOR_ROLE,       allocator);
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, allocatorAdmin);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role
        //       logic that calls into AccessControls to perform grants and revocations.
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        bytes32[] memory integrationIds = new bytes32[](8);
        integrationIds[0] = "AAVE_FACET";
        integrationIds[1] = "ERC4626_FACET";
        integrationIds[2] = "MERKL_FACET";
        integrationIds[3] = "PENDLE_FACET";
        integrationIds[4] = "PSM3_FACET";
        integrationIds[5] = "SPARK_VAULT_FACET";
        integrationIds[6] = "TRANSFER_ASSET_FACET";
        integrationIds[7] = "UNISWAP_V3_FACET";

        foreignController.updateIntegrations(integrationIds);

        /*** Step 4: Configure ALM system parameters through Spark governance ***/

        uint256 usdcMaxAmount = 5_000_000e6;
        uint256 usdcSlope     = uint256(1_000_000e6) / 4 hours;
        uint256 usdsMaxAmount = 5_000_000e18;
        uint256 usdsSlope     = uint256(1_000_000e18) / 4 hours;

        // NOTE: Using minimal config for test base setup
        rateLimits.setRateLimitData(
            foreignController.getPSMDepositRateLimitKey(address(usdcBase)),
            usdcMaxAmount,
            usdcSlope
        );

        rateLimits.setRateLimitData(
            foreignController.getPSMWithdrawRateLimitKey(address(usdcBase)),
            usdcMaxAmount,
            usdcSlope
        );

        rateLimits.setRateLimitData(
            foreignController.getPSMDepositRateLimitKey(address(usdsBase)),
            usdsMaxAmount,
            usdsSlope
        );

        rateLimits.setRateLimitData(
            foreignController.getPSMDepositRateLimitKey(address(susdsBase)),
            usdsMaxAmount,
            usdsSlope
        );

        rateLimits.setUnlimitedRateLimitData(
            foreignController.getPSMWithdrawRateLimitKey(address(usdsBase))
        );

        rateLimits.setUnlimitedRateLimitData(
            foreignController.getPSMWithdrawRateLimitKey(address(susdsBase))
        );

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
    /*** Facet wiring helpers                                                                   ***/
    /**********************************************************************************************/

    function _wireAaveFacet() internal {
        address aaveFacet = address(new AaveFacet());

        vm.label(aaveFacet, "AaveFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setAaveMaxSlippage.selector,
            IAaveFacet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getAaveMaxSlippage.selector,
            IAaveFacet.getMaxSlippage.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.depositAave.selector,
            IAaveFacet.deposit.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.withdrawAave.selector,
            IAaveFacet.withdraw.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getAaveDepositRateLimitKey.selector,
            IAaveFacet.getDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getAaveWithdrawRateLimitKey.selector,
            IAaveFacet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : aaveFacet,
            wires : wires
        });

        beacon.setIntegration("AAVE_FACET", config);
    }

    function _wireERC4626Facet() internal {
        address erc4626Facet = address(new ERC4626Facet());

        vm.label(erc4626Facet, "ERC4626Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](8);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setMaxExchangeRate.selector,
            IERC4626Facet.setMaxExchangeRate.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.depositERC4626.selector,
            IERC4626Facet.deposit.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.withdrawERC4626.selector,
            IERC4626Facet.withdraw.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.redeemERC4626.selector,
            IERC4626Facet.redeem.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.EXCHANGE_RATE_PRECISION.selector,
            IERC4626Facet.EXCHANGE_RATE_PRECISION.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.maxExchangeRates.selector,
            IERC4626Facet.getMaxExchangeRate.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getERC4626DepositRateLimitKey.selector,
            IERC4626Facet.getDepositRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getERC4626WithdrawRateLimitKey.selector,
            IERC4626Facet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : erc4626Facet,
            wires : wires
        });

        beacon.setIntegration("ERC4626_FACET", config);
    }

    function _wireMerklFacet() internal {
        address merklFacet = address(new MerklFacet());

        vm.label(merklFacet, "MerklFacet");

        IEnumerableIntegrations.Wire[] memory merklWires = new IEnumerableIntegrations.Wire[](2);

        merklWires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.toggleOperatorMerkl.selector,
            IMerklFacet.toggleOperator.selector
        );

        merklWires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getMerklToggleOperatorRateLimitKey.selector,
            IMerklFacet.getToggleOperatorRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : merklFacet,
            wires : merklWires
        });

        beacon.setIntegration("MERKL_FACET", config);
    }

    function _wirePendleFacet() internal {
        address pendleFacet = address(new PendleFacet(GroveBase.PENDLE_ROUTER));

        vm.label(pendleFacet, "PendleFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.redeemPendlePT.selector,
            IPendleFacet.redeem.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getPendleRedeemRateLimitKey.selector,
            IPendleFacet.getRedeemRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : pendleFacet,
            wires : wires
        });

        beacon.setIntegration("PENDLE_FACET", config);
    }

    function _wirePSM3Facet() internal {
        address psm3Facet = address(new PSM3Facet(address(psmBase)));

        vm.label(psm3Facet, "PSM3Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](4);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.depositPSM.selector,
            IPSM3Facet.deposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.withdrawPSM.selector,
            IPSM3Facet.withdraw.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getPSMDepositRateLimitKey.selector,
            IPSM3Facet.getDepositRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getPSMWithdrawRateLimitKey.selector,
            IPSM3Facet.getWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : psm3Facet,
            wires : wires
        });

        beacon.setIntegration("PSM3_FACET", config);
    }

    function _wireSparkVaultFacet() internal {
        address sparkVaultFacet = address(new SparkVaultFacet());

        vm.label(sparkVaultFacet, "SparkVaultFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.takeFromSparkVault.selector,
            ISparkVaultFacet.take.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getSparkVaultTakeRateLimitKey.selector,
            ISparkVaultFacet.getTakeRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : sparkVaultFacet,
            wires : wires
        });

        beacon.setIntegration("SPARK_VAULT_FACET", config);
    }

    function _wireTransferAssetFacet() internal {
        address transferAssetFacet = address(new TransferAssetFacet());

        vm.label(transferAssetFacet, "TransferAssetFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](2);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.transferAsset.selector,
            ITransferAssetFacet.transfer.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getTransferAssetTransferRateLimitKey.selector,
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
            IForeignControllerFull.setUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.setMaxSlippage.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.setMaxTickDelta.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setUniswapV3AddLiquidityLowerTickBound.selector,
            IUniswapV3Facet.setLiquidityLowerTickBound.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setUniswapV3AddLiquidityUpperTickBound.selector,
            IUniswapV3Facet.setLiquidityUpperTickBound.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.setUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.setTWAPSecondsAgo.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.swapUniswapV3.selector,
            IUniswapV3Facet.swap.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.addLiquidityUniswapV3.selector,
            IUniswapV3Facet.addLiquidity.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.removeLiquidityUniswapV3.selector,
            IUniswapV3Facet.removeLiquidity.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3MaxSlippage.selector,
            IUniswapV3Facet.getMaxSlippage.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3PoolMaxTickDelta.selector,
            IUniswapV3Facet.getMaxTickDelta.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3AddLiquidityTickBounds.selector,
            IUniswapV3Facet.getLiquidityTickBounds.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3TWAPSecondsAgo.selector,
            IUniswapV3Facet.getTWAPSecondsAgo.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3AggregateDepositRateLimitKey.selector,
            IUniswapV3Facet.getAggregateDepositRateLimitKey.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3AssetDepositRateLimitKey.selector,
            IUniswapV3Facet.getAssetDepositRateLimitKey.selector
        );

        wires[14] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3SwapRateLimitKey.selector,
            IUniswapV3Facet.getSwapRateLimitKey.selector
        );

        wires[15] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3AggregateWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getAggregateWithdrawRateLimitKey.selector
        );

        wires[16] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.getUniswapV3AssetWithdrawRateLimitKey.selector,
            IUniswapV3Facet.getAssetWithdrawRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : uniswapV3Facet,
            wires : wires
        });

        beacon.setIntegration("UNISWAP_V3_FACET", config);
    }

}
