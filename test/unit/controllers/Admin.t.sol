// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";
import { UniswapV3Lib }      from "../../../src/libraries/UniswapV3Lib.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract MainnetControllerAdminTestBase is UnitTestBase {

    event LayerZeroRecipientSet(uint32 indexed destinationDomain, bytes32 layerZeroRecipient);
    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);
    event UniswapV3PoolMaxTickDeltaSet(address indexed pool, uint24 maxTickDelta);
    event UniswapV3PoolLowerTickUpdated(address indexed pool, int24 lowerTick);
    event UniswapV3PoolUpperTickUpdated(address indexed pool, int24 upperTick);
    event UniswapV3PoolTwapSecondsAgoUpdated(address indexed pool, uint32 twapSecondsAgo);

    bytes32 layerZeroRecipient1 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient1"))));
    bytes32 layerZeroRecipient2 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient2"))));
    bytes32 mintRecipient1      = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 mintRecipient2      = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    MainnetController mainnetController;

    function setUp() public {
        MockDaiUsds daiUsds = new MockDaiUsds(makeAddr("dai"));
        MockPSM     psm     = new MockPSM(makeAddr("usdc"));
        MockVault   vault   = new MockVault(makeAddr("buffer"));

        mainnetController = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            address(vault),
            address(psm),
            address(daiUsds),
            makeAddr("cctp"),
            makeAddr("uniswapV3Router"),
            makeAddr("uniswapV3PositionManager")
        );
    }

}

contract MainnetControllerSetMintRecipientTests is MainnetControllerAdminTestBase {

    function test_setMintRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient() public {
        assertEq(mainnetController.mintRecipients(1), bytes32(0));
        assertEq(mainnetController.mintRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MintRecipientSet(1, mintRecipient1);
        mainnetController.setMintRecipient(1, mintRecipient1);

        assertEq(mainnetController.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MintRecipientSet(2, mintRecipient2);
        mainnetController.setMintRecipient(2, mintRecipient2);

        assertEq(mainnetController.mintRecipients(2), mintRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MintRecipientSet(1, mintRecipient2);
        mainnetController.setMintRecipient(1, mintRecipient2);

        assertEq(mainnetController.mintRecipients(1), mintRecipient2);
    }

}

contract MainnetControllerSetLayerZeroRecipientTests is MainnetControllerAdminTestBase {

    function test_setLayerZeroRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setLayerZeroRecipient() public {
        assertEq(mainnetController.layerZeroRecipients(1), bytes32(0));
        assertEq(mainnetController.layerZeroRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient1);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit LayerZeroRecipientSet(2, layerZeroRecipient2);
        mainnetController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient2);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient2);
    }

}

contract MainnetControllerSetMaxSlippageTests is MainnetControllerAdminTestBase {

    function test_setMaxSlippage_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.01e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.01e18);
    }

    function test_setMaxSlippage() public {
        address pool = makeAddr("pool");

        assertEq(mainnetController.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MaxSlippageSet(pool, 0.01e18);
        mainnetController.setMaxSlippage(pool, 0.01e18);

        assertEq(mainnetController.maxSlippages(pool), 0.01e18);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MaxSlippageSet(pool, 0.02e18);
        mainnetController.setMaxSlippage(pool, 0.02e18);

        assertEq(mainnetController.maxSlippages(pool), 0.02e18);
    }

    function test_setMaxSlippage_outOfBounds() public {
        vm.prank(admin);
        vm.expectRevert("MainnetController/max-slippage-out-of-bounds");
        mainnetController.setMaxSlippage(makeAddr("pool"), 1e18 + 1);
    }
}

contract MainnetControllerSetUniswapV3PoolMaxTickDeltaTests is MainnetControllerAdminTestBase {

    function test_setUniswapV3PoolMaxTickDelta_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 1000);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 1000);
    }

    function test_setUniswapV3PoolMaxTickDelta_zeroMaxTickDelta() public {
        vm.prank(admin);
        vm.expectRevert("MainnetController/max-tick-delta-out-of-bounds");
        mainnetController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 0);
    }

    function test_setUniswapV3PoolMaxTickDelta_exceedsMaxTickDelta() public {
        vm.prank(admin);
        vm.expectRevert("MainnetController/max-tick-delta-out-of-bounds");
        mainnetController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 887273); // MAX_TICK_DELTA + 1
    }

    function test_setUniswapV3PoolMaxTickDelta() public {
        address pool = makeAddr("pool");

        ( uint24 maxTickDelta,, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(maxTickDelta, 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolMaxTickDeltaSet(pool, 1000);
        mainnetController.setUniswapV3PoolMaxTickDelta(pool, 1000);

        ( maxTickDelta,, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(maxTickDelta, 1000);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolMaxTickDeltaSet(pool, 887272); // MAX_TICK_DELTA
        mainnetController.setUniswapV3PoolMaxTickDelta(pool, 887272);

        ( maxTickDelta,, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(maxTickDelta, 887272);
    }

}

contract MainnetControllerSetUniswapV3AddLiquidityLowerTickBoundTests is MainnetControllerAdminTestBase {

    function test_setUniswapV3AddLiquidityLowerTickBound_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(makeAddr("pool"), -1000);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(makeAddr("pool"), -1000);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_belowMinTick() public {
        vm.prank(admin);
        vm.expectRevert("MainnetController/lower-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(makeAddr("pool"), -887273); // MIN_TICK - 1
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_atOrAboveUpperTick() public {
        address pool = makeAddr("pool");

        // First set an upper tick bound
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 1000);

        // Try to set lower tick at or above the upper tick
        vm.prank(admin);
        vm.expectRevert("MainnetController/lower-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(pool, 1000);

        vm.prank(admin);
        vm.expectRevert("MainnetController/lower-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(pool, 1001);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound() public {
        address pool = makeAddr("pool");

        // First set an upper tick bound so we have room to set lower
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 5000);

        (, UniswapV3Lib.Tick memory tickBounds, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 5000);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolLowerTickUpdated(pool, -1000);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(pool, -1000);

        (, tickBounds, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, -1000);

        // Can set at MIN_TICK
        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolLowerTickUpdated(pool, -887272);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(pool, -887272);

        (, tickBounds, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, -887272);
    }

}

contract MainnetControllerSetUniswapV3AddLiquidityUpperTickBoundTests is MainnetControllerAdminTestBase {

    function test_setUniswapV3AddLiquidityUpperTickBound_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(makeAddr("pool"), 1000);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(makeAddr("pool"), 1000);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_aboveMaxTick() public {
        vm.prank(admin);
        vm.expectRevert("MainnetController/upper-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(makeAddr("pool"), 887273); // MAX_TICK + 1
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_atOrBelowLowerTick() public {
        address pool = makeAddr("pool");

        // First set a lower tick bound
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 2000);
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(pool, 1000);

        // Try to set upper tick at or below the lower tick
        vm.prank(admin);
        vm.expectRevert("MainnetController/upper-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 1000);

        vm.prank(admin);
        vm.expectRevert("MainnetController/upper-tick-out-of-bounds");
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 999);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound() public {
        address pool = makeAddr("pool");

        (, UniswapV3Lib.Tick memory tickBounds, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolUpperTickUpdated(pool, 1000);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 1000);

        (, tickBounds, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 1000);

        // Can set at MAX_TICK
        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolUpperTickUpdated(pool, 887272);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(pool, 887272);

        (, tickBounds, ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.upper, 887272);
    }

}

contract MainnetControllerSetUniswapV3TwapSecondsAgoTests is MainnetControllerAdminTestBase {

    function test_setUniswapV3TwapSecondsAgo_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), 300);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), 300);
    }

    function test_setUniswapV3TwapSecondsAgo_outOfBounds() public {
        vm.startPrank(admin);

        vm.expectRevert("MainnetController/twap-seconds-ago-out-of-bounds");
        mainnetController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), uint32(type(int32).max));

        vm.expectRevert("MainnetController/twap-seconds-ago-out-of-bounds");
        mainnetController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), type(uint32).max);

        vm.stopPrank();
    }

    function test_setUniswapV3TwapSecondsAgo() public {
        address pool = makeAddr("pool");

        (,, uint32 twapSecondsAgo ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(twapSecondsAgo, 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolTwapSecondsAgoUpdated(pool, 300);
        mainnetController.setUniswapV3TwapSecondsAgo(pool, 300);

        (,, twapSecondsAgo ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(twapSecondsAgo, 300);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit UniswapV3PoolTwapSecondsAgoUpdated(pool, 1800);
        mainnetController.setUniswapV3TwapSecondsAgo(pool, 1800);

        (,, twapSecondsAgo ) = mainnetController.uniswapV3PoolParams(pool);
        assertEq(twapSecondsAgo, 1800);
    }

}


contract ForeignControllerAdminTestBase is UnitTestBase {

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);
    event LayerZeroRecipientSet(uint32 indexed destinationDomain, bytes32 layerZeroRecipient);
    event MintRecipientSet(uint32 indexed destinationDomain, bytes32 mintRecipient);
    event UniswapV3PoolMaxTickDeltaSet(address indexed pool, uint24 maxTickDelta);
    event UniswapV3PoolLowerTickUpdated(address indexed pool, int24 lowerTick);
    event UniswapV3PoolUpperTickUpdated(address indexed pool, int24 upperTick);
    event UniswapV3PoolTwapSecondsAgoUpdated(address indexed pool, uint32 twapSecondsAgo);

    ForeignController foreignController;

    bytes32 layerZeroRecipient1 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient1"))));
    bytes32 layerZeroRecipient2 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient2"))));
    bytes32 mintRecipient1      = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 mintRecipient2      = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    function setUp() public {
        foreignController = new ForeignController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            makeAddr("psm"),
            makeAddr("usdc"),
            makeAddr("cctp"),
            makeAddr("pendleRouter"),
            makeAddr("uniswapV3Router"),
            makeAddr("uniswapV3PositionManager")
        );
    }
}

contract ForeignControllerSetMintRecipientTests is ForeignControllerAdminTestBase {

    function test_setMintRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMintRecipient(1, mintRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient() public {
        assertEq(foreignController.mintRecipients(1), bytes32(0));
        assertEq(foreignController.mintRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MintRecipientSet(1, mintRecipient1);
        foreignController.setMintRecipient(1, mintRecipient1);

        assertEq(foreignController.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MintRecipientSet(2, mintRecipient2);
        foreignController.setMintRecipient(2, mintRecipient2);

        assertEq(foreignController.mintRecipients(2), mintRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MintRecipientSet(1, mintRecipient2);
        foreignController.setMintRecipient(1, mintRecipient2);

        assertEq(foreignController.mintRecipients(1), mintRecipient2);
    }
}

contract ForeignControllerSetLayerZeroRecipientTests is ForeignControllerAdminTestBase {

    function test_setLayerZeroRecipient_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

    function test_setLayerZeroRecipient() public {
        assertEq(foreignController.layerZeroRecipients(1), bytes32(0));
        assertEq(foreignController.layerZeroRecipients(2), bytes32(0));

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient1);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit LayerZeroRecipientSet(2, layerZeroRecipient2);
        foreignController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit LayerZeroRecipientSet(1, layerZeroRecipient2);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient2);
    }

}

contract ForeignControllerSetMaxSlippageTests is ForeignControllerAdminTestBase {

    function test_setMaxSlippage_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxSlippage(makeAddr("pool"), 0.01e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxSlippage(makeAddr("pool"), 0.01e18);
    }

    function test_setMaxSlippage() public {
        address pool = makeAddr("pool");

        assertEq(foreignController.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MaxSlippageSet(pool, 0.01e18);
        foreignController.setMaxSlippage(pool, 0.01e18);

        assertEq(foreignController.maxSlippages(pool), 0.01e18);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MaxSlippageSet(pool, 0.02e18);
        foreignController.setMaxSlippage(pool, 0.02e18);

        assertEq(foreignController.maxSlippages(pool), 0.02e18);
    }

    function test_setMaxSlippage_outOfBounds() public {
        vm.prank(admin);
        vm.expectRevert("ForeignController/max-slippage-out-of-bounds");
        foreignController.setMaxSlippage(makeAddr("pool"), 1e18 + 1);
    }
}

contract ForeignControllerSetUniswapV3PoolMaxTickDeltaTests is ForeignControllerAdminTestBase {

    function test_setUniswapV3PoolMaxTickDelta_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 1000);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 1000);
    }

    function test_setUniswapV3PoolMaxTickDelta_zeroMaxTickDelta() public {
        vm.prank(admin);
        vm.expectRevert("ForeignController/max-tick-delta-out-of-bounds");
        foreignController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 0);
    }

    function test_setUniswapV3PoolMaxTickDelta_exceedsMaxTickDelta() public {
        vm.prank(admin);
        vm.expectRevert("ForeignController/max-tick-delta-out-of-bounds");
        foreignController.setUniswapV3PoolMaxTickDelta(makeAddr("pool"), 887273); // MAX_TICK_DELTA + 1
    }

    function test_setUniswapV3PoolMaxTickDelta() public {
        address pool = makeAddr("pool");

        ( uint24 maxTickDelta,, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(uint256(maxTickDelta), 0);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolMaxTickDeltaSet(pool, 1000);
        foreignController.setUniswapV3PoolMaxTickDelta(pool, 1000);

        ( maxTickDelta,, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(uint256(maxTickDelta), 1000);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolMaxTickDeltaSet(pool, 887272); // MAX_TICK_DELTA
        foreignController.setUniswapV3PoolMaxTickDelta(pool, 887272);

        ( maxTickDelta,, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(uint256(maxTickDelta), 887272);
    }

}

contract ForeignControllerSetUniswapV3AddLiquidityLowerTickBoundTests is ForeignControllerAdminTestBase {

    function test_setUniswapV3AddLiquidityLowerTickBound_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3AddLiquidityLowerTickBound(makeAddr("pool"), -1000);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3AddLiquidityLowerTickBound(makeAddr("pool"), -1000);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_belowMinTick() public {
        vm.prank(admin);
        vm.expectRevert("ForeignController/lower-tick-out-of-bounds");
        foreignController.setUniswapV3AddLiquidityLowerTickBound(makeAddr("pool"), -887273); // MIN_TICK - 1
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_atOrAboveUpperTick() public {
        address pool = makeAddr("pool");

        // First set an upper tick bound
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 1000);

        // Try to set lower tick at or above the upper tick
        vm.prank(admin);
        vm.expectRevert("ForeignController/lower-tick-out-of-bounds");
        foreignController.setUniswapV3AddLiquidityLowerTickBound(pool, 1000);

        vm.prank(admin);
        vm.expectRevert("ForeignController/lower-tick-out-of-bounds");
        foreignController.setUniswapV3AddLiquidityLowerTickBound(pool, 1001);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound() public {
        address pool = makeAddr("pool");

        // First set an upper tick bound so we have room to set lower
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 5000);

        (, UniswapV3Lib.Tick memory tickBounds, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 5000);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolLowerTickUpdated(pool, -1000);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(pool, -1000);

        (, tickBounds, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, -1000);

        // Can set at MIN_TICK
        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolLowerTickUpdated(pool, -887272);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(pool, -887272);

        (, tickBounds, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, -887272);
    }

}

contract ForeignControllerSetUniswapV3AddLiquidityUpperTickBoundTests is ForeignControllerAdminTestBase {

    function test_setUniswapV3AddLiquidityUpperTickBound_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3AddLiquidityUpperTickBound(makeAddr("pool"), 1000);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3AddLiquidityUpperTickBound(makeAddr("pool"), 1000);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_aboveMaxTick() public {
        vm.prank(admin);
        vm.expectRevert("ForeignController/upper-tick-out-of-bounds");
        foreignController.setUniswapV3AddLiquidityUpperTickBound(makeAddr("pool"), 887273); // MAX_TICK + 1
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_atOrBelowLowerTick() public {
        address pool = makeAddr("pool");

        // First set a lower tick bound
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 2000);
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(pool, 1000);

        // Try to set upper tick at or below the lower tick
        vm.prank(admin);
        vm.expectRevert("ForeignController/upper-tick-out-of-bounds");
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 1000);

        vm.prank(admin);
        vm.expectRevert("ForeignController/upper-tick-out-of-bounds");
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 999);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound() public {
        address pool = makeAddr("pool");

        (, UniswapV3Lib.Tick memory tickBounds, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 0);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolUpperTickUpdated(pool, 1000);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 1000);

        (, tickBounds, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 1000);

        // Can set at MAX_TICK
        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolUpperTickUpdated(pool, 887272);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(pool, 887272);

        (, tickBounds, ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(tickBounds.upper, 887272);
    }

}

contract ForeignControllerSetMerklDistributorTests is ForeignControllerAdminTestBase {

    event MerklDistributorSet(address indexed merklDistributor);

    function test_setMerklDistributor_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMerklDistributor(makeAddr("merklDistributor"));
    }

    function test_setMerklDistributor() public {
        assertEq(address(foreignController.merklDistributor()), address(0));

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MerklDistributorSet(makeAddr("merklDistributor"));
        foreignController.setMerklDistributor(makeAddr("merklDistributor"));
    }

}

contract ForeignControllerSetUniswapV3TwapSecondsAgoTests is ForeignControllerAdminTestBase {

    function test_setUniswapV3TwapSecondsAgo_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), 300);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), 300);
    }

    function test_setUniswapV3TwapSecondsAgo_outOfBounds() public {
        vm.startPrank(admin);

        vm.expectRevert("ForeignController/twap-seconds-ago-out-of-bounds");
        foreignController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), uint32(type(int32).max));

        vm.expectRevert("ForeignController/twap-seconds-ago-out-of-bounds");
        foreignController.setUniswapV3TwapSecondsAgo(makeAddr("pool"), type(uint32).max);

        vm.stopPrank();
    }

    function test_setUniswapV3TwapSecondsAgo() public {
        address pool = makeAddr("pool");

        (,, uint32 twapSecondsAgo ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(twapSecondsAgo, 0);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolTwapSecondsAgoUpdated(pool, 300);
        foreignController.setUniswapV3TwapSecondsAgo(pool, 300);

        (,, twapSecondsAgo ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(twapSecondsAgo, 300);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit UniswapV3PoolTwapSecondsAgoUpdated(pool, 1800);
        foreignController.setUniswapV3TwapSecondsAgo(pool, 1800);

        (,, twapSecondsAgo ) = foreignController.uniswapV3PoolParams(pool);
        assertEq(twapSecondsAgo, 1800);
    }

}
