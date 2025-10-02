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
        mainnetController.setMaxSlippage(exchange, 1e18 - 0.005e18); // 100% - 0.5% == 99.5%
    }

    function _getAssetByDecimals(uint8 decimals) internal returns (IERC20) {
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

    function test_otcSwapSend_rateLimitedBoundary() external {
        uint256 id = vm.snapshotState();
        for (uint8 decimalsSend = 6; decimalsSend <= 18; decimalsSend += 6) {
            vm.revertToState(id);
            IERC20 assetToSend = _getAssetByDecimals(decimalsSend);

            // Set OTC buffer
            vm.prank(Ethereum.SPARK_PROXY);
            mainnetController.setOTCBuffer(exchange, address(otcBuffer));

            skip(1 days);
            uint256 expRateLimit = 10_000_000e18;
            assertEq(rateLimits.getCurrentRateLimit(key), expRateLimit);
            // The controller decreases rate limit by sent18, which is:
            //   `uint256 sent18 = amountToSend * 1e18 / 10 ** IERC20Metadata(assetToSend).decimals();`
            // Hence maximum amountToSend is: `expRateLimit * 10 ** decimalsSend / 1e18`
            uint256 maxAmountToSend = expRateLimit * 10 ** decimalsSend / 1e18;

            deal(address(assetToSend), address(almProxy), maxAmountToSend + 1);
            vm.startPrank(relayer);
            vm.expectRevert("RateLimits/rate-limit-exceeded");
            mainnetController.otcSwapSend(exchange, address(assetToSend), maxAmountToSend + 1);

            mainnetController.otcSwapSend(exchange, address(assetToSend), maxAmountToSend);
            vm.stopPrank();
        }
    }

    function test_otcSwapSend_otcBufferNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcSwapSend(exchange, address(asset_12), 1e18);
    }

    function test_otcSwapSend_lastSwapNotReturned() external {
        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

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
        assertEq(sent18, 5_000_000e18);
        assertEq(claimed18, 0);

        // Try to do another one
        skip(1 seconds);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSwapSend(exchange, address(asset_12), 1e18);
    }

}

contract MainnetControllerOTCSwapSendSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcSwapSend() external {
        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Mint tokens
        deal(address(asset_12), address(almProxy), 10_000_000e12);

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
        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcClaim(exchange, address(1), 1e18);
    }

}

contract MainnetControllerOTCClaimSuccessTests is MainnetControllerOTCSwapBase {

    function _otcClaim_returnOneAsset(uint8 decimalsSend, uint8 decimalsReturn, bool recharge) internal {
        IERC20 assetToSend   = _getAssetByDecimals(decimalsSend);
        IERC20 assetToReturn = _getAssetByDecimals(decimalsReturn);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Set recharge rate
        uint256 rechargeRate;
        uint256 returnAmount;

        if (recharge) {
            // 1M normalized token per day
            rechargeRate = uint256(1_000_000e18) / 1 days;
            // The maxSlippage is 99.5%, hence we need at least 9_950_000 back. Recharge rate will
            // give us 1M, hence we need at least 8_950_000 back.
            returnAmount = 8_950_000 * 10 ** decimalsReturn;
        } else {
            rechargeRate = 0;
            // No recharge rate, we need full amount.
            returnAmount = 9_950_000 * 10 ** decimalsReturn;
        }

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, rechargeRate);

        // Mint tokens
        deal(address(assetToSend),   address(almProxy), 10e6 * 10 ** decimalsSend);
        deal(address(assetToReturn), address(exchange), returnAmount);

        // Execute OTC swap
        uint48 time_swap = uint48(block.timestamp);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(
            exchange, address(otcBuffer), address(assetToSend), 10e6 * 10 ** decimalsSend, (
                10e6 * 1e18
            )
        );
        mainnetController.otcSwapSend(
            exchange,
            address(assetToSend),
            10e6 * 10 ** decimalsSend
        );

        _otcClaim_returnOneAsset2(
            assetToReturn,
            decimalsReturn,
            returnAmount,
            recharge,
            time_swap
        );
    }

    function _otcClaim_returnOneAsset2(
        IERC20  assetToReturn,
        uint8   decimalsReturn,
        uint256 returnAmount,
        bool    recharge,
        uint48  time_swap
    ) internal {
        // Skip time by 1 day to (potentially) recharge
        if (recharge) skip(1 days);

        vm.prank(exchange);
        SafeERC20.safeTransfer(IERC20Metadata(address(assetToReturn)), address(otcBuffer), returnAmount);

        // Claim
        uint256 assetToReturnBalanceALMProxy  = assetToReturn.balanceOf(address(almProxy));
        uint256 assetToReturnBalanceOTCBuffer = assetToReturn.balanceOf(address(otcBuffer));
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(assetToReturn), returnAmount - 1, (
                (returnAmount - 1) * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(assetToReturn), returnAmount - 1);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );
        assertEq(swapTimestamp, time_swap);
        assertEq(sent18, 10e6 * 1e18);
        assertEq(claimed18, (returnAmount - 1) * 1e18 / 10 ** decimalsReturn);

        assertEq(assetToReturn.balanceOf(address(almProxy)),  assetToReturnBalanceALMProxy  + returnAmount - 1);
        assertEq(assetToReturn.balanceOf(address(otcBuffer)), assetToReturnBalanceOTCBuffer - (returnAmount - 1));
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        // There is a rounding error so we skip an additional second
        if (recharge) skip(1 seconds);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(assetToReturn), 1, (
                1 * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(assetToReturn), 1);

        (swapTimestamp, sent18, claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );
        assertEq(swapTimestamp, time_swap);
        assertEq(sent18, 10e6 * 1e18);
        assertEq(claimed18, returnAmount * 1e18 / 10 ** decimalsReturn);

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function _otcClaim_returnTwoAssets(uint8 decimalsSend, uint8 decimalsReturn, uint8 decimalsReturn2, bool recharge) internal {
        IERC20 assetToSend    = _getAssetByDecimals(decimalsSend);
        IERC20 assetToReturn  = _getAssetByDecimals(decimalsReturn);
        IERC20 assetToReturn2 = _getAssetByDecimals(decimalsReturn2);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Set recharge rate
        uint256 rechargeRate;
        uint256 returnAmount;
        uint256 returnAmount2;

        if (recharge) {
            // 1M normalized token per day
            rechargeRate = uint256(1_000_000e18) / 1 days;
            // The maxSlippage is 99.5%, hence we need at least 9_950_000 back. Recharge rate will
            // give us 1M, hence we need at least 8_950_000 back.
            returnAmount  = 4_475_000 * 10 ** decimalsReturn;
            returnAmount2 = 4_475_000 * 10 ** decimalsReturn2;
        } else {
            rechargeRate = 0;
            // No recharge rate, we need full amount.
            returnAmount  = 4_975_000 * 10 ** decimalsReturn;
            returnAmount2 = 4_975_000 * 10 ** decimalsReturn2;
        }

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, rechargeRate);

        // Mint tokens
        deal(address(assetToSend),    address(almProxy), 10e6 * 10 ** decimalsSend);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(
            exchange, address(otcBuffer), address(assetToSend), 10e6 * 10 ** decimalsSend, (
                10e6 * 1e18
            )
        );
        mainnetController.otcSwapSend(
            exchange,
            address(assetToSend),
            10e6 * 10 ** decimalsSend
        );

        _otcClaim_returnTwoAssets2(
            assetToReturn,
            assetToReturn2,
            decimalsReturn,
            decimalsReturn2,
            returnAmount,
            returnAmount2,
            recharge
        );
    }

    function _otcClaim_returnTwoAssets2(
        IERC20  assetToReturn,
        IERC20  assetToReturn2,
        uint8   decimalsReturn,
        uint8   decimalsReturn2,
        uint256 returnAmount,
        uint256 returnAmount2,
        bool    recharge
    ) internal {
        // Skip time by 1 day to (potentially) recharge
        if (recharge) skip(1 days);

        deal(address(assetToReturn),  address(exchange), returnAmount);
        vm.prank(exchange);
        SafeERC20.safeTransfer(
            IERC20Metadata(address(assetToReturn)), address(otcBuffer), returnAmount
        );

        deal(address(assetToReturn2), address(exchange), returnAmount2);
        vm.prank(exchange);
        SafeERC20.safeTransfer(
            IERC20Metadata(address(assetToReturn2)), address(otcBuffer), returnAmount2
        );

        // Claim
        uint256 assetToReturnBalanceALMProxy   = assetToReturn.balanceOf(address(almProxy));
        uint256 assetToReturnBalanceOTCBuffer  = assetToReturn.balanceOf(address(otcBuffer));

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(assetToReturn),  returnAmount - 1, (
                (returnAmount - 1) * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(assetToReturn), returnAmount - 1);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );
        assertEq(swapTimestamp, recharge ? uint48(block.timestamp - 1 days) : uint48(block.timestamp));
        assertEq(sent18, 10e6 * 1e18);
        assertEq(claimed18, (returnAmount - 1) * 1e18 / 10 ** decimalsReturn);

        assertEq(assetToReturn.balanceOf(address(almProxy)),  assetToReturnBalanceALMProxy  + returnAmount - 1);
        assertEq(assetToReturn.balanceOf(address(otcBuffer)), assetToReturnBalanceOTCBuffer - (returnAmount - 1));
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        uint256 assetToReturn2BalanceALMProxy  = assetToReturn2.balanceOf(address(almProxy));
        uint256 assetToReturn2BalanceOTCBuffer = assetToReturn2.balanceOf(address(otcBuffer));

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(assetToReturn2), returnAmount2 - 1, (
                (returnAmount2 - 1) * 1e18 / 10 ** decimalsReturn2
            )
        );
        mainnetController.otcClaim(exchange, address(assetToReturn2), returnAmount2 - 1);

        (swapTimestamp, sent18, claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );
        assertEq(swapTimestamp, recharge ? uint48(block.timestamp - 1 days) : uint48(block.timestamp));
        assertEq(sent18, 10e6 * 1e18);
        assertEq(claimed18, (
            (returnAmount - 1) * 1e18 / 10 ** decimalsReturn +
            (returnAmount2 - 1) * 1e18 / 10 ** decimalsReturn2
        ));

        assertEq(assetToReturn2.balanceOf(address(almProxy)),  assetToReturn2BalanceALMProxy  + returnAmount2 - 1);
        assertEq(assetToReturn2.balanceOf(address(otcBuffer)), assetToReturn2BalanceOTCBuffer - (returnAmount2 - 1));
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        _otcClaim_returnTwoAssets3(
            assetToReturn,
            assetToReturn2,
            decimalsReturn,
            decimalsReturn2,
            returnAmount,
            returnAmount2,
            recharge
        );
    }

    function _otcClaim_returnTwoAssets3(
        IERC20  assetToReturn,
        IERC20  assetToReturn2,
        uint8   decimalsReturn,
        uint8   decimalsReturn2,
        uint256 returnAmount,
        uint256 returnAmount2,
        bool    recharge
    ) internal {
        // There is a rounding error so we skip an additional second
        if (recharge) skip(1 seconds);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(assetToReturn), 1, (
                1 * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(assetToReturn), 1);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(assetToReturn2), 1, (
                1 * 1e18 / 10 ** decimalsReturn2
            )
        );
        mainnetController.otcClaim(exchange, address(assetToReturn2), 1);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );
        assertEq(swapTimestamp, recharge ? uint48(block.timestamp - 1 days - 1 seconds) : uint48(block.timestamp));
        assertEq(sent18, 10e6 * 1e18);
        assertEq(claimed18, (
            returnAmount * 1e18 / 10 ** decimalsReturn +
            returnAmount2 * 1e18 / 10 ** decimalsReturn2
        ));

        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function test_otcClaim() external {
        uint256 id = vm.snapshotState();
        // It is prudent to test all combinations of {6, 12, 18} decimals for all four flows:
        //  ✻ When the exchange returns a single asset /without requiring/ a recharge effect
        //  ✻ When the exchange returns a single asset /requiring/ a recharge effect
        //  ✻ When the exchange returns two assets /without requiring/ a recharge effect
        //  ✻ When the exchange returns two assets /requiring/ a recharge effect
        for (uint8 decimalsSend = 6; decimalsSend <= 18; decimalsSend += 6) {
            for (uint8 decimalsReturn = 6; decimalsReturn <= 18; decimalsReturn += 6) {
                _otcClaim_returnOneAsset(decimalsSend, decimalsReturn, false);
                vm.revertToState(id);
                _otcClaim_returnOneAsset(decimalsSend, decimalsReturn, true);

                vm.revertToState(id);
                for (uint8 decimalsReturn2 = 6; decimalsReturn2 <= 18; decimalsReturn2 += 6) {
                    _otcClaim_returnTwoAssets(decimalsSend, decimalsReturn, decimalsReturn2, false);
                    vm.revertToState(id);

                    _otcClaim_returnTwoAssets(decimalsSend, decimalsReturn, decimalsReturn2, true);
                    vm.revertToState(id);
                }
            }
        }
    }

}

contract MainnetControllerIsOTCSwapReadySuccessTests is MainnetControllerOTCSwapBase {

    function test_isOTcSwapReady_false() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(exchange, 0);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function test_isOtcSwapReady() external {
        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        // Mint tokens
        deal(address(usdt), address(almProxy), 10_000_000e6);
        deal(address(usds), address(exchange), 5_950_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(
            exchange, address(otcBuffer), address(usdt), 10_000_000e6, (
                10_000_000e18
            )
        );
        mainnetController.otcSwapSend(
            exchange,
            address(usdt),
            10_000_000e6
        );

        vm.prank(exchange);
        usds.transfer(address(otcBuffer), 5_950_000e18);

        // Claim
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(usds), 5_950_000e18);

        // Skip time by 4 days to recharge
        skip(4 days);
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        skip(1 seconds);
        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

