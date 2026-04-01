// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Avalanche } from "../../lib/grove-address-registry/src/Avalanche.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "../../lib/spark-psm/src/PSM3.sol";

import { ICentrifugeFacet } from "../../src/facets/centrifuge/ICentrifugeFacet.sol";
import { IERC7540Facet }    from "../../src/facets/erc7540/IERC7540Facet.sol";

import { CentrifugeFacet } from "../../src/facets/centrifuge/CentrifugeFacet.sol";
import { ERC7540Facet }    from "../../src/facets/erc7540/ERC7540Facet.sol";

import { ALMProxy }       from "../../src/ALMProxy.sol";
import { Controller }     from "../../src/Controller.sol";
import { RateLimits }     from "../../src/RateLimits.sol";
import { AccessControls } from "../../src/AccessControls.sol";

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

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant RELAYER_ROLE       = keccak256("RELAYER");

    address pocket = makeAddr("pocket");

    /**********************************************************************************************/
    /*** Avalanche addresses                                                                   ***/
    /**********************************************************************************************/

    address constant ALM_FREEZER                 = Avalanche.ALM_FREEZER;
    address constant ALM_RELAYER                 = Avalanche.ALM_RELAYER;
    address constant CCTP_TOKEN_MESSENGER        = Avalanche.CCTP_TOKEN_MESSENGER_V2;
    address constant GROVE_EXECUTOR              = Avalanche.GROVE_EXECUTOR;
    address constant USDC_AVALANCHE              = Avalanche.USDC;
    address constant UNISWAP_V3_ROUTER           = 0xbb00FF08d01D300023C629E8fFfFcb65A5a578cE;
    address constant UNISWAP_V3_POSITION_MANAGER = 0x655C406EBFa14EE2006250925e54ec43AD184f8B;

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    AccessControls         accessControls;
    ALMProxy               almProxy;
    IForeignControllerFull foreignController;
    RateLimits             rateLimits;

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

        almProxy   = new ALMProxy(GROVE_EXECUTOR);
        rateLimits = new RateLimits(GROVE_EXECUTOR);

        accessControls = new AccessControls(GROVE_EXECUTOR);

        foreignController = IForeignControllerFull(payable(new Controller({
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits),
            accessControls_ : address(accessControls)
        })));

        vm.startPrank(GROVE_EXECUTOR);

        accessControls.grantRole(accessControls.FREEZER_ROLE(), ALM_FREEZER);
        accessControls.grantRole(accessControls.RELAYER_ROLE(), ALM_RELAYER);

        almProxy.grantRole(almProxy.CONTROLLER(), address(foreignController));

        rateLimits.grantRole(rateLimits.CONTROLLER(), address(foreignController));

        // Facet wiring
        _wireCentrifugeFacet();
        _wireERC7540Facet();

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal pure virtual returns (uint256) {
        return 65896755;  // July 22, 2025
    }

    /**********************************************************************************************/
    /*** Facet wiring helpers.                                                                  ***/
    /**********************************************************************************************/

    function _wireCentrifugeFacet() internal {
        // NOTE: We are NOT wiring DEPOSIT, REDEEM keys, as they already wired in _wireERC7540Facet.

        address centrifugeFacet = address(new CentrifugeFacet());

        vm.label(centrifugeFacet, "CentrifugeFacet");

        // "Controller.setCentrifugeRecipient()" -> "CentrifugeFacet.setRecipient()"
        foreignController.setDispatch(
            IForeignControllerFull.setCentrifugeRecipient.selector,
            centrifugeFacet,
            ICentrifugeFacet.setRecipient.selector
        );

        // "Controller.cancelCentrifugeDepositRequest()" -> "CentrifugeFacet.cancelDepositRequest()"
        foreignController.setDispatch(
            IForeignControllerFull.cancelCentrifugeDepositRequest.selector,
            centrifugeFacet,
            ICentrifugeFacet.cancelDepositRequest.selector
        );

        // "Controller.claimCentrifugeCancelDepositRequest()" -> "CentrifugeFacet.claimCancelDepositRequest()"
        foreignController.setDispatch(
            IForeignControllerFull.claimCentrifugeCancelDepositRequest.selector,
            centrifugeFacet,
            ICentrifugeFacet.claimCancelDepositRequest.selector
        );

        // "Controller.cancelCentrifugeRedeemRequest()" -> "CentrifugeFacet.cancelRedeemRequest()"
        foreignController.setDispatch(
            IForeignControllerFull.cancelCentrifugeRedeemRequest.selector,
            centrifugeFacet,
            ICentrifugeFacet.cancelRedeemRequest.selector
        );

        // "Controller.claimCentrifugeCancelRedeemRequest()" -> "CentrifugeFacet.claimCancelRedeemRequest()"
        foreignController.setDispatch(
            IForeignControllerFull.claimCentrifugeCancelRedeemRequest.selector,
            centrifugeFacet,
            ICentrifugeFacet.claimCancelRedeemRequest.selector
        );

        // "Controller.transferSharesCentrifuge()" -> "CentrifugeFacet.transferShares()"
        foreignController.setDispatch(
            IForeignControllerFull.transferSharesCentrifuge.selector,
            centrifugeFacet,
            ICentrifugeFacet.transferShares.selector
        );

        // "Controller.LIMIT_CENTRIFUGE_TRANSFER()" -> "CentrifugeFacet.LIMIT_TRANSFER()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_CENTRIFUGE_TRANSFER.selector,
            centrifugeFacet,
            ICentrifugeFacet.LIMIT_TRANSFER.selector
        );

        // "Controller.getCentrifugeRecipient()" -> "CentrifugeFacet.getRecipient()"
        foreignController.setDispatch(
            IForeignControllerFull.getCentrifugeRecipient.selector,
            centrifugeFacet,
            ICentrifugeFacet.getRecipient.selector
        );
    }

    function _wireERC7540Facet() internal {
        address erc7540Facet = address(new ERC7540Facet());

        vm.label(erc7540Facet, "ERC7540Facet");

        // "Controller.requestDepositERC7540()" -> "ERC7540Facet.requestDeposit()"
        foreignController.setDispatch(
            IForeignControllerFull.requestDepositERC7540.selector,
            erc7540Facet,
            IERC7540Facet.requestDeposit.selector
        );

        // "Controller.claimDepositERC7540()" -> "ERC7540Facet.claimDeposit()"
        foreignController.setDispatch(
            IForeignControllerFull.claimDepositERC7540.selector,
            erc7540Facet,
            IERC7540Facet.claimDeposit.selector
        );

        // "Controller.requestRedeemERC7540()" -> "ERC7540Facet.requestRedeem()"
        foreignController.setDispatch(
            IForeignControllerFull.requestRedeemERC7540.selector,
            erc7540Facet,
            IERC7540Facet.requestRedeem.selector
        );

        // "Controller.claimRedeemERC7540()" -> "ERC7540Facet.claimRedeem()"
        foreignController.setDispatch(
            IForeignControllerFull.claimRedeemERC7540.selector,
            erc7540Facet,
            IERC7540Facet.claimRedeem.selector
        );

        // "Controller.LIMIT_7540_DEPOSIT()" -> "ERC7540Facet.LIMIT_DEPOSIT()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_7540_DEPOSIT.selector,
            erc7540Facet,
            IERC7540Facet.LIMIT_DEPOSIT.selector
        );

        // "Controller.LIMIT_7540_REDEEM()" -> "ERC7540Facet.LIMIT_REDEEM()"
        foreignController.setDispatch(
            IForeignControllerFull.LIMIT_7540_REDEEM.selector,
            erc7540Facet,
            IERC7540Facet.LIMIT_REDEEM.selector
        );
    }

}
