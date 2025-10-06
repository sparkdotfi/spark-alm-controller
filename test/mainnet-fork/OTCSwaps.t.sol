// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock }      from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 }      from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { OTCSwapState } from "src/MainnetController.sol";

import { OTCBuffer } from "src/OTCBuffer.sol";

import "./ForkTestBase.t.sol";

// Mock ERC20 with variable decimals
contract ERC20 is ERC20Mock {

    uint8 immutable internal _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

}

contract MainnetControllerOTCSwapBase is ForkTestBase {

    bytes32 LIMIT_OTC_SWAP = keccak256("LIMIT_OTC_SWAP");

    bytes32 key;

    OTCBuffer otcBuffer;
    // 12-decimal asset
    IERC20    asset_12;

    event OTCBufferSet(
        address indexed exchange,
        address indexed newOTCBuffer,
        address indexed oldOTCBuffer
    );
    event OTCSwapSent(
        address indexed exchange,
        address indexed buffer,
        address indexed tokenSent,
        uint256 amountSent,
        uint256 amountSent18
    );
    event OTCClaimed(
        address indexed exchange,
        address indexed buffer,
        address indexed assetClaimed,
        uint256 amountClaimed,
        uint256 amountClaimed18
    );
    event OTCRechargeRateSet(address indexed exchange, uint256 oldRate18, uint256 newRate18);

    address exchange = makeAddr("exchange");

    function setUp() public virtual override {
        super.setUp();

        // 1. Deploy OTCBuffer
        otcBuffer = new OTCBuffer(Ethereum.SPARK_PROXY);

        // 2. Deploy 12-decimal asset
        asset_12 = IERC20(address(new ERC20(12)));

        // 3. Set allowance
        vm.startPrank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(usdt),     address(almProxy), type(uint256).max);
        otcBuffer.approve(address(asset_12), address(almProxy), type(uint256).max);
        otcBuffer.approve(address(usds),     address(almProxy), type(uint256).max);
        vm.stopPrank();

        // 4. Set rate limits
        // This can be done because it doesn't depend on the asset
        key = RateLimitHelpers.makeAssetKey(
            LIMIT_OTC_SWAP,
            exchange
        );
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        // 5. Set maxSlippages
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(exchange, 1e18 - 0.05e18); // 100% - 5% == 95%

        // 6. Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
    }

    function _getAssetByDecimals(uint8 decimals) internal view returns (IERC20) {
        // This will use USDT for 6 decimals and USDS for 18 decimals.
        if (decimals == 6) {
            return usdt;
        } else if (decimals == 12) {
            return asset_12;
        } else if (decimals == 18) {
            return usds;
        }
        revert("Invalid decimals");
    }
}

contract MainnetControllerOTCSwapSendFailureTests is MainnetControllerOTCSwapBase {

    function test_otcSwapSend_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcSwapSend(exchange, address(1), 1e18);
    }

    function test_otcSwapSend_assetToSendZero() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/asset-to-send-zero");
        mainnetController.otcSwapSend(exchange, address(0), 1e18);
    }

    function test_otcSwapSend_amountToSendZero() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/amount-to-send-zero");
        mainnetController.otcSwapSend(exchange, address(asset_12), 0);
    }

    function otcSwapSend_rateLimitZero() external {
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 0, 0);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.otcSwapSend(exchange, address(asset_12), 1e18);
    }

    function test_otcSwapSend_rateLimitedBoundary() external {
        uint256 id = vm.snapshotState();
        for (uint8 decimalsSend = 6; decimalsSend <= 18; decimalsSend += 6) {
            vm.revertToState(id);
            IERC20 assetToSend = _getAssetByDecimals(decimalsSend);

            skip(1 days);
            uint256 maxRateLimit = 10_000_000e18;
            assertEq(rateLimits.getCurrentRateLimit(key), maxRateLimit);
            // The controller decreases rate limit by sent18, which is:
            //   `uint256 sent18 = amountToSend * 1e18 / 10 ** IERC20Metadata(assetToSend).decimals();`
            // Hence maximum amountToSend is: `maxRateLimit * 10 ** decimalsSend / 1e18`
            uint256 maxAmountToSend = maxRateLimit * 10 ** decimalsSend / 1e18;

            deal(address(assetToSend), address(almProxy), maxAmountToSend + 1);
            vm.startPrank(relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            mainnetController.otcSwapSend(exchange, address(assetToSend), maxAmountToSend + 1);

            mainnetController.otcSwapSend(exchange, address(assetToSend), maxAmountToSend);
            vm.stopPrank();
        }
    }

    function test_otcSwapSend_otcBufferNotSet() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(0));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcSwapSend(exchange, address(asset_12), 1e18);
    }

    function test_otcSwapSend_lastSwapNotReturned() external {
        // Mint tokens
        // In this test it is prudent to use less than 10M so rate limit is not reached.
        deal(address(asset_12), address(almProxy), 5_000_000e12);

        assertEq(asset_12.balanceOf(address(exchange)), 0);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(asset_12), 5_000_000e12, 5_000_000e18);
        mainnetController.otcSwapSend(exchange, address(asset_12), 5_000_000e12);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );
        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        5_000_000e18);
        assertEq(claimed18,     0);

        // Try to do another one
        skip(1 seconds);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSwapSend(exchange, address(asset_12), 1e18);
    }

}

contract MainnetControllerOTCSwapSendSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcSwapSend() external {
        // Mint tokens
        deal(address(asset_12), address(almProxy), 10_000_000e12);

        assertEq(asset_12.balanceOf(address(almProxy)), 10_000_000e12);
        assertEq(asset_12.balanceOf(address(exchange)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(asset_12), 10_000_000e12, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(asset_12), 10_000_000e12);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18, 10_000_000e18);
        assertEq(claimed18, 0);

        assertEq(asset_12.balanceOf(address(almProxy)), 0);
        assertEq(asset_12.balanceOf(address(exchange)), 10_000_000e12);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

contract MainnetControllerOTCClaimFailureTests is MainnetControllerOTCSwapBase {

    function test_otcClaim_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcClaim(exchange, address(1), 1e18);
    }

    function test_otcClaim_assetToClaimZero() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/asset-to-claim-zero");
        mainnetController.otcClaim(exchange, address(0), 1e18);
    }

    function test_otcClaim_amountToClaimZero() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/amount-to-claim-zero");
        mainnetController.otcClaim(exchange, address(1), 0);
    }

    function test_otcClaim_otcBufferNotSet() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(0));

        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcClaim(exchange, address(1), 1e18);
    }

}

contract MainnetControllerOTCClaimSuccessTests is MainnetControllerOTCSwapBase {

    function test_e2e_swapUsdtToUsds() external {
        uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));
        uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));

        // Mint tokens
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(address(usds), address(exchange), 9_500_000e18);

        assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy + 10_000_000e6);
        assertEq(usds.balanceOf(address(otcBuffer)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(usdt), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), usdtBalanceALMProxy);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.prank(exchange);
        SafeERC20.safeTransfer(IERC20Metadata(address(usds)), address(otcBuffer), 9_500_000e18);

        assertEq(usds.balanceOf(address(otcBuffer)), 9_500_000e18);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     0);

        assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy);
        assertEq(usds.balanceOf(address(otcBuffer)), 9_500_000e18);

        skip(1 days);

        // Claim
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(otcBuffer), address(usds), 9_500_000e18, 9_500_000e18);
        mainnetController.otcClaim(exchange, address(usds), 9_500_000e18);

        (swapTimestamp, sent18, claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, block.timestamp - 1 days);
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     9_500_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  9_500_000e18);
        assertEq(usds.balanceOf(address(otcBuffer)), 0);
    }

    function test_e2e_swapUsdtToUsds_withRecharge() external {
        uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));
        uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        // Mint tokens
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(address(usds), address(exchange), 8_500_000e18);

        assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy + 10_000_000e6);
        assertEq(usds.balanceOf(address(otcBuffer)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(usdt), 10_000_000e6);

        assertEq(usdt.balanceOf(address(almProxy)), usdtBalanceALMProxy);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.prank(exchange);
        SafeERC20.safeTransfer(IERC20Metadata(address(usds)), address(otcBuffer), 8_500_000e18);

        assertEq(usds.balanceOf(address(otcBuffer)), 8_500_000e18);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     0);

        assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy);
        assertEq(usds.balanceOf(address(otcBuffer)), 8_500_000e18);

        skip(1 days);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        // Claim
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(otcBuffer), address(usds), 8_500_000e18, 8_500_000e18);
        mainnetController.otcClaim(exchange, address(usds), 8_500_000e18);

        (swapTimestamp, sent18, claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, block.timestamp - 1 days);
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     8_500_000e18);

        // Still not ready
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        skip(1 seconds);

        // Now it is ready
        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy + 8_500_000e18);
        assertEq(usds.balanceOf(address(otcBuffer)), 0);
    }

    function test_e2e_swapUsdsToUsdt() external {
        uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));
        uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));

        // Mint tokens
        deal(address(usds), address(almProxy), 10_000_000e18);
        deal(address(usdt), address(exchange), 9_500_000e6);

        assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy + 10_000_000e18);
        assertEq(usdt.balanceOf(address(otcBuffer)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(usds), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), usdsBalanceALMProxy);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.prank(exchange);
        SafeERC20.safeTransfer(IERC20Metadata(address(usdt)), address(otcBuffer), 9_500_000e6);

        assertEq(usdt.balanceOf(address(otcBuffer)), 9_500_000e6);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     0);

        assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy);
        assertEq(usdt.balanceOf(address(otcBuffer)), 9_500_000e6);

        skip(1 days);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        // Claim
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(otcBuffer), address(usdt), 9_500_000e6, 9_500_000e18);
        mainnetController.otcClaim(exchange, address(usdt), 9_500_000e6);

        (swapTimestamp, sent18, claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, block.timestamp - 1 days);
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     9_500_000e18);

        assertEq(usdt.balanceOf(address(almProxy)),  9_500_000e6);
        assertEq(usdt.balanceOf(address(otcBuffer)), 0);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function test_e2e_swapUsdsToUsdt_withRecharge() external {
        uint256 usdsBalanceALMProxy = usds.balanceOf(address(almProxy));
        uint256 usdtBalanceALMProxy = usdt.balanceOf(address(almProxy));

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        // Mint tokens
        deal(address(usds), address(almProxy), 10_000_000e18);
        deal(address(usdt), address(exchange), 8_500_000e6);

        assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy + 10_000_000e18);
        assertEq(usdt.balanceOf(address(otcBuffer)), 0);

        assertEq(rateLimits.getCurrentRateLimit(key), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usds), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(usds), 10_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)),  usdsBalanceALMProxy);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);

        vm.prank(exchange);
        SafeERC20.safeTransfer(IERC20Metadata(address(usdt)), address(otcBuffer), 8_500_000e6);

        assertEq(usdt.balanceOf(address(otcBuffer)), 8_500_000e6);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     0);

        assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy);
        assertEq(usdt.balanceOf(address(otcBuffer)), 8_500_000e6);

        skip(1 days);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        // Claim
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(exchange, address(otcBuffer), address(usdt), 8_500_000e6, 8_500_000e18);
        mainnetController.otcClaim(exchange, address(usdt), 8_500_000e6);

        (swapTimestamp, sent18, claimed18) = mainnetController.otcSwapStates(exchange);

        assertEq(swapTimestamp, block.timestamp - 1 days);
        assertEq(sent18,        10_000_000e18);
        assertEq(claimed18,     8_500_000e18);

        // Still not ready
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        skip(1 seconds);

        // Now it is ready
        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));

        assertEq(usdt.balanceOf(address(almProxy)),  usdtBalanceALMProxy + 8_500_000e6);
        assertEq(usdt.balanceOf(address(otcBuffer)), 0);
    }

}

contract MainnetControlerGetClaimedWithRechargeTests is MainnetControllerOTCSwapBase {

    function test_getClaimedWithRecharge() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        // Mint tokens
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(address(usds), address(exchange), 5_500_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSwapSend(
            exchange,
            address(usdt),
            10_000_000e6
        );

        vm.prank(exchange);
        usds.transfer(address(otcBuffer), 5_500_000e18);

        // Claim
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds), 5_500_000e18);

        assertEq(mainnetController.getClaimedWithRecharge(exchange), 5_500_000e18);

        skip(1 days);
        assertEq(mainnetController.getClaimedWithRecharge(exchange), 6_499_999.999999999999993600e18);

        skip(1 days);
        assertEq(mainnetController.getClaimedWithRecharge(exchange), 7_499_999.999999999999987200e18);

        skip(2 days);
        assertEq(mainnetController.getClaimedWithRecharge(exchange), 9_499_999.999999999999974400e18);

        skip(1 days);
        assertEq(mainnetController.getClaimedWithRecharge(exchange), 10_499999.999999999999968000e18);

        skip(10 days);
        assertEq(mainnetController.getClaimedWithRecharge(exchange), 20_499_999.999999999999904000e18);
    }

}

contract MainnetControllerIsOTCSwapReadySuccessTests is MainnetControllerOTCSwapBase {

    function test_isOtcSwapReady_falseWithZeroSlippage() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(exchange, 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function test_isOtcSwapReady() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        // Mint tokens
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(address(usds), address(exchange), 5_500_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(usdt), 10_000_000e6, 10_000_000e18);
        mainnetController.otcSwapSend(
            exchange,
            address(usdt),
            10_000_000e6
        );

        vm.prank(exchange);
        usds.transfer(address(otcBuffer), 5_500_000e18);

        // Claim
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds), 5_500_000e18);

        // Skip time by 4 days to recharge
        skip(4 days);
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        skip(1 seconds);
        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

