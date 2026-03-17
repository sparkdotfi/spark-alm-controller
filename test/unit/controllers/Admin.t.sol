// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAccessControl }  from "../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { CCTPLib }      from "../../../src/libraries/CCTPLib.sol";
import { ERC4626Lib }   from "../../../src/libraries/ERC4626Lib.sol";
import { LayerZeroLib } from "../../../src/libraries/LayerZeroLib.sol";
import { OTCLib }       from "../../../src/libraries/OTCLib.sol";
import { UniswapV3Lib } from "../../../src/libraries/UniswapV3Lib.sol";
import { UniswapV4Lib } from "../../../src/libraries/UniswapV4Lib.sol";

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import { UnitTestBase } from "../UnitTestBase.t.sol";

abstract contract MainnetController_Admin_TestBase is UnitTestBase {

    bytes32 internal layerZeroRecipient1 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient1"))));
    bytes32 internal layerZeroRecipient2 = bytes32(uint256(uint160(makeAddr("layerZeroRecipient2"))));
    bytes32 internal mintRecipient1      = bytes32(uint256(uint160(makeAddr("mintRecipient1"))));
    bytes32 internal mintRecipient2      = bytes32(uint256(uint160(makeAddr("mintRecipient2"))));

    MainnetController internal mainnetController;

    function setUp() public {
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

contract MainnetController_Admin_SetCCTPMaxFeeCap_Tests is MainnetController_Admin_TestBase {

    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setCCTPMaxFeeCap_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setCCTPMaxFeeCap(1e18);
    }

    function test_setCCTPMaxFeeCap_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            _unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(_unauthorized);
        mainnetController.setCCTPMaxFeeCap(1e18);
    }

    function test_setCCTPMaxFeeCap() external {
        assertEq(mainnetController.cctpMaxFeeCap(), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit MainnetController.CCTPMaxFeeCapSet(1e18);

        vm.prank(admin);
        mainnetController.setCCTPMaxFeeCap(1e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.cctpMaxFeeCap(), 1e18);
    }

}

contract MainnetController_Admin_SetMintRecipient_Tests is MainnetController_Admin_TestBase {

    function test_setMintRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMintRecipient(1, mintRecipient1);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(freezer);
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient() external {
        assertEq(mainnetController.mintRecipients(1), bytes32(0));
        assertEq(mainnetController.mintRecipients(2), bytes32(0));

        vm.expectEmit(address(mainnetController));
        emit CCTPLib.MintRecipientSet(1, mintRecipient1);

        vm.prank(admin);
        mainnetController.setMintRecipient(1, mintRecipient1);

        assertEq(mainnetController.mintRecipients(1), mintRecipient1);

        vm.expectEmit(address(mainnetController));
        emit CCTPLib.MintRecipientSet(2, mintRecipient2);

        vm.prank(admin);
        mainnetController.setMintRecipient(2, mintRecipient2);

        assertEq(mainnetController.mintRecipients(2), mintRecipient2);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit CCTPLib.MintRecipientSet(1, mintRecipient2);

        vm.prank(admin);
        mainnetController.setMintRecipient(1, mintRecipient2);

        assertEq(mainnetController.mintRecipients(1), mintRecipient2);

        _assertReentrancyGuardWrittenToTwice();
    }

}

contract MainnetController_Admin_SetLayerZeroRecipient_Tests is MainnetController_Admin_TestBase {

    function test_setLayerZeroRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

    function test_setLayerZeroRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(freezer);
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

    function test_setLayerZeroRecipient() external {
        assertEq(mainnetController.layerZeroRecipients(1), bytes32(0));
        assertEq(mainnetController.layerZeroRecipients(2), bytes32(0));

        vm.expectEmit(address(mainnetController));
        emit LayerZeroLib.LayerZeroRecipientSet(1, layerZeroRecipient1);

        vm.prank(admin);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.expectEmit(address(mainnetController));
        emit LayerZeroLib.LayerZeroRecipientSet(2, layerZeroRecipient2);

        vm.prank(admin);
        mainnetController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit LayerZeroLib.LayerZeroRecipientSet(1, layerZeroRecipient2);

        vm.prank(admin);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient2);

        _assertReentrancyGuardWrittenToTwice();
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

contract MainnetController_Admin_SetOTCBuffer_Tests is MainnetController_Admin_TestBase {

    address exchange  = makeAddr("exchange");
    address otcBuffer = makeAddr("otcBuffer");

    function test_setOTCBuffer_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
    }

    function test_setOTCBuffer_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
    }

    function test_setOTCBuffer_exchangeZero() external {
        vm.expectRevert("OTCLib/exchange-zero-address");
        vm.prank(admin);
        mainnetController.setOTCBuffer(address(0), address(otcBuffer));
    }

    function test_setOTCBuffer_otcBufferZero() external {
        vm.expectRevert("OTCLib/otcBuffer-zero-address");
        vm.prank(admin);
        mainnetController.setOTCBuffer(exchange, address(0));
    }

    function test_setOTCBuffer_exchangeEqualsOTCBuffer() external {
        vm.expectRevert("OTCLib/exchange-equals-otcBuffer");
        vm.prank(admin);
        mainnetController.setOTCBuffer(address(otcBuffer), address(otcBuffer));
    }

    function test_setOTCBuffer() external {
        ( address otcBuffer_, , , , ) = mainnetController.otcs(exchange);

        assertEq(otcBuffer_, address(0));

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCBufferSet(exchange, address(otcBuffer));

        vm.prank(admin);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        _assertReentrancyGuardWrittenToTwice();

        ( otcBuffer_, , , , ) = mainnetController.otcs(exchange);

        assertEq(otcBuffer_, address(otcBuffer));
    }

}

contract MainnetController_Admin_SetOTCRechargeRate_Tests is MainnetController_Admin_TestBase {

    address exchange = makeAddr("exchange");

    function test_setOTCRechargeRate_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);
    }

    function test_setOTCRechargeRate_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);
    }

    function test_setOTCRechargeRate_exchangeZero() external {
        vm.expectRevert("OTCLib/exchange-zero-address");
        vm.prank(admin);
        mainnetController.setOTCRechargeRate(address(0), uint256(1_000_000e18) / 1 days);
    }

    function test_setOTCRechargeRate() external {
        ( , uint256 rate18, , , ) = mainnetController.otcs(exchange);
        assertEq(rate18, 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCRechargeRateSet(exchange, uint256(1_000_000e18) / 1 days);

        vm.prank(admin);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        _assertReentrancyGuardWrittenToTwice();

        ( , rate18, , , ) = mainnetController.otcs(exchange);
        assertEq(rate18, uint256(1_000_000e18) / 1 days);
    }

}

contract MainnetController_Admin_SetOTCWhitelistedAsset_Tests is MainnetController_Admin_TestBase {

    address asset    = makeAddr("asset");
    address exchange = makeAddr("exchange");

    function test_setOTCWhitelistedAsset_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setOTCWhitelistedAsset(exchange, asset, true);
    }

    function test_setOTCWhitelistedAsset_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setOTCWhitelistedAsset(exchange, asset, true);
    }

    function test_setOTCWhitelistedAsset_exchangeZero() external {
        vm.expectRevert("OTCLib/exchange-zero-address");
        vm.prank(admin);
        mainnetController.setOTCWhitelistedAsset(address(0), asset, true);
    }

    function test_setOTCWhitelistedAsset_assetZero() external {
        vm.expectRevert("OTCLib/asset-zero-address");
        vm.prank(admin);
        mainnetController.setOTCWhitelistedAsset(exchange, address(0), true);
    }

    function test_setOTCWhitelistedAsset_otcBufferNotSet() external {
        vm.expectRevert("OTCLib/otc-buffer-not-set");
        vm.prank(admin);
        mainnetController.setOTCWhitelistedAsset(makeAddr("fake-exchange"), asset, true);
    }

    function test_setOTCWhitelistedAsset() external {
        vm.startPrank(admin);

        mainnetController.setOTCBuffer(exchange, asset);

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCWhitelistedAssetSet(exchange, asset, true);

        mainnetController.setOTCWhitelistedAsset(exchange, asset, true);

        vm.stopPrank();

        assertEq(mainnetController.otcWhitelistedAssets(exchange, asset), true);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit OTCLib.OTCWhitelistedAssetSet(exchange, asset, false);

        vm.prank(admin);
        mainnetController.setOTCWhitelistedAsset(exchange, asset, false);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.otcWhitelistedAssets(exchange, asset), false);
    }

}

contract MainnetController_Admin_SetMaxExchangeRate_Tests is MainnetController_Admin_TestBase {

    function test_setMaxExchangeRate_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);
    }

    function test_setMaxExchangeRate_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);
    }

    function test_setMaxExchangeRate_tokenZeroAddress() external {
        vm.expectRevert("ERC4626Lib/token-zero-address");
        vm.prank(admin);
        mainnetController.setMaxExchangeRate(address(0), 1e18, 1e18);
    }

    function test_setMaxExchangeRate() external {
        address token = makeAddr("token");

        assertEq(mainnetController.maxExchangeRates(token), 0);

        vm.record();

        vm.expectEmit(address(mainnetController));
        emit ERC4626Lib.MaxExchangeRateSet(token, 1e36);

        vm.prank(admin);
        mainnetController.setMaxExchangeRate(token, 1e18, 1e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.maxExchangeRates(token), 1e36);

        vm.expectEmit(address(mainnetController));
        emit ERC4626Lib.MaxExchangeRateSet(token, 1e24);

        vm.prank(admin);
        mainnetController.setMaxExchangeRate(token, 1e18, 1e6);

        assertEq(mainnetController.maxExchangeRates(token), 1e24);

        vm.expectEmit(address(mainnetController));
        emit ERC4626Lib.MaxExchangeRateSet(token, 1e48);

        vm.prank(admin);
        mainnetController.setMaxExchangeRate(token, 1e6, 1e18);

        assertEq(mainnetController.maxExchangeRates(token), 1e48);
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

contract MainnetController_Admin_SetUniswapV4TickLimits_Tests is MainnetController_Admin_TestBase {

    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setUniswapV4TickLimits_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setUniswapV4TickLimits_revertsForNonAdmin() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setUniswapV4TickLimits_revertsWhenInvalidTicks() external {
        vm.expectRevert("UniswapV4Lib/invalid-ticks");
        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 1, 1, 1); // Reverts when lower >= upper

        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 1, 1); // lower must be less than upper

        vm.expectRevert("UniswapV4Lib/invalid-ticks");
        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 1, 0); // Reverts when maxTickSpacing is zero

        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0, 0); // maxTickSpacing can only be 0 if all 0
    }

    function test_setUniswapV4TickLimits() external {
        vm.expectEmit(address(mainnetController));
        emit UniswapV4Lib.UniswapV4TickLimitsSet(_POOL_ID, -60, 60, 20);

        vm.record();

        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);

        _assertReentrancyGuardWrittenToTwice();

        ( int24 tickLowerMin, int24 tickUpperMax, uint24 maxTickSpacing ) = mainnetController.uniswapV4TickLimits(_POOL_ID);

        assertEq(tickLowerMin,   -60);
        assertEq(tickUpperMax,   60);
        assertEq(maxTickSpacing, 20);
    }

}

contract MainnetController_Admin_SetMerklDistributor_Tests is MainnetController_Admin_TestBase {

    event MerklDistributorSet(address indexed merklDistributor);

    address internal immutable _unauthorized = makeAddr("unauthorized");

    function test_setMerklDistributor_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setMerklDistributor(makeAddr("merklDistributor"));
    }

    function test_setMerklDistributor_unauthorizedAccount() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                DEFAULT_ADMIN_ROLE
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setMerklDistributor(makeAddr("merklDistributor"));
    }

    function test_setMerklDistributor() public {
        address merklDistributor = makeAddr("merklDistributor");

        assertEq(address(mainnetController.merklDistributor()), address(0));

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MerklDistributorSet(merklDistributor);
        mainnetController.setMerklDistributor(merklDistributor);

        assertEq(address(mainnetController.merklDistributor()), merklDistributor);
    }

}

contract ForeignController_Admin_Tests is UnitTestBase {

    event MerklDistributorSet(address indexed merklDistributor);

    uint24 internal constant _MAX_TICK_DELTA = 887272;

    int24 internal constant _MIN_UNISWAP_TICK = -887_272;
    int24 internal constant _MAX_UNISWAP_TICK =  887_272;

    address internal immutable _pool            = makeAddr("pool");
    address internal immutable _positionManager = makeAddr("positionManager");
    address internal immutable _swapRouter      = makeAddr("swapRouter");
    address internal immutable _unauthorized    = makeAddr("unauthorized");

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

    function test_setCCTPMaxFeeCap_reentrancy() external {
        _setControllerEntered();

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setCCTPMaxFeeCap(1e18);
    }

    function test_setCCTPMaxFeeCap_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            _unauthorized,
            DEFAULT_ADMIN_ROLE
        ));

        vm.prank(_unauthorized);
        foreignController.setCCTPMaxFeeCap(1e18);
    }

    function test_setCCTPMaxFeeCap() external {
        assertEq(foreignController.cctpMaxFeeCap(), 0);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit ForeignController.CCTPMaxFeeCapSet(1e18);

        vm.prank(admin);
        foreignController.setCCTPMaxFeeCap(1e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(foreignController.cctpMaxFeeCap(), 1e18);
    }

    function test_setMintRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setMintRecipient(1, mintRecipient1);
    }

    function test_setMintRecipient_unauthorizedAccount() external {
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

    function test_setMintRecipient() external {
        assertEq(foreignController.mintRecipients(1), bytes32(0));
        assertEq(foreignController.mintRecipients(2), bytes32(0));

        vm.expectEmit(address(foreignController));
        emit CCTPLib.MintRecipientSet(1, mintRecipient1);

        vm.prank(admin);
        foreignController.setMintRecipient(1, mintRecipient1);

        assertEq(foreignController.mintRecipients(1), mintRecipient1);

        vm.expectEmit(address(foreignController));
        emit CCTPLib.MintRecipientSet(2, mintRecipient2);

        vm.prank(admin);
        foreignController.setMintRecipient(2, mintRecipient2);

        assertEq(foreignController.mintRecipients(2), mintRecipient2);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit CCTPLib.MintRecipientSet(1, mintRecipient2);

        vm.prank(admin);
        foreignController.setMintRecipient(1, mintRecipient2);

        assertEq(foreignController.mintRecipients(1), mintRecipient2);

        _assertReentrancyGuardWrittenToTwice();
    }

    function test_setLayerZeroRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

    function test_setLayerZeroRecipient_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            freezer,
            DEFAULT_ADMIN_ROLE
        ));
        vm.prank(freezer);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

    function test_setLayerZeroRecipient() external {
        assertEq(foreignController.layerZeroRecipients(1), bytes32(0));
        assertEq(foreignController.layerZeroRecipients(2), bytes32(0));

        vm.expectEmit(address(foreignController));
        emit LayerZeroLib.LayerZeroRecipientSet(1, layerZeroRecipient1);

        vm.prank(admin);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.expectEmit(address(foreignController));
        emit LayerZeroLib.LayerZeroRecipientSet(2, layerZeroRecipient2);

        vm.prank(admin);
        foreignController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit LayerZeroLib.LayerZeroRecipientSet(1, layerZeroRecipient2);

        vm.prank(admin);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient2);

        _assertReentrancyGuardWrittenToTwice();
    }

    function test_setMaxExchangeRate_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);
    }

    function test_setMaxExchangeRate_unauthorizedAccount() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMaxExchangeRate(makeAddr("token"), 1e18, 1e18);
    }

    function test_setMaxExchangeRate_tokenZeroAddress() external {
        vm.expectRevert("ERC4626Lib/token-zero-address");
        vm.prank(admin);
        foreignController.setMaxExchangeRate(address(0), 1e18, 1e18);
    }

    function test_setMaxExchangeRate() external {
        address token = makeAddr("token");

        assertEq(foreignController.maxExchangeRates(token), 0);

        vm.record();

        vm.expectEmit(address(foreignController));
        emit ERC4626Lib.MaxExchangeRateSet(token, 1e36);

        vm.prank(admin);
        foreignController.setMaxExchangeRate(token, 1e18, 1e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(foreignController.maxExchangeRates(token), 1e36);

        vm.expectEmit(address(foreignController));
        emit ERC4626Lib.MaxExchangeRateSet(token, 1e24);

        vm.prank(admin);
        foreignController.setMaxExchangeRate(token, 1e18, 1e6);

        assertEq(foreignController.maxExchangeRates(token), 1e24);

        vm.expectEmit(address(foreignController));
        emit ERC4626Lib.MaxExchangeRateSet(token, 1e48);

        vm.prank(admin);
        foreignController.setMaxExchangeRate(token, 1e6, 1e18);

        assertEq(foreignController.maxExchangeRates(token), 1e48);
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

    function test_setMerklDistributor_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setMerklDistributor(makeAddr("merklDistributor"));
    }

    function test_setMerklDistributor_unauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        foreignController.setMerklDistributor(makeAddr("merklDistributor"));
    }

    function test_setMerklDistributor() public {
        address merklDistributor = makeAddr("merklDistributor");

        assertEq(address(foreignController.merklDistributor()), address(0));

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit MerklDistributorSet(merklDistributor);
        foreignController.setMerklDistributor(merklDistributor);

        assertEq(address(foreignController.merklDistributor()), merklDistributor);
    }

}
