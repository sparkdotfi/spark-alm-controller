// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IAccessControl }  from "../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { UniswapV3Lib } from "../../../src/libraries/UniswapV3Lib.sol";

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract MainnetController_Admin_TestBase is UnitTestBase {

    MainnetController internal mainnetController;

    function setUp() public virtual {
        MockDaiUsds daiUsds = new MockDaiUsds(makeAddr("dai"));
        MockPSM     psm     = new MockPSM(makeAddr("usdc"));
        MockVault   vault   = new MockVault(makeAddr("buffer"));

        mainnetController = new MainnetController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            makeAddr("accessControls"),
            address(vault),
            address(psm),
            address(daiUsds),
            makeAddr("cctp")
        );
    }

    function _setControllerEntered() internal {
        vm.store(address(mainnetController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        _assertReentrancyGuardWrittenToTwice(address(mainnetController));
    }

}

contract MainnetController_Admin_SetMaxSlippage_Tests is MainnetController_Admin_TestBase {

    function test_setMaxSlippage_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.98e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage_poolZeroAddress() external {
        vm.prank(admin);
        vm.expectRevert("MC/pool-zero-address");
        mainnetController.setMaxSlippage(address(0), 0.98e18);
    }

    function test_setMaxSlippage() external {
        address pool = makeAddr("pool");

        assertEq(mainnetController.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MaxSlippageSet(pool, 0.98e18);
        mainnetController.setMaxSlippage(pool, 0.98e18);

        assertEq(mainnetController.maxSlippages(pool), 0.98e18);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MaxSlippageSet(pool, 0.99e18);
        mainnetController.setMaxSlippage(pool, 0.99e18);

        assertEq(mainnetController.maxSlippages(pool), 0.99e18);

        _assertReentrancyGuardWrittenToTwice();
    }

}

contract MainnetController_Admin_SetUniswapV3PositionManager_Tests is MainnetController_Admin_TestBase {

    address internal immutable _positionManager = makeAddr("positionManager");
    address internal immutable _unauthorized    = makeAddr("unauthorized");

    function test_setUniswapV3PositionManager_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV3PositionManager(_positionManager);
    }

    function test_setUniswapV3PositionManager_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV3PositionManager(_positionManager);
    }

    function test_setUniswapV3PositionManager() external {
        assertEq(mainnetController.uniswapV3PositionManager(), address(0));

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit MainnetController.UniswapV3PositionManagerSet(_positionManager);

        vm.prank(admin);
        mainnetController.setUniswapV3PositionManager(_positionManager);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.uniswapV3PositionManager(), _positionManager);
    }

}

contract MainnetController_Admin_SetUniswapV3SwapRouter_Tests is MainnetController_Admin_TestBase {

    address internal immutable _swapRouter   = makeAddr("swapRouter");
    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setUniswapV3SwapRouter_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV3SwapRouter(_swapRouter);
    }

    function test_setUniswapV3SwapRouter_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV3SwapRouter(_swapRouter);
    }

    function test_setUniswapV3SwapRouter() external {
        assertEq(mainnetController.uniswapV3Router(), address(0));

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit MainnetController.UniswapV3SwapRouterSet(_swapRouter);

        vm.prank(admin);
        mainnetController.setUniswapV3SwapRouter(_swapRouter);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.uniswapV3Router(), _swapRouter);
    }

}

contract MainnetController_Admin_SetUniswapV3PoolMaxTickDelta_Tests is MainnetController_Admin_TestBase {

    uint24 internal constant _MAX_TICK_DELTA = 887_272;

    address internal immutable _pool         = makeAddr("pool");
    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setUniswapV3PoolMaxTickDelta_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, 10);
    }

    function test_setUniswapV3PoolMaxTickDelta_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, 1000);
    }

    function test_setUniswapV3PoolMaxTickDelta_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/max-tick-delta-oob");
        vm.prank(admin);
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, 0);

        vm.prank(admin);
        vm.expectRevert("UniswapV3Lib/max-tick-delta-oob");
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, _MAX_TICK_DELTA + 1);

        // Can set at boundary

        vm.prank(admin);
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, 1);

        vm.prank(admin);
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, _MAX_TICK_DELTA);
    }

    function test_setUniswapV3PoolMaxTickDelta() external {
        ( uint24 maxTickDelta, , ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(maxTickDelta, 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolMaxTickDeltaSet(_pool, 1000);

        vm.prank(admin);
        mainnetController.setUniswapV3PoolMaxTickDelta(_pool, 1000);

        _assertReentrancyGuardWrittenToTwice();

        ( maxTickDelta, , ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(maxTickDelta, 1000);
    }

}

contract MainnetController_Admin_SetUniswapV3AddLiquidityLowerTickBound_Tests is MainnetController_Admin_TestBase {

    int24 internal constant _MIN_UNISWAP_TICK = -887_272;

    address internal immutable _pool         = makeAddr("pool");
    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setUniswapV3AddLiquidityLowerTickBound_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/lower-tick-oob");
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, _MIN_UNISWAP_TICK - 1);

        // First set an upper tick bound
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 1000);

        // Try to set lower tick at the upper tick
        vm.prank(admin);
        vm.expectRevert("UniswapV3Lib/lower-tick-oob");
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, 1000);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, _MIN_UNISWAP_TICK);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, 999);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound() external {
        // First set an upper tick bound so we have room to set lower
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 5000);

        ( , UniswapV3Lib.Ticks memory tickBounds, ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 5000);

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolLowerTickUpdated(_pool, -1000);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, -1000);

        ( , tickBounds, ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, -1000);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolLowerTickUpdated(_pool, _MIN_UNISWAP_TICK);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityLowerTickBound(_pool, _MIN_UNISWAP_TICK);

        _assertReentrancyGuardWrittenToTwice();

        ( , tickBounds, ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, _MIN_UNISWAP_TICK);
    }

}

contract MainnetController_Admin_SetUniswapV3AddLiquidityUpperTickBound_Tests is MainnetController_Admin_TestBase {

    int24 internal constant _MAX_UNISWAP_TICK = 887_272;

    address internal immutable _pool         = makeAddr("pool");
    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setUniswapV3AddLiquidityUpperTickBound_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/upper-tick-oob");
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, _MAX_UNISWAP_TICK + 1);

        vm.expectRevert("UniswapV3Lib/upper-tick-oob");
        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 0); // Current lower tick is 0

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, _MAX_UNISWAP_TICK);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 1);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound() external {
        ( , UniswapV3Lib.Ticks memory tickBounds, ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 0);

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolUpperTickUpdated(_pool, 1000);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, 1000);

        ( , tickBounds, ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 1000);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolUpperTickUpdated(_pool, _MAX_UNISWAP_TICK);

        vm.prank(admin);
        mainnetController.setUniswapV3AddLiquidityUpperTickBound(_pool, _MAX_UNISWAP_TICK);

        _assertReentrancyGuardWrittenToTwice();

        ( , tickBounds, ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.upper, _MAX_UNISWAP_TICK);
    }

}

contract MainnetController_Admin_SetUniswapV3TWAPSecondsAgo_Tests is MainnetController_Admin_TestBase {

    address internal immutable _pool         = makeAddr("pool");
    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setUniswapV3TWAPSecondsAgo_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV3TWAPSecondsAgo(_pool, 100);
    }

    function test_setUniswapV3TWAPSecondsAgo_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV3TWAPSecondsAgo(_pool, 300);
    }

    function test_setUniswapV3TWAPSecondsAgo_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/twap-seconds-ago-oob");
        vm.prank(admin);
        mainnetController.setUniswapV3TWAPSecondsAgo(_pool, uint32(type(int32).max));

        vm.prank(admin);
        mainnetController.setUniswapV3TWAPSecondsAgo(_pool, uint32(type(int32).max) - 1);
    }

    function test_setUniswapV3TWAPSecondsAgo() external {
        ( , , uint32 twapSecondsAgo ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(twapSecondsAgo, 0);

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolTWAPSecondsAgoUpdated(_pool, 300);

        vm.prank(admin);
        mainnetController.setUniswapV3TWAPSecondsAgo(_pool, 300);

        ( , , twapSecondsAgo ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(twapSecondsAgo, 300);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit UniswapV3Lib.UniswapV3PoolTWAPSecondsAgoUpdated(_pool, 1800);

        vm.prank(admin);
        mainnetController.setUniswapV3TWAPSecondsAgo(_pool, 1800);

        _assertReentrancyGuardWrittenToTwice();

        ( , , twapSecondsAgo ) = mainnetController.uniswapV3PoolParams(_pool);

        assertEq(twapSecondsAgo, 1800);
    }

}

contract ForeignController_Admin_Tests is UnitTestBase {

    uint24 internal constant _MAX_TICK_DELTA = 887272;

    int24 internal constant _MIN_UNISWAP_TICK = -887_272;
    int24 internal constant _MAX_UNISWAP_TICK =  887_272;

    address internal immutable _pool            = makeAddr("pool");
    address internal immutable _positionManager = makeAddr("positionManager");
    address internal immutable _swapRouter      = makeAddr("swapRouter");
    address internal immutable _unauthorized    = makeAddr("unauthorized");

    ForeignController internal foreignController;

    function setUp() public {
        foreignController = new ForeignController(
            admin,
            makeAddr("almProxy"),
            makeAddr("rateLimits"),
            makeAddr("accessControls"),
            makeAddr("psm"),
            makeAddr("usdc"),
            makeAddr("cctp")
        );
    }

    function _setControllerEntered() internal {
        vm.store(address(foreignController), _REENTRANCY_GUARD_SLOT, _REENTRANCY_GUARD_ENTERED);
    }

    function _assertReentrancyGuardWrittenToTwice() internal {
        _assertReentrancyGuardWrittenToTwice(address(foreignController));
    }

    function test_setMaxSlippage_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxSlippage(makeAddr("pool"), 0.98e18);

        vm.prank(freezer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage_poolZeroAddress() external {
        vm.prank(admin);
        vm.expectRevert("FC/pool-zero-address");
        foreignController.setMaxSlippage(address(0), 0.98e18);
    }

    function test_setMaxSlippage() external {
        address pool = makeAddr("pool");

        assertEq(foreignController.maxSlippages(pool), 0);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MaxSlippageSet(pool, 0.98e18);
        foreignController.setMaxSlippage(pool, 0.98e18);

        assertEq(foreignController.maxSlippages(pool), 0.98e18);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MaxSlippageSet(pool, 0.99e18);
        foreignController.setMaxSlippage(pool, 0.99e18);

        assertEq(foreignController.maxSlippages(pool), 0.99e18);

        _assertReentrancyGuardWrittenToTwice();
    }

    function test_setUniswapV3PositionManager_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setUniswapV3PositionManager(_positionManager);
    }

    function test_setUniswapV3PositionManager_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        foreignController.setUniswapV3PositionManager(_positionManager);
    }

    function test_setUniswapV3PositionManager() external {
        assertEq(foreignController.uniswapV3PositionManager(), address(0));

        vm.record();

        vm.expectEmit(address(foreignController));
        emit ForeignController.UniswapV3PositionManagerSet(_positionManager);

        vm.prank(admin);
        foreignController.setUniswapV3PositionManager(_positionManager);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(foreignController.uniswapV3PositionManager(), _positionManager);
    }

    function test_setUniswapV3SwapRouter_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setUniswapV3SwapRouter(_swapRouter);
    }

    function test_setUniswapV3SwapRouter_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        foreignController.setUniswapV3SwapRouter(_swapRouter);
    }

    function test_setUniswapV3SwapRouter() external {
        assertEq(foreignController.uniswapV3Router(), address(0));

        vm.record();

        vm.expectEmit(address(foreignController));
        emit ForeignController.UniswapV3SwapRouterSet(_swapRouter);

        vm.prank(admin);
        foreignController.setUniswapV3SwapRouter(_swapRouter);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(foreignController.uniswapV3Router(), _swapRouter);
    }

    function test_setUniswapV3PoolMaxTickDelta_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, 10);
    }

    function test_setUniswapV3PoolMaxTickDelta_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, 1000);
    }

    function test_setUniswapV3PoolMaxTickDelta_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/max-tick-delta-oob");
        vm.prank(admin);
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, 0);

        vm.prank(admin);
        vm.expectRevert("UniswapV3Lib/max-tick-delta-oob");
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, _MAX_TICK_DELTA + 1);

        // Can set at boundary

        vm.prank(admin);
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, 1);

        vm.prank(admin);
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, _MAX_TICK_DELTA);
    }

    function test_setUniswapV3PoolMaxTickDelta() external {
        ( uint24 maxTickDelta, , ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(maxTickDelta, 0);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolMaxTickDeltaSet(_pool, 1000);

        vm.prank(admin);
        foreignController.setUniswapV3PoolMaxTickDelta(_pool, 1000);

        _assertReentrancyGuardWrittenToTwice();

        ( maxTickDelta, , ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(maxTickDelta, 1000);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/lower-tick-oob");
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, _MIN_UNISWAP_TICK - 1);

        // First set an upper tick bound
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 1000);

        // Try to set lower tick at the upper tick
        vm.prank(admin);
        vm.expectRevert("UniswapV3Lib/lower-tick-oob");
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, 1000);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, _MIN_UNISWAP_TICK);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, 999);
    }

    function test_setUniswapV3AddLiquidityLowerTickBound() external {
        // First set an upper tick bound so we have room to set lower
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 5000);

        ( , UniswapV3Lib.Ticks memory tickBounds, ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 5000);

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolLowerTickUpdated(_pool, -1000);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, -1000);

        ( , tickBounds, ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, -1000);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolLowerTickUpdated(_pool, _MIN_UNISWAP_TICK);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityLowerTickBound(_pool, _MIN_UNISWAP_TICK);

        _assertReentrancyGuardWrittenToTwice();

        ( , tickBounds, ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, _MIN_UNISWAP_TICK);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 100);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/upper-tick-oob");
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, _MAX_UNISWAP_TICK + 1);

        vm.expectRevert("UniswapV3Lib/upper-tick-oob");
        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 0); // Current lower tick is 0

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, _MAX_UNISWAP_TICK);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 1);
    }

    function test_setUniswapV3AddLiquidityUpperTickBound() external {
        ( , UniswapV3Lib.Ticks memory tickBounds, ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 0);

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolUpperTickUpdated(_pool, 1000);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, 1000);

        ( , tickBounds, ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.lower, 0);
        assertEq(tickBounds.upper, 1000);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolUpperTickUpdated(_pool, _MAX_UNISWAP_TICK);

        vm.prank(admin);
        foreignController.setUniswapV3AddLiquidityUpperTickBound(_pool, _MAX_UNISWAP_TICK);

        _assertReentrancyGuardWrittenToTwice();

        ( , tickBounds, ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(tickBounds.upper, _MAX_UNISWAP_TICK);
    }

    function test_setUniswapV3TWAPSecondsAgo_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setUniswapV3TWAPSecondsAgo(_pool, 100);
    }

    function test_setUniswapV3TWAPSecondsAgo_unauthorizedAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        foreignController.setUniswapV3TWAPSecondsAgo(_pool, 300);
    }

    function test_setUniswapV3TWAPSecondsAgo_outOfBoundsBoundary() external {
        vm.expectRevert("UniswapV3Lib/twap-seconds-ago-oob");
        vm.prank(admin);
        foreignController.setUniswapV3TWAPSecondsAgo(_pool, uint32(type(int32).max));

        vm.prank(admin);
        foreignController.setUniswapV3TWAPSecondsAgo(_pool, uint32(type(int32).max) - 1);
    }

    function test_setUniswapV3TWAPSecondsAgo() external {
        ( , , uint32 twapSecondsAgo ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(twapSecondsAgo, 0);

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolTWAPSecondsAgoUpdated(_pool, 300);

        vm.prank(admin);
        foreignController.setUniswapV3TWAPSecondsAgo(_pool, 300);

        ( , , twapSecondsAgo ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(twapSecondsAgo, 300);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit UniswapV3Lib.UniswapV3PoolTWAPSecondsAgoUpdated(_pool, 1800);

        vm.prank(admin);
        foreignController.setUniswapV3TWAPSecondsAgo(_pool, 1800);

        _assertReentrancyGuardWrittenToTwice();

        ( , , twapSecondsAgo ) = foreignController.uniswapV3PoolParams(_pool);

        assertEq(twapSecondsAgo, 1800);
    }

}
