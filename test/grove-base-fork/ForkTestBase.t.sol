// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "forge-std/Test.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { PSM3Deploy } from "spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "spark-psm/src/PSM3.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ForeignControllerDeploy } from "../../deploy/ControllerDeploy.sol";
import { ControllerInstance }      from "../../deploy/ControllerInstance.sol";

import { ForeignControllerInit as Init } from "../../deploy/ForeignControllerInit.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

contract MockSSROracle {

    function getConversionRate() external pure returns (uint256) {
        return 1e18;
    }

}

contract ForkTestBase is Test {

    /**********************************************************************************************/
    /*** Constants/state variables                                                              ***/
    /**********************************************************************************************/

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    bytes32 CONTROLLER;
    bytes32 FREEZER;
    bytes32 RELAYER;

    address pocket = makeAddr("pocket");

    /**********************************************************************************************/
    /*** Base addresses                                                                   ***/
    /**********************************************************************************************/

    // TODO: Update these to use the correct addresses from the registry`
    address constant ALM_FREEZER          = 0xB0113804960345fd0a245788b3423319c86940e5;
    address constant ALM_RELAYER          = 0x0eEC86649E756a23CBc68d9EFEd756f16aD5F85f;
    address constant CCTP_TOKEN_MESSENGER = 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962;
    address constant USDC_BASE            = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant PENDLE_ROUTER_BASE   = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    address GROVE_EXECUTOR = makeAddr("groveExecutor");

    /**********************************************************************************************/
    /*** ALM system deployments                                                                 ***/
    /**********************************************************************************************/

    ALMProxy          almProxy;
    RateLimits        rateLimits;
    ForeignController foreignController;

    /**********************************************************************************************/
    /*** Addresses for testing                                                                  ***/
    /**********************************************************************************************/

    IERC20 usdsBase;
    IERC20 susdsBase;
    IERC20 usdcBase;

    IPSM3 psmBase;

    MockSSROracle ssrOracle;

    /**********************************************************************************************/
    /*** Test setup                                                                             ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        /*** Step 1: Set up environment, deploy mock addresses ***/

        vm.createSelectFork(getChain('base').rpcUrl, _getBlock());

        usdsBase  = IERC20(address(new ERC20Mock()));
        susdsBase = IERC20(address(new ERC20Mock()));
        usdcBase  = IERC20(USDC_BASE);

        ssrOracle = new MockSSROracle();

        /*** Step 2: Deploy and configure PSM with a pocket ***/

        deal(address(usdsBase), address(this), 1e18);  // For seeding PSM during deployment

        psmBase = IPSM3(PSM3Deploy.deploy(
            GROVE_EXECUTOR, USDC_BASE, address(usdsBase), address(susdsBase), address(ssrOracle)
        ));

        vm.prank(GROVE_EXECUTOR);
        psmBase.setPocket(pocket);

        vm.prank(pocket);
        usdcBase.approve(address(psmBase), type(uint256).max);

        /*** Step 3: Deploy ALM system ***/

        ControllerInstance memory controllerInst = ForeignControllerDeploy.deployFull({
            admin        : GROVE_EXECUTOR,
            psm          : address(psmBase),
            usdc         : USDC_BASE,
            cctp         : CCTP_TOKEN_MESSENGER,
            pendleRouter : PENDLE_ROUTER_BASE
        });

        almProxy          = ALMProxy(payable(controllerInst.almProxy));
        rateLimits        = RateLimits(controllerInst.rateLimits);
        foreignController = ForeignController(controllerInst.controller);

        CONTROLLER = almProxy.CONTROLLER();
        FREEZER    = foreignController.FREEZER();
        RELAYER    = foreignController.RELAYER();

        /*** Step 3: Configure ALM system through Grove governance (Grove spell payload) ***/

        address[] memory relayers = new address[](1);
        relayers[0] = ALM_RELAYER;

        Init.ConfigAddressParams memory configAddresses = Init.ConfigAddressParams({
            freezer       : ALM_FREEZER,
            relayers      : relayers,
            oldController : address(0)
        });

        Init.CheckAddressParams memory checkAddresses = Init.CheckAddressParams({
            admin        : GROVE_EXECUTOR,
            psm          : address(psmBase),
            cctp         : CCTP_TOKEN_MESSENGER,
            usdc         : USDC_BASE,
            pendleRouter : PENDLE_ROUTER_BASE
            // susds : address(susdsBase),
            // usds  : address(usdsBase)
        });

        Init.MintRecipient[] memory mintRecipients = new Init.MintRecipient[](1);

        mintRecipients[0] = Init.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(makeAddr("ethereumAlmProxy"))))
        });

        Init.LayerZeroRecipient[] memory layerZeroRecipients = new Init.LayerZeroRecipient[](0);

        Init.CentrifugeRecipient[] memory centrifugeRecipients = new Init.CentrifugeRecipient[](0);

        vm.startPrank(GROVE_EXECUTOR);

        Init.initAlmSystem(
            controllerInst,
            configAddresses,
            checkAddresses,
            mintRecipients,
            layerZeroRecipients,
            centrifugeRecipients
        );

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 36912750; //  October 16, 2025
    }

}
