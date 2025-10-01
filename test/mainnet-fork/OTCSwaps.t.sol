// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

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

        // Allowance cannot be set now because different assets will be used, so it will have to be
        // done separately in each test.

        // 2. Set rate limits
        // We can do that because it doesn't depend on the asset
        key = RateLimitHelpers.makeAssetKey(
            LIMIT_OTC_SWAP,
            exchange
        );
        vm.prank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(key, 10_000_000e18, uint256(10_000_000e18) / 1 days);

        // 3. Set maxSlippages
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(exchange, 1e18 - 0.005e18); // 100% - 0.5% == 99.5%
    }
}

contract MainnetControllerOTCSwapFailureTests is MainnetControllerOTCSwapBase {

    function test_otcSwapSend_auth() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcSwapSend(exchange, address(1), 1e18);
    }

    function test_otcSwapSend_rateLimitedBoundary() external {
        ERC20 assetToSend = new ERC20(18);
        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToSend), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        skip(1 days);
        uint256 expRateLimit = 1 days * (10_000_000e18 / 1 days);

        deal(address(assetToSend), address(almProxy), expRateLimit + 1);
        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.otcSwapSend(exchange, address(assetToSend), expRateLimit + 1);

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(assetToSend), expRateLimit, expRateLimit);
        mainnetController.otcSwapSend(exchange, address(assetToSend), expRateLimit);
    }

    function test_otcSwapSend_amountToSendZero() external {
        ERC20 assetToSend = new ERC20(18);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/amount-to-send-zero");
        mainnetController.otcSwapSend(exchange, address(assetToSend), 0);
    }

    function test_otcSwapSend_otcBufferNotSet() external {
        ERC20 assetToSend = new ERC20(18);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcSwapSend(exchange, address(assetToSend), 1e18);
    }

    function test_otcSwapSend_lastSwapNotReturned() external {
        ERC20 assetToSend = new ERC20(18);
        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToSend), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Mint tokens
        deal(address(assetToSend), address(almProxy), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(assetToSend), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(assetToSend), 10_000_000e18);

        // Try to do another one
        skip(1 seconds);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSwapSend(exchange, address(assetToSend), 1e18);
    }

}

contract MainnetControllerOTCSwapSendSuccessTests is MainnetControllerOTCSwapBase {

    function test_otcSwapSend() external {
        ERC20 assetToSend = new ERC20(18);
        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToSend), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Mint tokens
        deal(address(assetToSend), address(almProxy), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(assetToSend), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(assetToSend), 10_000_000e18);

        (uint256 swapTimestamp, uint256 sent18, uint256 claimed18) = (
            mainnetController.otcSwapStates(exchange)
        );

        assertEq(swapTimestamp, uint48(block.timestamp));
        assertEq(sent18, 10_000_000e18);
        assertEq(claimed18, 0);

        assertEq(assetToSend.balanceOf(address(almProxy)), 0);
        assertEq(assetToSend.balanceOf(address(exchange)), 10_000_000e18);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

contract MainnetControllerOTCClaimFailureTests is MainnetControllerOTCSwapBase {

    function test_otcClaim_auth() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcClaim(exchange, address(1), 1e18);
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

    function test_otcClaim_assetZero() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        vm.prank(relayer);
        vm.expectRevert("call to non-contract address 0x0000000000000000000000000000000000000000");
        mainnetController.otcClaim(exchange, address(0), 1e18);
    }

}

contract MainnetControllerOTCClaimSuccessTests is MainnetControllerOTCSwapBase {

    function _otcClaim_returnOneAsset(uint8 decimalsSend, uint8 decimalsReturn, bool recharge) internal {
        ERC20 assetToSend   = new ERC20(decimalsSend);
        ERC20 assetToReturn = new ERC20(decimalsReturn);

        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToReturn), address(mainnetController), type(uint256).max);

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
        vm.prank(relayer);
        uint48 time_swap = uint48(block.timestamp);
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
        ERC20   assetToReturn,
        uint8   decimalsReturn,
        uint256 returnAmount,
        bool    recharge,
        uint48  time_swap
    ) internal {
        // Skip time by 1 day to (potentially) recharge
        if (recharge) skip(1 days);

        vm.prank(exchange);
        assetToReturn.transfer(address(otcBuffer), returnAmount);

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
        ERC20 assetToSend    = new ERC20(decimalsSend);
        ERC20 assetToReturn  = new ERC20(decimalsReturn);
        ERC20 assetToReturn2 = new ERC20(decimalsReturn2);

        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToReturn),  address(mainnetController), type(uint256).max);
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToReturn2), address(mainnetController), type(uint256).max);

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
        deal(address(assetToReturn),  address(exchange), returnAmount);
        deal(address(assetToReturn2), address(exchange), returnAmount2);

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
        ERC20   assetToReturn,
        ERC20   assetToReturn2,
        uint8   decimalsReturn,
        uint8   decimalsReturn2,
        uint256 returnAmount,
        uint256 returnAmount2,
        bool    recharge
    ) internal {
        // Skip time by 1 day to (potentially) recharge
        if (recharge) skip(1 days);

        vm.prank(exchange);
        assetToReturn.transfer(address(otcBuffer), returnAmount);

        vm.prank(exchange);
        assetToReturn2.transfer(address(otcBuffer), returnAmount2);

        // Claim
        uint256 assetToReturnBalanceALMProxy  = assetToReturn.balanceOf(address(almProxy));
        uint256 assetToReturnBalanceOTCBuffer = assetToReturn.balanceOf(address(otcBuffer));
        uint256 tokRet2BalAlm = assetToReturn2.balanceOf(address(almProxy));
        uint256 tokRet2BalBuf = assetToReturn2.balanceOf(address(otcBuffer));

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

        assertEq(assetToReturn2.balanceOf(address(almProxy)),  tokRet2BalAlm + returnAmount2 - 1);
        assertEq(assetToReturn2.balanceOf(address(otcBuffer)), tokRet2BalBuf - (returnAmount2 - 1));
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
        ERC20   assetToReturn,
        ERC20   assetToReturn2,
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
        // Try {6, 12, 18}³:
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
        ERC20 assetToSend   = new ERC20(6);
        ERC20 assetToReturn = new ERC20(12);

        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(assetToReturn), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));


        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);

        // Mint tokens
        deal(address(assetToSend),   address(almProxy), 10_000_000e6);
        deal(address(assetToReturn), address(exchange), 5_950_000e12);

        // Execute OTC swap
        vm.prank(relayer);
        uint48 time_swap = uint48(block.timestamp);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(
            exchange, address(otcBuffer), address(assetToSend), 10_000_000e6, (
                10_000_000e18
            )
        );
        mainnetController.otcSwapSend(
            exchange,
            address(assetToSend),
            10_000_000e6
        );

        vm.prank(exchange);
        assetToReturn.transfer(address(otcBuffer), 5_950_000e12);

        // Claim
        vm.prank(relayer);
        mainnetController.otcClaim(exchange, address(assetToReturn), 5_950_000e12);

        // Skip time by 4 days to recharge
        skip(4 days);
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        skip(1 seconds);
        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

