// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { DssInstance, MCD } from "../../lib/dss-test/src/MCD.sol";

import { AllocatorInit, AllocatorIlkConfig } from "../../lib/dss-allocator/deploy/AllocatorInit.sol";

import {
    AllocatorIlkInstance,
    AllocatorSharedInstance
} from "../../lib/dss-allocator/deploy/AllocatorInstances.sol";

import { AllocatorDeploy } from "../../lib/dss-allocator/deploy/AllocatorDeploy.sol";

import { IERC20 } from "../../lib/forge-std/src/interfaces/IERC20.sol";

import { Ethereum } from "../../lib/spark-address-registry/src/Ethereum.sol";

import { RateLimitLib } from "../../src/libraries/RateLimitLib.sol";
import { RolesLib }     from "../../src/libraries/RolesLib.sol";

import { Roles } from "../../src/facets/Roles.sol";
import { USDS }  from "../../src/facets/USDS.sol";

import { ALMProxy } from "../../src/ALMProxy.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IBufferLike {
    function approve(address, address, uint256) external;
}

interface IChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface IVaultLike {
    function buffer() external view returns (address);
    function rely(address) external;
}

interface IUSDSFunctions {
    function mintUSDS(uint256 amount) external;
    function burnUSDS(uint256 amount) external;
    function setUSDSRateLimit(uint256 maxAmount, uint256 slope, uint256 lastAmount, uint256 lastUpdated) external;
    function relayerRole() external view returns (bytes32 relayerRole);
    function currentUSDSRateLimit() external view returns (uint256 currentRateLimit);
    function usdsRateLimitData() external view returns (RateLimitLib.RateLimitData memory rateLimitData);
}

contract USDSFacetTests is ForkTestBase {

    bytes32 constant ILK = "ILK-A";

    uint256 constant INK           = 1e12 * 1e18;  // Ink initialization amount
    uint256 constant EIGHT_PCT_APY = 1.000000002440418608258400030e27;  // 8% APY (current DSR + 1%)

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    DssInstance dss;  // Mainnet DSS

    address usdsJoin;

    uint256 usdsSupply;
    uint256 vatDaiUsdsJoin;

    address buffer;
    address vault;

    address usdsFacet;

    address unauthorized = makeAddr("unauthorized");

    function setUp() public override {
        super.setUp();

        /*** Step 1: Set up environment, cast addresses ***/

        dss = MCD.loadFromChainlog(LOG);

        usdsJoin = IChainlogLike(LOG).getAddress("USDS_JOIN");

        usdsSupply     = IERC20(Ethereum.USDS).totalSupply();
        vatDaiUsdsJoin = dss.vat.dai(usdsJoin);

        /*** Step 2: Deploy and configure allocation system ***/

        AllocatorSharedInstance memory sharedInst
            = AllocatorDeploy.deployShared(address(this), Ethereum.PAUSE_PROXY);

        AllocatorIlkInstance memory ilkInst = AllocatorDeploy.deployIlk({
            deployer : address(this),
            owner    : Ethereum.PAUSE_PROXY,
            roles    : sharedInst.roles,
            ilk      : ILK,
            usdsJoin : usdsJoin
        });

        AllocatorIlkConfig memory ilkConfig = AllocatorIlkConfig({
            ilk            : ILK,
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

        /*** Step 3: Approve the ALM Proxy to spend the USDS ***/

        vm.startPrank(Ethereum.SPARK_PROXY);
        IVaultLike(vault).rely(almProxy);
        IBufferLike(IVaultLike(vault).buffer()).approve(Ethereum.USDS, almProxy, type(uint256).max);
        vm.stopPrank();

        /*** Step 4: Deploy the USDS Facet, wire the functions, initialize the facet's proxy storage ***/

        usdsFacet = address(new USDS());

        bytes4[] memory functionSelectors = new bytes4[](6);
        functionSelectors[0] = IUSDSFunctions.mintUSDS.selector;
        functionSelectors[1] = IUSDSFunctions.burnUSDS.selector;
        functionSelectors[2] = IUSDSFunctions.setUSDSRateLimit.selector;
        functionSelectors[3] = IUSDSFunctions.relayerRole.selector;
        functionSelectors[4] = IUSDSFunctions.currentUSDSRateLimit.selector;
        functionSelectors[5] = IUSDSFunctions.usdsRateLimitData.selector;

        ALMProxy.Implementation[] memory implementations = new ALMProxy.Implementation[](6);
        implementations[0] = ALMProxy.Implementation({
            implementation: usdsFacet,
            functionSelector: USDS.mint.selector
        });
        implementations[1] = ALMProxy.Implementation({
            implementation: usdsFacet,
            functionSelector: USDS.burn.selector
        });
        implementations[2] = ALMProxy.Implementation({
            implementation: usdsFacet,
            functionSelector: USDS.setRateLimit.selector
        });
        implementations[3] = ALMProxy.Implementation({
            implementation: usdsFacet,
            functionSelector: USDS.relayerRole.selector
        });
        implementations[4] = ALMProxy.Implementation({
            implementation: usdsFacet,
            functionSelector: USDS.currentRateLimit.selector
        });
        implementations[5] = ALMProxy.Implementation({
            implementation: usdsFacet,
            functionSelector: USDS.rateLimitData.selector
        });

        vm.startPrank(Ethereum.SPARK_PROXY);

        ALMProxy(almProxy).setImplementations(functionSelectors, implementations);

        ALMProxy(almProxy).delegateCall(
            usdsFacet,
            abi.encodeCall(USDS.initialize, (Ethereum.USDS, vault, ADMIN_ROLE, RELAYER_ROLE))
        );

        Roles(almProxy).grantRole(RELAYER_ROLE, relayer);

        vm.stopPrank();
    }

    function test_relayerRole() external {
        assertEq(IUSDSFunctions(almProxy).relayerRole(), RELAYER_ROLE);
    }

    function test_relayerHasRole() external {
        assertTrue(Roles(almProxy).hasRole(RELAYER_ROLE, relayer));
    }

    function test_setUSDSRateLimit_notAdmin() external {
        vm.expectRevert(abi.encodeWithSelector(
            RolesLib.Roles_NotAuthorized.selector,
            unauthorized,
            ADMIN_ROLE
        ));
        vm.prank(unauthorized);
        IUSDSFunctions(almProxy).setUSDSRateLimit(0, 0, 0, 0);
    }

    function test_setUSDSRateLimit() external {
        uint256 maxAmount = 5_000_000e18;
        uint256 slope = uint256(5_000_000e18) / 1 days;
        uint256 lastAmount = 5_000_000e18;
        uint256 lastUpdated = vm.getBlockTimestamp();

        vm.expectEmit(almProxy);
        emit USDS.USDS_RateLimitSet(
            Ethereum.SPARK_PROXY,
            maxAmount,
            slope,
            lastAmount,
            lastUpdated
        );

        vm.prank(Ethereum.SPARK_PROXY);
        IUSDSFunctions(almProxy).setUSDSRateLimit(maxAmount, slope, lastAmount, lastUpdated);

        assertEq(IUSDSFunctions(almProxy).usdsRateLimitData().maxAmount, maxAmount);
        assertEq(IUSDSFunctions(almProxy).usdsRateLimitData().slope, slope);
        assertEq(IUSDSFunctions(almProxy).usdsRateLimitData().lastAmount, lastAmount);
        assertEq(IUSDSFunctions(almProxy).usdsRateLimitData().lastUpdated, lastUpdated);
    }

    function test_mintUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSelector(
            RolesLib.Roles_NotAuthorized.selector,
            address(this),
            RELAYER_ROLE
        ));
        IUSDSFunctions(almProxy).mintUSDS(1e18);
    }

    function test_mintUSDS_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(
            USDS.USDS_RateLimitExceeded.selector,
            1e18,
            0
        ));
        IUSDSFunctions(almProxy).mintUSDS(1e18);
    }

    function test_mintUSDS_rateLimitBoundary() external {
        _setRateLimit();

        vm.expectRevert(abi.encodeWithSelector(
            USDS.USDS_RateLimitExceeded.selector,
            5_000_000e18 + 1,
            5_000_000e18
        ));
        vm.startPrank(relayer);
        IUSDSFunctions(almProxy).mintUSDS(5_000_000e18 + 1);
    }

    function test_mintUSDS() external {
        _setRateLimit();

        ( uint256 ink, uint256 art ) = dss.vat.urns(ILK, vault);
        ( uint256 Art,,,, )          = dss.vat.ilks(ILK);

        assertEq(dss.vat.dai(usdsJoin), vatDaiUsdsJoin);

        assertEq(Art, 0);
        assertEq(ink, INK);
        assertEq(art, 0);

        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy), 0);
        assertEq(IERC20(Ethereum.USDS).totalSupply(),       usdsSupply);

        vm.prank(relayer);
        IUSDSFunctions(almProxy).mintUSDS(1e18);

        ( ink, art ) = dss.vat.urns(ILK, vault);
        ( Art,,,, )  = dss.vat.ilks(ILK);

        assertEq(dss.vat.dai(usdsJoin), vatDaiUsdsJoin + 1e45);

        assertEq(Art, 1e18);
        assertEq(ink, INK);
        assertEq(art, 1e18);

        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy), 1e18);
        assertEq(IERC20(Ethereum.USDS).totalSupply(),       usdsSupply + 1e18);
    }

    function test_mintUSDS_rateLimited() external {
        _setRateLimit();

        vm.startPrank(relayer);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 5_000_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       0);

        IUSDSFunctions(almProxy).mintUSDS(1_000_000e18);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 4_000_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       1_000_000e18);

        skip(1 hours);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 4_249_999.9999999999999984e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       1_000_000e18);

        IUSDSFunctions(almProxy).mintUSDS(4_249_999.9999999999999984e18);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 0);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       5_249_999.9999999999999984e18);

        vm.expectRevert(abi.encodeWithSelector(
            USDS.USDS_RateLimitExceeded.selector,
            1,
            0
        ));
        IUSDSFunctions(almProxy).mintUSDS(1);

        vm.stopPrank();
    }

    function test_burnUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSelector(
            RolesLib.Roles_NotAuthorized.selector,
            address(this),
            RELAYER_ROLE
        ));
        IUSDSFunctions(almProxy).burnUSDS(1e18);
    }

    function test_burnUSDS_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert(USDS.USDS_RateLimitZeroMaxAmount.selector);
        IUSDSFunctions(almProxy).burnUSDS(1e18);
    }

    function test_burnUSDS() external {
        _setRateLimit();

        // Setup
        vm.prank(relayer);
        IUSDSFunctions(almProxy).mintUSDS(1e18);

        ( uint256 ink, uint256 art ) = dss.vat.urns(ILK, vault);
        ( uint256 Art,,,, )          = dss.vat.ilks(ILK);

        assertEq(dss.vat.dai(usdsJoin), vatDaiUsdsJoin + 1e45);

        assertEq(Art, 1e18);
        assertEq(ink, INK);
        assertEq(art, 1e18);

        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy), 1e18);
        assertEq(IERC20(Ethereum.USDS).totalSupply(),       usdsSupply + 1e18);

        vm.prank(relayer);
        IUSDSFunctions(almProxy).burnUSDS(1e18);

        ( ink, art ) = dss.vat.urns(ILK, vault);
        ( Art,,,, )  = dss.vat.ilks(ILK);

        assertEq(dss.vat.dai(usdsJoin), vatDaiUsdsJoin);

        assertEq(Art, 0);
        assertEq(ink, INK);
        assertEq(art, 0);

        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy), 0);
        assertEq(IERC20(Ethereum.USDS).totalSupply(),       usdsSupply);
    }

    function test_burnUSDS_rateLimited() external {
        _setRateLimit();

        vm.startPrank(relayer);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 5_000_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       0);

        IUSDSFunctions(almProxy).mintUSDS(1_000_000e18);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 4_000_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       1_000_000e18);

        IUSDSFunctions(almProxy).burnUSDS(500_000e18);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 4_500_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       500_000e18);

        skip(4 hours);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 5_000_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       500_000e18);

        IUSDSFunctions(almProxy).burnUSDS(500_000e18);

        assertEq(IUSDSFunctions(almProxy).currentUSDSRateLimit(), 5_000_000e18);
        assertEq(IERC20(Ethereum.USDS).balanceOf(almProxy),       0);

        vm.stopPrank();
    }

    function _setRateLimit() internal {
        vm.prank(Ethereum.SPARK_PROXY);
        IUSDSFunctions(almProxy).setUSDSRateLimit(
            5_000_000e18,
            uint256(1_000_000e18) / 4 hours,
            5_000_000e18,
            vm.getBlockTimestamp()
        );
    }

}
