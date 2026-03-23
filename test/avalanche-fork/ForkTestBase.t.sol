// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import "../../lib/forge-std/src/Test.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { ERC20Mock } from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { Avalanche } from "../../lib/grove-address-registry/src/Avalanche.sol";

import { PSM3Deploy } from "../../lib/spark-psm/deploy/PSM3Deploy.sol";
import { IPSM3 }      from "../../lib/spark-psm/src/PSM3.sol";

import { CCTPv2Forwarder as CCTPForwarder } from "../../lib/grove-xchain-helpers/src/forwarders/CCTPv2Forwarder.sol";

import { ALMProxy }          from "../../src/ALMProxy.sol";
import { ForeignController } from "../../src/ForeignController.sol";
import { RateLimits }        from "../../src/RateLimits.sol";
import { AccessControls }    from "../../src/AccessControls.sol";
import { Parameters }        from "../../src/Parameters.sol";

import { RateLimitHelpers } from "../../src/RateLimitHelpers.sol";

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

    bytes32 CONTROLLER;
    bytes32 FREEZER;
    bytes32 RELAYER;

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

    AccessControls    accessControls;
    ALMProxy          almProxy;
    ForeignController foreignController;
    Parameters        parameters;
    RateLimits        rateLimits;

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
        parameters     = new Parameters(GROVE_EXECUTOR);

        foreignController = new ForeignController({
            admin_          : GROVE_EXECUTOR,
            proxy_          : address(almProxy),
            rateLimits_     : address(rateLimits),
            accessControls_ : address(accessControls),
            parameters_     : address(parameters),
            psm_            : address(psmAvalanche),
            usdc_           : USDC_AVALANCHE,
            cctp_           : CCTP_TOKEN_MESSENGER
        });

        CONTROLLER = almProxy.CONTROLLER();
        FREEZER    = foreignController.FREEZER();
        RELAYER    = foreignController.RELAYER();

        /*** Step 3: Configure ALM system through Grove governance (Grove spell payload) ***/

        address[] memory relayers = new address[](1);
        relayers[0] = ALM_RELAYER;

        MintRecipient[] memory mintRecipients = new MintRecipient[](1);

        mintRecipients[0] = MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : bytes32(uint256(uint160(makeAddr("ethereumAlmProxy"))))
        });

        vm.startPrank(GROVE_EXECUTOR);

        almProxy.grantRole(almProxy.CONTROLLER(),                address(foreignController));
        foreignController.grantRole(foreignController.FREEZER(), ALM_FREEZER);
        rateLimits.grantRole(rateLimits.CONTROLLER(),            address(foreignController));

        for (uint256 i; i < relayers.length; ++i) {
            foreignController.grantRole(foreignController.RELAYER(), relayers[i]);
        }

        for (uint256 i; i < mintRecipients.length; ++i) {
            foreignController.setMintRecipient(mintRecipients[i].domain, mintRecipients[i].mintRecipient);
        }

        vm.stopPrank();
    }

    // Default configuration for the fork, can be overridden in inheriting tests
    function _getBlock() internal virtual pure returns (uint256) {
        return 65896755;  // July 22, 2025
    }

}
