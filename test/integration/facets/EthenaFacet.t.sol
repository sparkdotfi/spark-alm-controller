// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IEthenaFacet }            from "../../../src/facets/ethena/IEthenaFacet.sol";
import { IEnumerableIntegrations } from "../../../src/interfaces/IEnumerableIntegrations.sol";

import { EthenaFacet } from "../../../src/facets/ethena/EthenaFacet.sol";

import { Integration_TestBase } from "../TestBase.t.sol";

interface IControllerLike {

    function setDelegatedSignerRateLimitKey() external pure returns (bytes32);

    function removeDelegatedSignerRateLimitKey() external pure returns (bytes32);

    function mintRateLimitKey() external pure returns (bytes32);

    function burnRateLimitKey() external pure returns (bytes32);

    function cooldownRateLimitKey() external pure returns (bytes32);

    function unstakeRateLimitKey() external pure returns (bytes32);

    function updateIntegrations(bytes32[] memory integrationIds) external;

}

contract Controller_EthenaFacet_Tests is Integration_TestBase {

    IControllerLike internal controller;

    function setUp() external {
        controller = IControllerLike(_deploy());

        address facet = address(new EthenaFacet(
            makeAddr("minter"),
            makeAddr("susde"),
            makeAddr("usdc"),
            makeAddr("usde")
        ));

        vm.label(facet, "EthenaFacet");

        IEnumerableIntegrations.Wire[] memory wires = new IEnumerableIntegrations.Wire[](6);

        wires[0] = IEnumerableIntegrations.Wire(
            IControllerLike.setDelegatedSignerRateLimitKey.selector,
            IEthenaFacet.setDelegatedSignerRateLimitKey.selector
        );

        wires[1] = IEnumerableIntegrations.Wire(
            IControllerLike.removeDelegatedSignerRateLimitKey.selector,
            IEthenaFacet.removeDelegatedSignerRateLimitKey.selector
        );

        wires[2] = IEnumerableIntegrations.Wire(
            IControllerLike.mintRateLimitKey.selector,
            IEthenaFacet.mintRateLimitKey.selector
        );

        wires[3] = IEnumerableIntegrations.Wire(
            IControllerLike.burnRateLimitKey.selector,
            IEthenaFacet.burnRateLimitKey.selector
        );

        wires[4] = IEnumerableIntegrations.Wire(
            IControllerLike.cooldownRateLimitKey.selector,
            IEthenaFacet.cooldownRateLimitKey.selector
        );

        wires[5] = IEnumerableIntegrations.Wire(
            IControllerLike.unstakeRateLimitKey.selector,
            IEthenaFacet.unstakeRateLimitKey.selector
        );

        IEnumerableIntegrations.Config memory config = IEnumerableIntegrations.Config(facet, wires);

        vm.prank(beaconAdmin);
        beacon.setIntegration("USDE_FACET", config);

        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = "USDE_FACET";

        vm.prank(admin);
        controller.updateIntegrations(integrationIds);
    }

    /**********************************************************************************************/
    /*** Constructor Tests                                                                      ***/
    /**********************************************************************************************/

    function test_constructor_zeroEthenaMinter() external {
        vm.expectRevert("EthenaFacet/zero-minter");
        new EthenaFacet(address(0), address(0), address(0), address(0));
    }

    function test_constructor_zeroSusde() external {
        vm.expectRevert("EthenaFacet/zero-susde");
        new EthenaFacet(makeAddr("minter"), address(0), address(0), address(0));
    }

    function test_constructor_zeroUSDC() external {
        vm.expectRevert("EthenaFacet/zero-usdc");
        new EthenaFacet(makeAddr("minter"), makeAddr("susde"), address(0), address(0));
    }

    function test_constructor_zeroUSDE() external {
        vm.expectRevert("EthenaFacet/zero-usde");
        new EthenaFacet(makeAddr("minter"), makeAddr("susde"), makeAddr("usdc"), address(0));
    }

    function test_constructor() external {
        address minter = makeAddr("minter");
        address susde  = makeAddr("susde");
        address usdc   = makeAddr("usdc");
        address usde   = makeAddr("usde");

        EthenaFacet facet = new EthenaFacet(minter, susde, usdc, usde);

        assertEq(facet.minter(), minter);
        assertEq(facet.susde(),  susde);
        assertEq(facet.usdc(),   usdc);
        assertEq(facet.usde(),   usde);
    }

    /**********************************************************************************************/
    /*** setDelegatedSignerRateLimitKey Tests                                                    ***/
    /**********************************************************************************************/

    function test_setDelegatedSignerRateLimitKey() external {
        assertEq(controller.setDelegatedSignerRateLimitKey(), keccak256("LIMIT_ETHENA_SET_DELEGATED_SIGNER"));
    }

    /**********************************************************************************************/
    /*** removeDelegatedSignerRateLimitKey Tests                                                ***/
    /**********************************************************************************************/

    function test_removeDelegatedSignerRateLimitKey() external {
        assertEq(controller.removeDelegatedSignerRateLimitKey(), keccak256("LIMIT_ETHENA_REMOVE_DELEGATED_SIGNER"));
    }

    /**********************************************************************************************/
    /*** mintRateLimitKey Tests                                                                 ***/
    /**********************************************************************************************/

    function test_mintRateLimitKey() external {
        assertEq(controller.mintRateLimitKey(), keccak256("LIMIT_ETHENA_MINT"));
    }

    /**********************************************************************************************/
    /*** burnRateLimitKey Tests                                                                 ***/
    /**********************************************************************************************/

    function test_burnRateLimitKey() external {
        assertEq(controller.burnRateLimitKey(), keccak256("LIMIT_ETHENA_BURN"));
    }

    /**********************************************************************************************/
    /*** cooldownRateLimitKey Tests                                                             ***/
    /**********************************************************************************************/

    function test_cooldownRateLimitKey() external {
        assertEq(controller.cooldownRateLimitKey(), keccak256("LIMIT_ETHENA_COOLDOWN"));
    }

    /**********************************************************************************************/
    /*** unstakeRateLimitKey Tests                                                               ***/
    /**********************************************************************************************/

    function test_unstakeRateLimitKey() external {
        assertEq(controller.unstakeRateLimitKey(), keccak256("LIMIT_ETHENA_UNSTAKE"));
    }

}
