// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import { IAccessControl }  from "../../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC20Metadata }  from "../../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 }        from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import { ReentrancyGuard } from "../../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { ForeignController } from "../../../src/ForeignController.sol";
import { MainnetController } from "../../../src/MainnetController.sol";

import { MockDaiUsds } from "../mocks/MockDaiUsds.sol";
import { MockPSM }     from "../mocks/MockPSM.sol";
import { MockVault }   from "../mocks/MockVault.sol";

import "../UnitTestBase.t.sol";

contract MainnetControllerAdminTestBase is UnitTestBase {

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

contract MainnetControllerSetMintRecipientTests is MainnetControllerAdminTestBase {

    function test_setMintRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setMintRecipient(1, mintRecipient1);
    }

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
        emit MainnetController.MintRecipientSet(1, mintRecipient1);
        mainnetController.setMintRecipient(1, mintRecipient1);

        assertEq(mainnetController.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MintRecipientSet(2, mintRecipient2);
        mainnetController.setMintRecipient(2, mintRecipient2);

        assertEq(mainnetController.mintRecipients(2), mintRecipient2);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MintRecipientSet(1, mintRecipient2);
        mainnetController.setMintRecipient(1, mintRecipient2);

        assertEq(mainnetController.mintRecipients(1), mintRecipient2);

        _assertReentrancyGuardWrittenToTwice();
    }

}

contract MainnetControllerSetLayerZeroRecipientTests is MainnetControllerAdminTestBase {

    function test_setLayerZeroRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

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
        emit MainnetController.LayerZeroRecipientSet(1, layerZeroRecipient1);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.LayerZeroRecipientSet(2, layerZeroRecipient2);
        mainnetController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.LayerZeroRecipientSet(1, layerZeroRecipient2);
        mainnetController.setLayerZeroRecipient(1, layerZeroRecipient2);

        assertEq(mainnetController.layerZeroRecipients(1), layerZeroRecipient2);

        _assertReentrancyGuardWrittenToTwice();
    }

}

contract MainnetControllerSetMaxSlippageTests is MainnetControllerAdminTestBase {

    function test_setMaxSlippage_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setMaxSlippage(makeAddr("pool"), 0.98e18);
    }

    function test_setMaxSlippage_unauthorizedAccount() public {
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

    function test_setMaxSlippage_poolZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("MC/pool-zero-address");
        mainnetController.setMaxSlippage(address(0), 0.98e18);
    }

    function test_setMaxSlippage() public {
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

contract MainnetControllerSetOTCBufferTests is MainnetControllerAdminTestBase {

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
        vm.prank(admin);
        vm.expectRevert("MC/exchange-zero-address");
        mainnetController.setOTCBuffer(address(0), address(otcBuffer));
    }

    function test_setOTCBuffer_otcBufferZero() external {
        vm.prank(admin);
        vm.expectRevert("MC/otcBuffer-zero-address");
        mainnetController.setOTCBuffer(exchange, address(0));
    }

    function test_setOTCBuffer_exchangeEqualsOTCBuffer() external {
        vm.prank(admin);
        vm.expectRevert("MC/exchange-equals-otcBuffer");
        mainnetController.setOTCBuffer(address(otcBuffer), address(otcBuffer));
    }

    function test_setOTCBuffer() external {
        ( address otcBuffer_,,,, ) = mainnetController.otcs(exchange);

        assertEq(otcBuffer_, address(0));

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.OTCBufferSet(exchange, address(0), address(otcBuffer));
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        _assertReentrancyGuardWrittenToTwice();

        ( otcBuffer_,,,, ) = mainnetController.otcs(exchange);

        assertEq(otcBuffer_, address(otcBuffer));
    }

}

contract MainnetControllerSetOTCRechargeRateTests is MainnetControllerAdminTestBase {

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

    function test_setOTCRechargeRate() external {
        ( , uint256 rate18,,, ) = mainnetController.otcs(exchange);
        assertEq(rate18, 0);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.OTCRechargeRateSet(exchange, 0, uint256(1_000_000e18) / 1 days);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        _assertReentrancyGuardWrittenToTwice();

        ( , rate18,,, ) = mainnetController.otcs(exchange);
        assertEq(rate18, uint256(1_000_000e18) / 1 days);
    }

}

contract MainnetControllerSetOTCWhitelistedAssetTests is MainnetControllerAdminTestBase {

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
        vm.prank(admin);
        vm.expectRevert("MC/exchange-zero-address");
        mainnetController.setOTCWhitelistedAsset(address(0), asset, true);
    }

    function test_setOTCWhitelistedAsset_assetZero() external {
        vm.prank(admin);
        vm.expectRevert("MC/asset-zero-address");
        mainnetController.setOTCWhitelistedAsset(exchange, address(0), true);
    }

    function test_setOTCWhitelistedAsset_otcBufferNotSet() external {
        vm.prank(admin);
        vm.expectRevert("MC/otc-buffer-not-set");
        mainnetController.setOTCWhitelistedAsset(makeAddr("fake-exchange"), asset, true);
    }

    function test_setOTCWhitelistedAsset() external {
        vm.startPrank(admin);

        mainnetController.setOTCBuffer(exchange, asset);

        vm.expectEmit(address(mainnetController));
        emit MainnetController.OTCWhitelistedAssetSet(exchange, asset, true);
        mainnetController.setOTCWhitelistedAsset(exchange, asset, true);

        vm.stopPrank();

        assertEq(mainnetController.otcWhitelistedAssets(exchange, asset), true);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.OTCWhitelistedAssetSet(exchange, asset, false);
        mainnetController.setOTCWhitelistedAsset(exchange, asset, false);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.otcWhitelistedAssets(exchange, asset), false);
    }

}

contract MainnetControllerSetMaxExchangeRateTests is MainnetControllerAdminTestBase {

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
        vm.prank(admin);
        vm.expectRevert("MC/token-zero-address");
        mainnetController.setMaxExchangeRate(address(0), 1e18, 1e18);
    }

    function test_setMaxExchangeRate() external {
        address token = makeAddr("token");

        assertEq(mainnetController.maxExchangeRates(token), 0);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MaxExchangeRateSet(token, 1e36);
        mainnetController.setMaxExchangeRate(token, 1e18, 1e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(mainnetController.maxExchangeRates(token), 1e36);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MaxExchangeRateSet(token, 1e24);
        mainnetController.setMaxExchangeRate(token, 1e18, 1e6);

        assertEq(mainnetController.maxExchangeRates(token), 1e24);

        vm.prank(admin);
        vm.expectEmit(address(mainnetController));
        emit MainnetController.MaxExchangeRateSet(token, 1e48);
        mainnetController.setMaxExchangeRate(token, 1e6, 1e18);

        assertEq(mainnetController.maxExchangeRates(token), 1e48);
    }

}

contract MainnetControllerSetUniswapV4TickLimitsTests is MainnetControllerAdminTestBase {

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
                mainnetController.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0, 0);
    }

    function test_setUniswapV4TickLimits_revertsWhenInvalidTicks() external {
        vm.prank(admin);
        vm.expectRevert("MC/invalid-ticks");
        mainnetController.setUniswapV4TickLimits(bytes32(0), 1, 1, 1); // Reverts when lower >= upper

        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 1, 1); // lower must be less than upper

        vm.prank(admin);
        vm.expectRevert("MC/invalid-ticks");
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 1, 0); // Reverts when maxTickSpacing is zero

        vm.prank(admin);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0, 0); // maxTickSpacing can only be 0 if all 0
    }

    function test_setUniswapV4TickLimits() external {
        vm.expectEmit(address(mainnetController));
        emit MainnetController.UniswapV4TickLimitsSet(_POOL_ID, -60, 60, 20);

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

contract ForeignControllerAdminTests is UnitTestBase {

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

    function test_setMaxSlippage_unauthorizedAccount() public {
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

    function test_setMaxSlippage_poolZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("FC/pool-zero-address");
        foreignController.setMaxSlippage(address(0), 0.98e18);
    }

    function test_setMaxSlippage() public {
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

    function test_setMintRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setMintRecipient(1, mintRecipient1);
    }

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
        emit ForeignController.MintRecipientSet(1, mintRecipient1);
        foreignController.setMintRecipient(1, mintRecipient1);

        assertEq(foreignController.mintRecipients(1), mintRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MintRecipientSet(2, mintRecipient2);
        foreignController.setMintRecipient(2, mintRecipient2);

        assertEq(foreignController.mintRecipients(2), mintRecipient2);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MintRecipientSet(1, mintRecipient2);
        foreignController.setMintRecipient(1, mintRecipient2);

        assertEq(foreignController.mintRecipients(1), mintRecipient2);

        _assertReentrancyGuardWrittenToTwice();
    }

    function test_setLayerZeroRecipient_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);
    }

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
        emit ForeignController.LayerZeroRecipientSet(1, layerZeroRecipient1);
        foreignController.setLayerZeroRecipient(1, layerZeroRecipient1);

        assertEq(foreignController.layerZeroRecipients(1), layerZeroRecipient1);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.LayerZeroRecipientSet(2, layerZeroRecipient2);
        foreignController.setLayerZeroRecipient(2, layerZeroRecipient2);

        assertEq(foreignController.layerZeroRecipients(2), layerZeroRecipient2);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.LayerZeroRecipientSet(1, layerZeroRecipient2);
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
        vm.prank(admin);
        vm.expectRevert("FC/token-zero-address");
        foreignController.setMaxExchangeRate(address(0), 1e18, 1e18);
    }

    function test_setMaxExchangeRate() external {
        address token = makeAddr("token");

        assertEq(foreignController.maxExchangeRates(token), 0);

        vm.record();

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MaxExchangeRateSet(token, 1e36);
        foreignController.setMaxExchangeRate(token, 1e18, 1e18);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(foreignController.maxExchangeRates(token), 1e36);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MaxExchangeRateSet(token, 1e24);
        foreignController.setMaxExchangeRate(token, 1e18, 1e6);

        assertEq(foreignController.maxExchangeRates(token), 1e24);

        vm.prank(admin);
        vm.expectEmit(address(foreignController));
        emit ForeignController.MaxExchangeRateSet(token, 1e48);
        foreignController.setMaxExchangeRate(token, 1e6, 1e18);

        assertEq(foreignController.maxExchangeRates(token), 1e48);
    }

}
