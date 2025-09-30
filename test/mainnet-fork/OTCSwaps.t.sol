// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { console2 } from "forge-std/console2.sol";

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

    function test_setOTCBuffer_auth() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
    }

    function test_setOTCBuffer_exchangeZero() external {
        vm.prank(Ethereum.SPARK_PROXY);
        vm.expectRevert("MainnetController/exchange-zero-address");
        mainnetController.setOTCBuffer(address(0), address(otcBuffer));
    }

    function test_setOTCBuffer_exchangeEqualsOTCBuffer() external {
        vm.prank(Ethereum.SPARK_PROXY);
        vm.expectRevert("MainnetController/exchange-equals-otcBuffer");
        mainnetController.setOTCBuffer(address(otcBuffer), address(otcBuffer));
    }

    function test_setOTCRechargeRate_auth() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            DEFAULT_ADMIN_ROLE
        ));
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);
    }

    function test_otcSwapSend_auth() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.otcSwapSend(exchange, address(1), 1e18);
    }

    function test_otcSwapSend_rateLimitedBoundary() external {
        ERC20 tokenSend = new ERC20(18);
        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(tokenSend), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        skip(1 days);
        uint256 expRateLimit = 1 days * (10_000_000e18 / 1 days);

        deal(address(tokenSend), address(almProxy), expRateLimit + 1);
        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.otcSwapSend(exchange, address(tokenSend), expRateLimit + 1);

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(tokenSend), expRateLimit, expRateLimit);
        mainnetController.otcSwapSend(exchange, address(tokenSend), expRateLimit);
    }

    function test_otcSwapSend_amountToSendZero() external {
        ERC20 tokenSend = new ERC20(18);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/amount-to-send-zero");
        mainnetController.otcSwapSend(exchange, address(tokenSend), 0);
    }

    function test_otcSwapSend_otcBufferNotSet() external {
        ERC20 tokenSend = new ERC20(18);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/otc-buffer-not-set");
        mainnetController.otcSwapSend(exchange, address(tokenSend), 1e18);
    }

    function test_otcSwapSend_lastSwapNotReturned() external {
        ERC20 tokenSend = new ERC20(18);
        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(tokenSend), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Mint tokens
        deal(address(tokenSend), address(almProxy), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(tokenSend), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(tokenSend), 10_000_000e18);

        // Try to do another one
        skip(1 seconds);
        vm.prank(relayer);
        vm.expectRevert("MainnetController/last-swap-not-returned");
        mainnetController.otcSwapSend(exchange, address(tokenSend), 1e18);
    }

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

}

contract MainnetControllerOTCSwapSuccessTests is MainnetControllerOTCSwapBase {

    function test_setOTCBuffer() external {
        vm.prank(Ethereum.SPARK_PROXY);
        vm.expectEmit(address(mainnetController));
        emit OTCBufferSet(exchange, address(otcBuffer), address(0));
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));
    }

    function test_setOTCRechargeRate() external {
        vm.prank(Ethereum.SPARK_PROXY);
        vm.expectEmit(address(mainnetController));
        emit OTCRechargeRateSet(exchange, 0, uint256(1_000_000e18) / 1 days);
        mainnetController.setOTCRechargeRate(exchange, uint256(1_000_000e18) / 1 days);
    }

    function test_otcSwapSend() external {
        ERC20 tokenSend = new ERC20(18);
        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(tokenSend), address(mainnetController), type(uint256).max);

        // Set OTC buffer
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setOTCBuffer(exchange, address(otcBuffer));

        // Mint tokens
        deal(address(tokenSend), address(almProxy), 10_000_000e18);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(exchange, address(otcBuffer), address(tokenSend), 10_000_000e18, 10_000_000e18);
        mainnetController.otcSwapSend(exchange, address(tokenSend), 10_000_000e18);

        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function _otcClaim_returnOneAsset(uint8 decimalsSend, uint8 decimalsReturn, bool recharge) internal {
        ERC20 tokenSend   = new ERC20(decimalsSend);
        ERC20 tokenReturn = new ERC20(decimalsReturn);

        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(tokenReturn), address(mainnetController), type(uint256).max);

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
        deal(address(tokenSend),   address(almProxy), 10e6 * 10 ** decimalsSend);
        deal(address(tokenReturn), address(exchange), returnAmount);

        // Execute OTC swap
        vm.prank(relayer);
        uint48 time_swap = uint48(block.timestamp);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(
            exchange, address(otcBuffer), address(tokenSend), 10e6 * 10 ** decimalsSend, (
                10e6 * 1e18
            )
        );
        mainnetController.otcSwapSend(
            exchange,
            address(tokenSend),
            10e6 * 10 ** decimalsSend
        );

        // Skip time by 1 day to (potentially) recharge
        if (recharge) skip(1 days);

        vm.prank(exchange);
        tokenReturn.transfer(address(otcBuffer), returnAmount);

        // Claim
        uint256 tokRetBalAlm = tokenReturn.balanceOf(address(almProxy));
        uint256 tokRetBalBuf = tokenReturn.balanceOf(address(otcBuffer));
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(tokenReturn), returnAmount - 1, (
                (returnAmount - 1) * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(tokenReturn), returnAmount - 1);

        // assertEq(mainnetController.otcSwapStates(exchange), OTCSwapState({
        //     swapTimestamp: time_swap,
        //     sent18: 10e6 * 10 ** 18 / 10 ** decimalsSend * 10 ** 18,
        //     claimed18: (returnAmount - 1) / 10 ** decimalsReturn * 10 ** 18
        // }));

        assertEq(tokenReturn.balanceOf(address(almProxy)),  tokRetBalAlm + returnAmount - 1);
        assertEq(tokenReturn.balanceOf(address(otcBuffer)), tokRetBalBuf - (returnAmount - 1));
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        // There is a rounding error so we skip an additional second
        if (recharge) skip(1 seconds);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(tokenReturn), 1, (
                1 * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(tokenReturn), 1);
        assertTrue(mainnetController.isOtcSwapReady(address(exchange)));
    }

    function _otcClaim_returnTwoAssets(uint8 decimalsSend, uint8 decimalsReturn, uint8 decimalsReturn2, bool recharge) internal {
        ERC20 tokenSend    = new ERC20(decimalsSend);
        ERC20 tokenReturn  = new ERC20(decimalsReturn);
        ERC20 tokenReturn2 = new ERC20(decimalsReturn2);

        // Set allowance
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(tokenReturn),  address(mainnetController), type(uint256).max);
        vm.prank(Ethereum.SPARK_PROXY);
        otcBuffer.approve(address(tokenReturn2), address(mainnetController), type(uint256).max);

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
        deal(address(tokenSend),    address(almProxy), 10e6 * 10 ** decimalsSend);
        deal(address(tokenReturn),  address(exchange), returnAmount);
        deal(address(tokenReturn2), address(exchange), returnAmount2);

        // Execute OTC swap
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCSwapSent(
            exchange, address(otcBuffer), address(tokenSend), 10e6 * 10 ** decimalsSend, (
                10e6 * 1e18
            )
        );
        mainnetController.otcSwapSend(
            exchange,
            address(tokenSend),
            10e6 * 10 ** decimalsSend
        );

        // Skip time by 1 day to (potentially) recharge
        if (recharge) skip(1 days);

        _otcClaim_returnTwoAssets2(
            tokenReturn,
            tokenReturn2,
            decimalsReturn,
            decimalsReturn2,
            returnAmount,
            returnAmount2,
            recharge
        );
    }

    function _otcClaim_returnTwoAssets2(
        ERC20   tokenReturn,
        ERC20   tokenReturn2,
        uint8   decimalsReturn,
        uint8   decimalsReturn2,
        uint256 returnAmount,
        uint256 returnAmount2,
        bool    recharge
    ) internal {
        vm.prank(exchange);
        tokenReturn.transfer(address(otcBuffer), returnAmount);

        vm.prank(exchange);
        tokenReturn2.transfer(address(otcBuffer), returnAmount2);

        // Claim
        uint256 tokRetBalAlm  = tokenReturn.balanceOf(address(almProxy));
        uint256 tokRetBalBuf  = tokenReturn.balanceOf(address(otcBuffer));
        uint256 tokRet2BalAlm = tokenReturn2.balanceOf(address(almProxy));
        uint256 tokRet2BalBuf = tokenReturn2.balanceOf(address(otcBuffer));

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(tokenReturn),  returnAmount - 1, (
                (returnAmount - 1) * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(tokenReturn), returnAmount - 1);
        assertEq(tokenReturn.balanceOf(address(almProxy)),  tokRetBalAlm + returnAmount - 1);
        assertEq(tokenReturn.balanceOf(address(otcBuffer)), tokRetBalBuf - (returnAmount - 1));
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(tokenReturn2), returnAmount2 - 1, (
                (returnAmount2 - 1) * 1e18 / 10 ** decimalsReturn2
            )
        );
        mainnetController.otcClaim(exchange, address(tokenReturn2), returnAmount2 - 1);
        assertEq(tokenReturn2.balanceOf(address(almProxy)),  tokRet2BalAlm + returnAmount2 - 1);
        assertEq(tokenReturn2.balanceOf(address(otcBuffer)), tokRet2BalBuf - (returnAmount2 - 1));
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));

        // There is a rounding error so we skip an additional second
        if (recharge) skip(1 seconds);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(tokenReturn), 1, (
                1 * 1e18 / 10 ** decimalsReturn
            )
        );
        mainnetController.otcClaim(exchange, address(tokenReturn), 1);
        vm.prank(relayer);
        vm.expectEmit(address(mainnetController));
        emit OTCClaimed(
            exchange, address(otcBuffer), address(tokenReturn2), 1, (
                1 * 1e18 / 10 ** decimalsReturn2
            )
        );
        mainnetController.otcClaim(exchange, address(tokenReturn2), 1);
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

    function test_isOtcSwapReady() external {
        vm.prank(Ethereum.SPARK_PROXY);
        mainnetController.setMaxSlippage(exchange, 0);
        assertFalse(mainnetController.isOtcSwapReady(address(exchange)));
    }

}

