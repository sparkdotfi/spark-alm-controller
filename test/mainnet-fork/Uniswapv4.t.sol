// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { console } from "../../lib/forge-std/src/console.sol";

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { PoolId }       from "../../lib/uniswap-v4-core/src/types/PoolId.sol";
import { PoolKey }      from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { FullMath }     from "../../lib/uniswap-v4-core/src/libraries/FullMath.sol";
import { TickMath }     from "../../lib/uniswap-v4-core/src/libraries/TickMath.sol";

import { IV4Router }     from "../../lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";
import { Actions }       from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { SlippageCheck } from "../../lib/uniswap-v4-periphery/src/libraries/SlippageCheck.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { UniswapV4Lib } from "../../src/libraries/UniswapV4Lib.sol";

import { MainnetController } from "../../src/MainnetController.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    // NOTE: Purposely not returning bool to avoid issues with non-conformant tokens.
    function approve(address spender, uint256 amount) external;

    function allowance(address owner, address spender) external view returns (uint256 allowance);

    function balanceOf(address owner) external view returns (uint256 balance);

}

interface IPermit2Like {

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    function allowance(
        address user,
        address token,
        address spender
    ) external view returns (uint160 allowance, uint48 expiration, uint48 nonce);

}

interface IPoolManagerLike {

    error CurrencyNotSettled();

}

interface IPositionManagerLike {

    function transferFrom(address from, address to, uint256 id) external;

    function getPoolAndPositionInfo(
        uint256 tokenId
    ) external view returns (PoolKey memory poolKey, PositionInfo info);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    function nextTokenId() external view returns (uint256 nextTokenId);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function poolKeys(bytes25 poolId) external view returns (PoolKey memory poolKeys);

}

interface IStateViewLike {

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

}

interface IUniversalRouterLike {

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;

}

contract MainnetControllerUniswapV4Tests is ForkTestBase {

    struct IncreasePositionResult {
        uint256 tokenId;
        uint256 amount0Spent;
        uint256 amount1Spent;
        uint128 liquidityIncrease;
        int24   tickLower;
        int24   tickUpper;
    }

    struct DecreasePositionResult {
        uint256 tokenId;
        uint256 amount0Received;
        uint256 amount1Received;
        uint128 liquidityDecrease;
        int24   tickLower;
        int24   tickUpper;
    }

    uint256 internal constant _V4_SWAP = 0x10;

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");

    bytes32 internal constant _DEPOSIT_LIMIT_KEY  = keccak256(abi.encode(_LIMIT_DEPOSIT,  _POOL_ID));
    bytes32 internal constant _WITHDRAW_LIMIT_KEY = keccak256(abi.encode(_LIMIT_WITHDRAW, _POOL_ID));

    address internal constant _PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address internal constant _STATE_VIEW       = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;

    // Uniswap V4 USDC/USDT pool
    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    address internal immutable _unauthorized = makeAddr("unauthorized");
    address internal immutable _user         = makeAddr("user");

    /**********************************************************************************************/
    /*** mintPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_mintPositionUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.mintPositionUniswapV4({
            poolId     : bytes32(0),
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.mintPositionUniswapV4({
            poolId     : bytes32(0),
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickLimitsNotSet() external {
        vm.prank(relayer);
        vm.expectRevert("MC/tickLimits-not-set");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTicksMisordered() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MC/ticks-misordered");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : -6,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        vm.expectRevert("MC/ticks-misordered");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : -5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : -4,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickLowerTooLow() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MC/tickLower-too-low");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -11,
            tickUpper  : -5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : -5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickUpperTooHigh() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 0, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MC/tickUpper-too-high");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 1,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickSpacingTooWide() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -10, 10, 10);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 1_000_000e6);
        deal(address(usdt), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        vm.expectRevert("MC/tickSpacing-too-wide");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 6,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -5,
            tickUpper  : 5,
            liquidity  : 1_000_000e6,
            amount0Max : 1_000_000e6,
            amount1Max : 1_000_000e6
        });
    }

    function test_mintPositionUniswapV4_revertsWhenAmount0MaxSurpassed() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(-10, 0, 1_000_000e6);

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount0Forecasted, amount0Forecasted + 1)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted,
            amount1Max : amount1Forecasted + 1  // Quote is off by 1
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max : amount1Forecasted + 1   // Quote is off by 1
        });
    }

    function test_mintPositionUniswapV4_revertsWhenAmount1MaxSurpassed() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(-10, 0, 1_000_000e6);

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount1Forecasted, amount1Forecasted + 1)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max : amount1Forecasted
        });

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max : amount1Forecasted + 1   // Quote is off by 1
        });
    }

    function test_mintPositionUniswapV4_revertsWhenRateLimitExceeded() external {
        uint256 expectedDecrease = 499.966111e18;

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease - 1, 0);
        vm.stopPrank();

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(-10, 0, 1_000_000e6);

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max : amount1Forecasted + 1   // Quote is off by 1
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max : amount1Forecasted + 1   // Quote is off by 1
        });
    }

    function test_mintPositionUniswapV4() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint256 amount0Max, uint256 amount1Max ) = _getIncreasePositionMaxAmounts(-10, 0, 1_000_000e6, 0.99e18);

        vm.record();

        IncreasePositionResult memory result = _mintPosition(-10, 0, 1_000_000e6, amount0Max, amount1Max);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Spent, 340.756158e6);
        assertEq(result.amount1Spent, 159.209953e6);
    }

    /**********************************************************************************************/
    /*** increaseLiquidity Tests                                                                ***/
    /**********************************************************************************************/

    function test_increaseLiquidityUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenPositionIsNotOwnedByProxy() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(address(almProxy));
        IPositionManagerLike(_POSITION_MANAGER).transferFrom(address(almProxy), address(1), minted.tokenId);

        vm.prank(relayer);
        vm.expectRevert("MC/non-proxy-position");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(relayer);
        vm.expectRevert("MC/tokenId-poolId-mismatch");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenAmount0MaxSurpassed() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount0Forecasted, amount0Forecasted + 1)
        );

        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted,
            amount1Max        : amount1Forecasted + 1  // Quote is off by 1
        });

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max        : amount1Forecasted + 1   // Quote is off by 1
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenAmount1MaxSurpassed() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, amount1Forecasted, amount1Forecasted + 1)
        );

        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max        : amount1Forecasted
        });

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max        : amount1Forecasted + 1   // Quote is off by 1
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenRateLimitExceeded() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        uint256 expectedDecrease = 499.966111e18;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease - 1, 0);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(minted.tickLower, minted.tickUpper, 1_000_000e6);

        deal(address(usdc), address(almProxy), amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max        : amount1Forecasted + 1   // Quote is off by 1
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : amount0Forecasted + 1,  // Quote is off by 1
            amount1Max        : amount1Forecasted + 1   // Quote is off by 1
        });
    }

    function test_increaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Max, uint256 amount1Max ) = _getIncreasePositionMaxAmounts(minted.tickLower, minted.tickUpper, 1_000_000e6, 0.99e18);

        vm.record();

        IncreasePositionResult memory result = _increasePosition(minted.tokenId, 1_000_000e6, amount0Max, amount1Max);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Spent, 340.756158e6);
        assertEq(result.amount1Spent, 159.209953e6);
    }

    /**********************************************************************************************/
    /*** decreaseLiquidityUniswapV4 Tests                                                       ***/
    /**********************************************************************************************/

    function test_decreaseLiquidityUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(relayer);
        vm.expectRevert("MC/tokenId-poolId-mismatch");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount0MinNotMet() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageCheck.MinimumAmountInsufficient.selector,
                amount0Forecasted + 1,
                amount0Forecasted
            )
        );

        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted + 1,
            amount1Min        : amount1Forecasted
        });

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount1MinNotMet() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageCheck.MinimumAmountInsufficient.selector,
                amount1Forecasted + 1,
                amount1Forecasted
            )
        );

        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted + 1
        });

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenRateLimitExceeded() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        uint256 expectedDecrease = 249.983054e18;

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, expectedDecrease - 1, 0);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, expectedDecrease, 0);

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : amount0Forecasted,
            amount1Min        : amount1Forecasted
        });
    }

    function test_decreaseLiquidityUniswapV4_partial() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Min, uint256 amount1Min ) = _getDecreasePositionMinAmounts(minted.tokenId, minted.liquidityIncrease / 2, 0.99e18);

        vm.record();

        DecreasePositionResult memory result = _decreasePosition(minted.tokenId, minted.liquidityIncrease / 2, amount0Min, amount1Min);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Received, 170.378078e6);
        assertEq(result.amount1Received, 79.604976e6);
    }

    function test_decreaseLiquidityUniswapV4_all() external {
        IncreasePositionResult memory minted = _setupLiquidity();

        vm.prank(SPARK_PROXY);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);

        ( uint256 amount0Min, uint256 amount1Min ) = _getDecreasePositionMinAmounts(minted.tokenId, minted.liquidityIncrease, 0.99e18);

        vm.record();

        DecreasePositionResult memory result = _decreasePosition(minted.tokenId, minted.liquidityIncrease, amount0Min, amount1Min);

        _assertReentrancyGuardWrittenToTwice();

        assertEq(result.amount0Received, 340.756157e6);
        assertEq(result.amount1Received, 159.209952e6);
    }

    /**********************************************************************************************/
    /*** Story Tests                                                                            ***/
    /**********************************************************************************************/

    /**
     * @dev Story 1 is a round trip of liquidity minting, increase, decreasing, and closing/burning,
     *      each 90 days apart, while an external account swaps tokens in and out of the pool.
     *      - The relayer mints a position with 1,000,000 liquidity.
     *      - The relayer increases the liquidity position by 50% (to 1,500,000 liquidity).
     *      - The relayer decreases the liquidity position by 50% (to 750,000 liquidity).
     *      - The relayer decreases the remaining liquidity position (to 0 liquidity).
     */
    function test_uniswapV4_story1() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();

        // 1. The relayer mints a position with 1,000,000 liquidity.
        IncreasePositionResult memory increaseResult = _mintPosition(-10, 0, 1_000_000e6, type(uint160).max, type(uint160).max);

        uint256 expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + _to18From6Decimals(increaseResult.amount1Spent);
        assertEq(rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 2. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 3. Some account swaps 500,000 USDT for USDC.
        _externalSwap(_user, address(usdt), 500_000e6);

        // 4. The relayer increases the liquidity position by 50%.
        increaseResult = _increasePosition(increaseResult.tokenId, 500_000e6, type(uint160).max, type(uint160).max);

        // NOTE: Rate recharged to max since 90 days elapsed.
        expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + _to18From6Decimals(increaseResult.amount1Spent);
        assertEq(rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 5. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 6. Some account swaps 750,000 USDC for USDT.
        _externalSwap(_user, address(usdc), 750_000e6);

        // 7. The relayer decreases the liquidity position by 50%.
        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 750_000e6, 0, 0);

        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + _to18From6Decimals(decreaseResult.amount1Received);
        assertEq(rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        // 8. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 9. Some account swaps 1,000,000 USDT for USDC.
        _externalSwap(_user, address(usdt), 1_000_000e6);

        // 10. The relayer decreases the remaining liquidity position.
        decreaseResult = _decreasePosition(increaseResult.tokenId, 750_000e6, 0, 0);

        // NOTE: Rate recharged to max since 90 days elapsed.
        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + _to18From6Decimals(decreaseResult.amount1Received);
        assertEq(rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), 2_000_000e18 - expectedDecrease);

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(decreaseResult.tokenId),
            0
        );
    }

    /**********************************************************************************************/
    /*** Attack Tests                                                                           ***/
    /**********************************************************************************************/

    function test_uniswapV4_logPriceAndTicks_increasingPrice() public {
        vm.skip(true);

        for (uint256 i = 0; i <= 100; ++i) {
            if (i != 0) {
                _externalSwap(_user, address(usdt), 200_000e6);
            }

            _logCurrentPriceAndTick();
            console.log(" -> After swapping: %s USDT\n", uint256(i * 200_000));
        }
    }

    function test_uniswapV4_logPriceAndTicks_decreasingPrice() public {
        vm.skip(true);

        for (uint256 i = 0; i <= 100; ++i) {
            if (i != 0) {
                _externalSwap(_user, address(usdc), 200_000e6);
            }

            _logCurrentPriceAndTick();
            console.log(" -> After swapping: %s USDC\n", uint256(i * 200_000));
        }
    }

    function test_uniswapV4_attack_baseline_priceMid() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be between the range)                  ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 840_606.192834e6);
        assertEq(increaseResult.amount1Spent, 159_209.952358e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_816.145192e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 840_606.192833e6);
        assertEq(decreaseResult.amount1Received, 159_209.952357e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_816.145190e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceMidToAbove() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdt), 19_200_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be between the range, but is above)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), 11);

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 0); // Expected 840_606.192834e6
        assertEq(increaseResult.amount1Spent, 999_950.044994e6); // Expected 159_209.952358e6
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_950.044994e6); // Expected 999_816.145192e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), 11);

        uint256 amountOut2 = _externalSwap(_user, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 19_200_305.050324e6);
        assertEq(usdc.balanceOf(_user), 0);
        assertEq(usdt.balanceOf(_user), 19_200_305.050324e6); // Gained 305 USDT.

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 819_742.888121e6); // Expected 840_606.192833e6
        assertEq(decreaseResult.amount1Received, 180_067.672764e6); // Expected 159_209.952357e6
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_810.560885e6); // Expected 999_816.145190e6, and lost 139 USD.
    }

    function test_uniswapV4_attack_priceMidToBelow() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdc), 2_500_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be between the range, but is below)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -11);

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 999_950.044994e6); // Expected 840_606.192834e6
        assertEq(increaseResult.amount1Spent, 0); // Expected 159_209.952358e6
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_950.044994e6); // Expected 999_816.145192e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -11);

        uint256 amountOut2 = _externalSwap(_user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 2_499_974.750232e6);
        assertEq(usdc.balanceOf(_user), 2_499_974.750232e6); // Lost 26 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 844_561.661143e6); // Expected 840_606.192833e6
        assertEq(decreaseResult.amount1Received, 155_258.746587e6); // Expected 159_209.952357e6
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_820.40773e6); // Expected 999_816.145190e6, and lost 129 USD.
    }

    function test_uniswapV4_attackBaseline_priceBelow() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be below the range)                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        IncreasePositionResult memory increaseResult = _mintPosition(-5, 15, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 999_700.101224e6);
        assertEq(increaseResult.amount1Spent, 0);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_700.101224e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 999_700.101223e6);
        assertEq(decreaseResult.amount1Received, 0);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_700.101223e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceBelowToMid() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdt), 18_000_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be below the range, but is between)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), 2);

        IncreasePositionResult memory increaseResult = _mintPosition(-5, 15, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 632_055.655046e6); // Expected 999_700.101224e6
        assertEq(increaseResult.amount1Spent, 367_595.789859e6); // Expected 0
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_651.444905e6); // Expected 999_700.101224e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), 2);

        uint256 amountOut2 = _externalSwap(_user, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 17_999_838.406844e6);
        assertEq(usdc.balanceOf(_user), 0);
        assertEq(usdt.balanceOf(_user), 17_999_838.406844e6); // Lost 161 USDT.

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 999_703.777704e6); // Expected 999_700.101223e6
        assertEq(decreaseResult.amount1Received, 0); // Expected 0
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_703.777704e6); // Expected 999_700.101223e6, and gained 52 USD.
    }

    function test_uniswapV4_attack_priceBelowToAbove() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdt), 19_300_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be below the range, but is above)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), 34);

        IncreasePositionResult memory increaseResult = _mintPosition(-5, 15, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 0); // Expected 999_700.101224e6
        assertEq(increaseResult.amount1Spent, 1_000_200.051255e6); // Expected 0
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 1_000_200.051255e6); // Expected 999_700.101224e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), 34);

        uint256 amountOut2 = _externalSwap(_user, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 19_300_769.578693e6);
        assertEq(usdc.balanceOf(_user), 0);
        assertEq(usdt.balanceOf(_user), 19_300_769.578693e6); // Gained 769 USDT.

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 999_710.098327e6); // Expected 999_700.101223e6
        assertEq(decreaseResult.amount1Received, 0); // Expected 0
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 999_710.098327e6); // Expected 999_700.101223e6, and lost 490 USD.
    }

    function test_uniswapV4_attackBaseline_priceAbove() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be above the range)                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        IncreasePositionResult memory increaseResult = _mintPosition(-30, -10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 0);
        assertEq(increaseResult.amount1Spent, 998_950.644702e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 998_950.644702e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0);
        assertEq(decreaseResult.amount1Received, 998_950.644701e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 998_950.644701e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceAboveToMid() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdc), 2_840_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is between)   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -20);

        IncreasePositionResult memory increaseResult = _mintPosition(-30, -10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 457_787.249555e6); // Expected 0
        assertEq(increaseResult.amount1Spent, 541_830.090075e6); // Expected 998_950.644702e6
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 999_617.339630e6); // Expected 998_950.644702e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -20);

        uint256 amountOut2 = _externalSwap(_user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 2_840_292.929030e6);
        assertEq(usdc.balanceOf(_user), 2_840_292.929030e6); // Gained 292 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -8);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0); // Expected 0
        assertEq(decreaseResult.amount1Received, 998_955.215954e6); // Expected 998_950.644701e6
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 998_955.215954e6); // Expected 998_950.644701e6, and lost 662 USD.
    }

    function test_uniswapV4_attack_priceAboveToBelow() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdc), 2_900_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -50);

        IncreasePositionResult memory increaseResult = _mintPosition(-30, -10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 1_000_950.445137e6); // Expected 0
        assertEq(increaseResult.amount1Spent, 0); // Expected 998_950.644702e6
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 1_000_950.445137e6); // Expected 998_950.644702e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -50);

        uint256 amountOut2 = _externalSwap(_user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 2_901_232.701533e6);
        assertEq(usdc.balanceOf(_user), 2_901_232.701533e6); // Gained 1_232 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -8);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0); // Expected 0
        assertEq(decreaseResult.amount1Received, 998_960.634310e6); // Expected 998_950.644701e6
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 998_960.634310e6); // Expected 998_950.644701e6, and lost 1,989 USD.
    }

    function test_uniswapV4_attack_priceAboveToBelow_defended() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Get max amounts                                                                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _getIncreasePositionMaxAmounts(-30, -10, 1_000_000_000e6, 0.99e18);

        uint256 amount0Max = (amount0Forecasted * 1e18) / 0.99e18;
        uint256 amount1Max = (amount1Forecasted * 1e18) / 0.99e18;

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        _externalSwap(_user, address(usdc), 2_900_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -50);

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Max);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Max);

        vm.prank(relayer);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageCheck.MaximumAmountExceeded.selector, 0, 1_000_950.445137e6)
        );

        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -30,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : amount0Max,
            amount1Max : amount1Max
        });
    }

    function test_uniswapV4_attackBaseline_priceAbove_wideTicks() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 200); // Allow wider tick range.
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  20_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 20_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Add Liquidity (Current price is expected to be above the range)                    ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        IncreasePositionResult memory increaseResult = _mintPosition(-200, -10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 0);
        assertEq(increaseResult.amount1Spent, 9_449_821.223798e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 9_449_821.223798e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 0);
        assertEq(decreaseResult.amount1Received, 9_449_821.223797e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 9_449_821.223797e6); // Lost 0 USD.
    }

    function test_uniswapV4_attack_priceAboveToBelow_wideTicks() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 200); // Allow wider tick spacing.
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  20_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 20_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        uint256 amountOut1 = _externalSwap(_user, address(usdc), 3_020_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -501);

        IncreasePositionResult memory increaseResult = _mintPosition(-200, -10, 1_000_000_000e6, type(uint160).max, type(uint160).max);

        assertEq(increaseResult.amount0Spent, 9_549_562.082877e6); // Expected 0
        assertEq(increaseResult.amount1Spent, 0); // Expected 9_449_821.223798e6
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 9_549_562.082877e6); // Expected 9_449_821.223798e6

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -501);

        uint256 amountOut2 = _externalSwap(_user, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 3_067_685.526025e6);
        assertEq(usdc.balanceOf(_user), 3_067_685.526025e6); // Gained 47_685 USDC.
        assertEq(usdt.balanceOf(_user), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -141);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 1_000_000_000e6, 0, 0);

        assertEq(decreaseResult.amount0Received, 6_528_153.154390e6); // Expected 0
        assertEq(decreaseResult.amount1Received, 2_970_499.394905e6); // Expected 998_950.644701e6
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 9_498_652.549295e6); // Expected 998_950.644701e6, and lost 50,909 USD.
    }

    function test_uniswapV4_attack_priceAboveToBelow_defended_wideTicks() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -200, 200, 20); // Disallow wider tick spacing.
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  20_000_000e18, 0);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 20_000_000e18, 0);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -7);

        _externalSwap(_user, address(usdc), 3_020_000e6);

        /******************************************************************************************/
        /*** Add Liquidity (Current price was expected to be above the range, but is below)     ***/
        /******************************************************************************************/

        assertEq(_getCurrentTick(), -501);

        vm.prank(relayer);
        vm.expectRevert("MC/tickSpacing-too-wide");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -200,
            tickUpper  : -10,
            liquidity  : 1_000_000_000e6,
            amount0Max : type(uint160).max,
            amount1Max : type(uint160).max
        });
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _setupLiquidity() internal returns (IncreasePositionResult memory minted) {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60, 20);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 2_000_000e18, 0);
        vm.stopPrank();

        ( uint256 amount0Max, uint256 amount1Max ) = _getIncreasePositionMaxAmounts(-10, 0, 1_000_000e6, 0.99e18);

        minted = _mintPosition(-10, 0, 1_000_000e6, amount0Max, amount1Max);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 0, 0, 0);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY, 0, 0);
        vm.stopPrank();
    }

    function _getIncreasePositionMaxAmounts(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint256 maxSlippage
    ) internal returns (uint256 amount0Max, uint256 amount1Max) {
        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            tickLower,
            tickUpper,
            liquidity
        );

        amount0Max = (amount0Forecasted * 1e18) / maxSlippage;
        amount1Max = (amount1Forecasted * 1e18) / maxSlippage;
    }

    function _mintPosition(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max
    ) internal returns (IncreasePositionResult memory result) {
        uint256 tokenIdToMint = IPositionManagerLike(_POSITION_MANAGER).nextTokenId();

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Max);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Max);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : amount0Max,
            amount1Max : amount1Max
        });

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        uint256 rateLimitAfterCall = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        result.tokenId           = tokenIdToMint;
        result.amount0Spent      = usdcBeforeCall - usdcAfterCall;
        result.amount1Spent      = usdtBeforeCall - usdtAfterCall;
        result.liquidityIncrease = liquidity;
        result.tickLower         = tickLower;
        result.tickUpper         = tickUpper;

        assertLe(result.amount0Spent, amount0Max);
        assertLe(result.amount1Spent, amount1Max);

        assertEq(rateLimitBeforeCall - rateLimitAfterCall, _to18From6Decimals(result.amount0Spent + result.amount1Spent));

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(result.tokenId), result.liquidityIncrease);

        _assertZeroAllowances(address(usdc));
        _assertZeroAllowances(address(usdt));
    }

    function _increasePosition(
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint256 amount0Max,
        uint256 amount1Max
    ) internal returns (IncreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Max);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Max);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        uint256 positionLiquidityBeforeCall = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : amount0Max,
            amount1Max        : amount1Max
        });

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        uint256 rateLimitAfterCall = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        uint256 positionLiquidityAfterCall = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        result.tokenId           = tokenId;
        result.amount0Spent      = usdcBeforeCall - usdcAfterCall;
        result.amount1Spent      = usdtBeforeCall - usdtAfterCall;
        result.liquidityIncrease = liquidityIncrease;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();

        assertLe(result.amount0Spent, amount0Max);
        assertLe(result.amount1Spent, amount1Max);

        assertEq(rateLimitBeforeCall - rateLimitAfterCall, _to18From6Decimals(result.amount0Spent + result.amount1Spent));

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(positionLiquidityAfterCall, positionLiquidityBeforeCall + result.liquidityIncrease);

        _assertZeroAllowances(address(usdc));
        _assertZeroAllowances(address(usdt));
    }

    function _getDecreasePositionMinAmounts(
        uint256 tokenId,
        uint128 liquidity,
        uint256 maxSlippage
    ) internal returns (uint256 amount0Min, uint256 amount1Min) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidity
        );

        amount0Min = (amount0Forecasted * maxSlippage) / 1e18;
        amount1Min = (amount1Forecasted * maxSlippage) / 1e18;
    }

    function _decreasePosition(
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal returns (DecreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 rateLimitBeforeCall = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        uint256 positionLiquidityBeforeCall = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : amount0Min,
            amount1Min        : amount1Min
        });

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        uint256 rateLimitAfterCall = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        uint256 positionLiquidityAfterCall = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        result.tokenId           = tokenId;
        result.amount0Received   = usdcAfterCall - usdcBeforeCall;
        result.amount1Received   = usdtAfterCall - usdtBeforeCall;
        result.liquidityDecrease = liquidityDecrease;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();

        assertGe(result.amount0Received, amount0Min);
        assertGe(result.amount1Received, amount1Min);

        assertEq(rateLimitBeforeCall - rateLimitAfterCall, _to18From6Decimals(result.amount0Received + result.amount1Received));

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(positionLiquidityAfterCall, positionLiquidityBeforeCall - result.liquidityDecrease);
    }

    function _getAmount0ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "invalid-sqrtPrices-0");

        return FullMath.mulDiv(
            uint256(liquidity) << 96,
            sqrtPriceBX96 - sqrtPriceAX96,
            uint256(sqrtPriceBX96) * sqrtPriceAX96
        );
    }

    function _getAmount1ForLiquidity(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "invalid-sqrtPrices-1");

        return FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, 1 << 96);
    }

    function _getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        require(sqrtPriceAX96 < sqrtPriceBX96, "invalid-sqrtPrices");

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            return (
                _getAmount0ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity),
                0
            );
        }

        if (sqrtPriceX96 >= sqrtPriceBX96) {
            return (
                0,
                _getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity)
            );
        }

        return (
            _getAmount0ForLiquidity(sqrtPriceX96, sqrtPriceBX96, liquidity),
            _getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceX96, liquidity)
        );
    }

    function _getPrice(uint160 sqrtPriceX96) internal view returns (uint256 price) {
        uint256 priceRoot = (uint256(sqrtPriceX96) * 1e18) >> 96;

        return (priceRoot * priceRoot) / 1e18;
    }

    function _getPrice(int24 tick) internal view returns (uint256 price) {
        return _getPrice(TickMath.getSqrtPriceAtTick(tick));
    }

    function _getCurrentTick() internal view returns (int24 tick) {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(_POOL_ID));

        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function _logCurrentPriceAndTick() internal view {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(_POOL_ID));

        uint256 price = _getPrice(sqrtPriceX96);
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        if (price < 1e1) {
            console.log("price: 0.00000000000000000%s", price);
        } else if (price < 1e2) {
            console.log("price: 0.0000000000000000%s", price);
        } else if (price < 1e3) {
            console.log("price: 0.000000000000000%s", price);
        } else if (price < 1e4) {
            console.log("price: 0.00000000000000%s", price);
        } else if (price < 1e5) {
            console.log("price: 0.0000000000000%s", price);
        } else if (price < 1e6) {
            console.log("price: 0.000000000000%s", price);
        } else if (price < 1e7) {
            console.log("price: 0.00000000000%s", price);
        } else if (price < 1e8) {
            console.log("price: 0.0000000000%s", price);
        } else if (price < 1e9) {
            console.log("price: 0.000000000%s", price);
        } else if (price < 1e10) {
            console.log("price: 0.00000000%s", price);
        } else if (price < 1e11) {
            console.log("price: 0.0000000%s", price);
        } else if (price < 1e12) {
            console.log("price: 0.000000%s", price);
        } else if (price < 1e13) {
            console.log("price: 0.00000%s", price);
        } else if (price < 1e14) {
            console.log("price: 0.0000%s", price);
        } else if (price < 1e15) {
            console.log("price: 0.000%s", price);
        } else if (price < 1e16) {
            console.log("price: 0.00%s", price);
        } else if (price < 1e17) {
            console.log("price: 0.0%s", price);
        } else {
            uint256 quotient = price / 1e18;
            uint256 remainder = price % 1e18;

            if (remainder < 1e1) {
                console.log("price: %s.00000000000000000%s", quotient, remainder);
            } else if (remainder < 1e2) {
                console.log("price: %s.0000000000000000%s", quotient, remainder);
            } else if (remainder < 1e3) {
                console.log("price: %s.000000000000000%s", quotient, remainder);
            } else if (remainder < 1e4) {
                console.log("price: %s.00000000000000%s", quotient, remainder);
            } else if (remainder < 1e5) {
                console.log("price: %s.0000000000000%s", quotient, remainder);
            } else if (remainder < 1e6) {
                console.log("price: %s.000000000000%s", quotient, remainder);
            } else if (remainder < 1e7) {
                console.log("price: %s.00000000000%s", quotient, remainder);
            } else if (remainder < 1e8) {
                console.log("price: %s.0000000000%s", quotient, remainder);
            } else if (remainder < 1e9) {
                console.log("price: %s.000000000%s", quotient, remainder);
            } else if (remainder < 1e10) {
                console.log("price: %s.00000000%s", quotient, remainder);
            } else if (remainder < 1e11) {
                console.log("price: %s.0000000%s", quotient, remainder);
            } else if (remainder < 1e12) {
                console.log("price: %s.000000%s", quotient, remainder);
            } else if (remainder < 1e13) {
                console.log("price: %s.00000%s", quotient, remainder);
            } else if (remainder < 1e14) {
                console.log("price: %s.0000%s", quotient, remainder);
            } else if (remainder < 1e15) {
                console.log("price: %s.000%s", quotient, remainder);
            } else if (remainder < 1e16) {
                console.log("price: %s.00%s", quotient, remainder);
            } else if (remainder < 1e17) {
                console.log("price: %s.0%s", quotient, remainder);
            } else {
                console.log("price: %s.%s", quotient, remainder);
            }
        }

        console.log(" -> tick: %s", tick);
    }

    function _quoteLiquidity(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidityAmount
    ) internal view returns (uint256 amount0, uint256 amount1) {
        ( uint160 sqrtPriceX96, , , ) = IStateViewLike(_STATE_VIEW).getSlot0(PoolId.wrap(_POOL_ID));

        return _getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );
    }

    function _assertZeroAllowances(address token) internal {
        ( uint160 allowance, , ) = IPermit2Like(_PERMIT2).allowance(address(almProxy), token, _POSITION_MANAGER);

        assertEq(allowance, 0, "permit2 allowance not 0");

        assertEq(IERC20Like(token).allowance(address(almProxy), _PERMIT2), 0, "allowance to permit2 not 0");
    }

    function _to18From6Decimals(uint256 amount) internal pure returns (uint256) {
        return amount * 1e12;
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23470490;  // September 29, 2025
    }

    function _externalSwap(address account, address tokenIn, uint128 amountIn) internal returns (uint256 amountOut) {
        address tokenOut = tokenIn == address(usdc) ? address(usdt) : address(usdc);

        deal(tokenIn, account, amountIn);

        bytes memory commands = abi.encodePacked(uint8(_V4_SWAP));

        bytes[] memory inputs = new bytes[](1);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey          : IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(_POOL_ID)),
                zeroForOne       : tokenIn == address(usdc),
                amountIn         : amountIn,
                amountOutMinimum : 0,
                hookData         : bytes("")
            })
        );

        params[1] = abi.encode(tokenIn, amountIn);
        params[2] = abi.encode(tokenOut, 0);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        uint256 startingOutBalance = IERC20Like(tokenOut).balanceOf(account);

        // Execute the swap
        vm.startPrank(account);
        IERC20Like(tokenIn).approve(_PERMIT2, amountIn);
        IPermit2Like(_PERMIT2).approve(tokenIn, _ROUTER, amountIn, uint48(block.timestamp));
        IUniversalRouterLike(_ROUTER).execute(commands, inputs, block.timestamp);
        vm.stopPrank();

        return IERC20Like(tokenOut).balanceOf(account) - startingOutBalance;
    }

}
