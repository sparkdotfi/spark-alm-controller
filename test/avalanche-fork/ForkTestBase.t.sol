// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Avalanche } from "../../lib/grove-address-registry/src/Avalanche.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "../../lib/spark-psm/src/PSM3.sol";

import { IFacet } from "../../src/facets/IFacet.sol";

import { ICentrifugeFacet } from "../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { IERC7540Facet }    from "../../src/facets/erc7540/IERC7540Facet.sol";

import { CentrifugeFacet } from "../../src/facets/centrifuge/CentrifugeFacet.sol";
import { ERC7540Facet }    from "../../src/facets/erc7540/ERC7540Facet.sol";

import { IAccessControls }         from "../../src/interfaces/IAccessControls.sol";
import { IALMProxy }               from "../../src/interfaces/IALMProxy.sol";
import { IEnumerableIntegrations } from "../../src/interfaces/IEnumerableIntegrations.sol";
import { IRateLimits }             from "../../src/interfaces/IRateLimits.sol";

import { Beacon }     from "../../src/Beacon.sol";
import { PAUFactory } from "../../src/PAUFactory.sol";

import { IForeignControllerFull } from "../interfaces/IForeignControllerFull.sol";

contract MockSSROracle {

    function getConversionRate() external pure returns (uint256) {
        return 1e18;
    }

}

contract ForkTestBase is Test {

    struct MintRecipient {
        uint32  domain;
        bytes32 mintRecipient;
    }

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    bytes32 constant ALLOCATOR_ROLE       = keccak256("ALLOCATOR_ROLE");
    bytes32 constant ALLOCATOR_ADMIN_ROLE = keccak256("ALLOCATOR_ADMIN_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE   = 0x00;

    address pocket   = makeAddr("pocket");
    address skyAdmin = makeAddr("skyAdmin");

    /**********************************************************************************************/
    /*** Avalanche addresses                                                                    ***/
    /**********************************************************************************************/

    address constant ALLOCATOR                   = Avalanche.ALM_RELAYER;
    address constant ALLOCATOR_ADMIN             = Avalanche.ALM_FREEZER;
    address constant GROVE_EXECUTOR              = Avalanche.GROVE_EXECUTOR;
    address constant USDC_AVALANCHE              = Avalanche.USDC;
    address constant UNISWAP_V3_ROUTER           = 0xbb00FF08d01D300023C629E8fFfFcb65A5a578cE;
    address constant UNISWAP_V3_POSITION_MANAGER = 0x655C406EBFa14EE2006250925e54ec43AD184f8B;

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
    /*** Addresses for testing                                                                  ***/
    /**********************************************************************************************/

    IERC20 usdsAvalanche;
    IERC20 susdsAvalanche;
    IERC20 usdcAvalanche;

    IPSM3 psmAvalanche;

    MockSSROracle ssrOracle;

    /**********************************************************************************************/
    /*** Test setup                                                                             ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        /*** Step 1: Set up environment, deploy mock addresses ***/

        vm.createSelectFork(getChain('avalanche').rpcUrl, _getBlock());

        usdsAvalanche  = IERC20(address(new ERC20Mock()));
        susdsAvalanche = IERC20(address(new ERC20Mock()));
        usdcAvalanche  = IERC20(USDC_AVALANCHE);

        ssrOracle = new MockSSROracle();

        /*** Step 2: Deploy and configure PSM with a pocket ***/

        deal(address(usdsAvalanche), address(this), 1e18);  // For seeding PSM during deployment

        psmAvalanche = IPSM3(PSM3Deploy.deploy(
            GROVE_EXECUTOR, USDC_AVALANCHE, address(usdsAvalanche), address(susdsAvalanche), address(ssrOracle)
        ));

        vm.prank(GROVE_EXECUTOR);
        psmAvalanche.setPocket(pocket);

        vm.prank(pocket);
        usdcAvalanche.approve(address(psmAvalanche), type(uint256).max);

        /*** Step 3: Deploy ALM system ***/

        beacon  = new Beacon(skyAdmin);
        factory = new PAUFactory(address(beacon));

        foreignController = IForeignControllerFull(payable(factory.deploy(GROVE_EXECUTOR)));
        accessControls    = IAccessControls(foreignController.accessControls());
        almProxy          = IALMProxy(payable(foreignController.proxy()));
        rateLimits        = IRateLimits(foreignController.rateLimits());

        vm.startPrank(skyAdmin);

        // Facet wiring
        _wireCentrifugeFacet();
        _wireERC7540Facet();

        vm.stopPrank();

        vm.startPrank(GROVE_EXECUTOR);

        accessControls.grantRole(ALLOCATOR_ROLE,       ALLOCATOR);
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, ALLOCATOR_ADMIN);

        // NOTE: In practice the ALLOCATOR_ADMIN_ROLE will be a wrapper module with custom role 
        //       logic that calls into AccessControls to perform grants and revocations.
        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        bytes32[] memory integrationIds = new bytes32[](2);
        integrationIds[0] = "CENTRIFUGE_FACET";
        integrationIds[1] = "ERC7540_FACET";

        foreignController.updateIntegrations(integrationIds);

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal pure virtual returns (uint256) {
        return 65896755;  // July 22, 2025
    }

    /**********************************************************************************************/
    /*** Facet wiring helpers                                                                   ***/
    /**********************************************************************************************/

    function _wireCentrifugeFacet() internal {
        // NOTE: We are NOT wiring DEPOSIT, REDEEM keys, as they already wired in _wireERC7540Facet.

        address centrifugeFacet = address(new CentrifugeFacet());

        vm.label(centrifugeFacet, "CentrifugeFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](14);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_setRecipient.selector,
            ICentrifugeFacet.setRecipient.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_cancelDepositRequest.selector,
            ICentrifugeFacet.cancelDepositRequest.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_claimCancelDepositRequest.selector,
            ICentrifugeFacet.claimCancelDepositRequest.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_cancelRedeemRequest.selector,
            ICentrifugeFacet.cancelRedeemRequest.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_claimCancelRedeemRequest.selector,
            ICentrifugeFacet.claimCancelRedeemRequest.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_transferShares.selector,
            ICentrifugeFacet.transferShares.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_getRecipient.selector,
            ICentrifugeFacet.getRecipient.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_getCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getCancelDepositRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_getClaimCancelDepositRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelDepositRateLimitKey.selector
        );

        wires[9] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_getCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getCancelRedeemRateLimitKey.selector
        );

        wires[10] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_getClaimCancelRedeemRateLimitKey.selector,
            ICentrifugeFacet.getClaimCancelRedeemRateLimitKey.selector
        );

        wires[11] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_getTransferRateLimitKey.selector,
            ICentrifugeFacet.getTransferRateLimitKey.selector
        );

        wires[12] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_VERSION.selector,
            IFacet.VERSION.selector
        );

        wires[13] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.centrifuge_REQUEST_ID.selector,
            ICentrifugeFacet.REQUEST_ID.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : centrifugeFacet,
            wires : wires
        });

        beacon.setIntegration("CENTRIFUGE_FACET", config);
    }

    function _wireERC7540Facet() internal {
        address erc7540Facet = address(new ERC7540Facet());

        vm.label(erc7540Facet, "ERC7540Facet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](9);

        wires[0] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_requestDeposit.selector,
            IERC7540Facet.requestDeposit.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_claimDeposit.selector,
            IERC7540Facet.claimDeposit.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_requestRedeem.selector,
            IERC7540Facet.requestRedeem.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_claimRedeem.selector,
            IERC7540Facet.claimRedeem.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_getRequestDepositRateLimitKey.selector,
            IERC7540Facet.getRequestDepositRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_getClaimDepositRateLimitKey.selector,
            IERC7540Facet.getClaimDepositRateLimitKey.selector
        );

        wires[6] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_getRequestRedeemRateLimitKey.selector,
            IERC7540Facet.getRequestRedeemRateLimitKey.selector
        );

        wires[7] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_getClaimRedeemRateLimitKey.selector,
            IERC7540Facet.getClaimRedeemRateLimitKey.selector
        );

        wires[8] = IEnumerableIntegrations.Wire(
            IForeignControllerFull.erc7540_VERSION.selector,
            IFacet.VERSION.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config({
            facet : erc7540Facet,
            wires : wires
        });

        beacon.setIntegration("ERC7540_FACET", config);
    }

}
