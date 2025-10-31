// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { PoolId }       from "../../lib/uniswap-v4-core/src/types/PoolId.sol";
import { PoolKey }      from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { FullMath }     from "../../lib/uniswap-v4-core/src/libraries/FullMath.sol";
import { TickMath }     from "../../lib/uniswap-v4-core/src/libraries/TickMath.sol";

import { IAccessControl } from "../../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { UniswapV4Lib } from "../../src/libraries/UniswapV4Lib.sol";

import { MainnetController } from "../../src/MainnetController.sol";

import { ForkTestBase } from "./ForkTestBase.t.sol";

interface IERC20Like {

    function allowance(address owner, address spender) external view returns (uint256 allowance);
}

interface IStateViewLike {

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

}

interface IPermit2Like {

    function allowance(
        address user,
        address token,
        address spender
    ) external view returns (uint160 allowance, uint48 expiration, uint48 nonce);
}

interface IPositionManagerLike {

    function transferFrom(address from, address to, uint256 id) external;

    function getPoolAndPositionInfo(
        uint256 tokenId
    ) external view returns (PoolKey memory poolKey, PositionInfo info);

    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);

    function nextTokenId() external view returns (uint256 nextTokenId);

    function ownerOf(uint256 tokenId) external view returns (address owner);
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

    bytes32 internal constant _LIMIT_DEPOSIT  = keccak256("LIMIT_UNISWAP_V4_DEPOSIT");
    bytes32 internal constant _LIMIT_WITHDRAW = keccak256("LIMIT_UNISWAP_V4_WITHDRAW");

    bytes32 internal constant _DEPOSIT_LIMIT_KEY  = keccak256(abi.encode(_LIMIT_DEPOSIT, _POOL_ID));
    bytes32 internal constant _WITHDRAW_LIMIT_KEY = keccak256(abi.encode(_LIMIT_WITHDRAW, _POOL_ID));

    address internal constant _PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _STATE_VIEW       = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;

    // Uniswap V4 USDC/USDT pool
    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    address internal immutable _unauthorized = makeAddr("unauthorized");

    function setUp() public virtual override  {
        super.setUp();

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** mintPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_mintPositionUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.startPrank(_unauthorized);
        mainnetController.mintPositionUniswapV4({
            poolId     : bytes32(0),
            tickLower  : 0,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
        vm.stopPrank();
    }

    function test_mintPositionUniswapV4_revertsWhenTickLowerTooLow() external {
        vm.expectRevert("MainnetController/tickLower-too-low");

        vm.startPrank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -1,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
        vm.stopPrank();
    }

    function test_mintPositionUniswapV4_revertsWhenTickUpperTooHigh() external {
        vm.expectRevert("MainnetController/tickUpper-too-high");

        vm.startPrank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 0,
            tickUpper  : 1,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
        vm.stopPrank();
    }

    function test_mintPositionUniswapV4_revertsWhenMaxSlippageNotSet() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            -10,
            0,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.expectRevert("UniswapV4Lib/maxSlippage-not-set");

        vm.startPrank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max : (amount1Forecasted * 1e18) / 0.98e18
        });
        vm.stopPrank();
    }

    function test_mintPositionUniswapV4_revertsWhenAmount0MaxTooHigh() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            -10,
            0,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.expectRevert("UniswapV4Lib/amount0Max-too-high");

        vm.startPrank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : ((amount0Forecasted + 2) * 1e18) / 0.98e18,
            amount1Max : (amount1Forecasted * 1e18) / 0.98e18
        });
        vm.stopPrank();
    }

    function test_mintPositionUniswapV4_revertsWhenAmount1MaxTooHigh() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            -10,
            0,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.expectRevert("UniswapV4Lib/amount1Max-too-high");

        vm.startPrank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max : ((amount1Forecasted + 2) * 1e18) / 0.98e18
        });
        vm.stopPrank();
    }

    function test_mintPositionUniswapV4() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        uint256 initialDepositLimit = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        IncreasePositionResult memory result = _mintPosition(-10, 0, 1_000_000e6);

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));
        assertEq(IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(result.tokenId), result.liquidityIncrease);

        _assertZeroAllowances(address(usdc));
        _assertZeroAllowances(address(usdt));

        uint256 expectedDecrease = _to18From6Decimals(result.amount0Spent) + _to18From6Decimals(result.amount1Spent);
        assertEq(initialDepositLimit - rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), expectedDecrease);
    }

    /**********************************************************************************************/
    /*** increaseLiquidity Tests                                                                ***/
    /**********************************************************************************************/

    function test_increaseLiquidityUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.startPrank(_unauthorized);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniswapV4_revertsWhenPositionIsNotOwnedByProxy() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(address(almProxy));
        IPositionManagerLike(_POSITION_MANAGER).transferFrom(address(almProxy), address(1), minted.tokenId);
        vm.stopPrank();

        vm.expectRevert("UniswapV4Lib/non-proxy-position");

        vm.startPrank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.expectRevert("UniswapV4Lib/tokenId-poolId-mismatch");

        vm.startPrank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityIncrease : 0,
            amount0Max        : 0,
            amount1Max        : 0
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniswapV4_revertsWhenMaxSlippageNotSet() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.expectRevert("UniswapV4Lib/maxSlippage-not-set");

        vm.startPrank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max        : (amount1Forecasted * 1e18) / 0.98e18
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniswapV4_revertsWhenAmount0MaxTooHigh() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.expectRevert("UniswapV4Lib/amount0Max-too-high");

        vm.startPrank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : ((amount0Forecasted + 2) * 1e18) / 0.98e18,
            amount1Max        : (amount1Forecasted * 1e18) / 0.98e18
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniswapV4_revertsWhenAmount1MaxTooHigh() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.expectRevert("UniswapV4Lib/amount1Max-too-high");

        vm.startPrank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max        : ((amount1Forecasted + 2) * 1e18) / 0.98e18
        });
        vm.stopPrank();
    }

    function test_increaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        uint256 initialDepositLimit = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        IncreasePositionResult memory result = _increasePosition(minted.tokenId, 1_000_000e6);

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(minted.tokenId), address(almProxy));

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(minted.tokenId),
            minted.liquidityIncrease + result.liquidityIncrease
        );

        _assertZeroAllowances(address(usdc));
        _assertZeroAllowances(address(usdt));

        uint256 expectedDecrease = _to18From6Decimals(result.amount0Spent) + _to18From6Decimals(result.amount1Spent);
        assertEq(initialDepositLimit - rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), expectedDecrease);
    }

    /**********************************************************************************************/
    /*** burnPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_burnPositionUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.startPrank(_unauthorized);
        mainnetController.burnPositionUniswapV4({
            poolId     : bytes32(0),
            tokenId    : 0,
            amount0Min : 0,
            amount1Min : 0
        });
        vm.stopPrank();
    }

    function test_burnPositionUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.expectRevert("UniswapV4Lib/tokenId-poolId-mismatch");

        vm.startPrank(relayer);
        mainnetController.burnPositionUniswapV4({
            poolId     : bytes32(0),
            tokenId    : minted.tokenId,
            amount0Min : 0,
            amount1Min : 0
        });
        vm.stopPrank();
    }

    function test_burnPositionUniswapV4_revertsWhenMaxSlippageNotSet() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.expectRevert("UniswapV4Lib/maxSlippage-not-set");

        vm.startPrank(relayer);
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : 0,
            amount1Min : 0
        });
        vm.stopPrank();
    }

    function test_burnPositionUniswapV4_revertsWhenAmount0MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        ( uint256 amount0Forecasted, ) = _quoteLiquidity(minted.tickLower, minted.tickUpper, minted.liquidityIncrease);

        vm.expectRevert("UniswapV4Lib/amount0Min-too-small");

        vm.startPrank(relayer);
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : (amount0Forecasted * 0.98e18) / 1e18,
            amount1Min : 0
        });
        vm.stopPrank();
    }

    function test_burnPositionUniswapV4_revertsWhenAmount1MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        (
            uint256 amount0Forecasted,
            uint256 amount1Forecasted
        ) = _quoteLiquidity(minted.tickLower, minted.tickUpper, minted.liquidityIncrease);

        vm.expectRevert("UniswapV4Lib/amount1Min-too-small");

        vm.startPrank(relayer);
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : ((amount0Forecasted + 1) * 0.98e18) / 1e18,
            amount1Min : (amount1Forecasted * 0.98e18) / 1e18
        });
        vm.stopPrank();
    }

    function test_burnPositionUniswapV4() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        uint256 initialWithdrawLimit = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        DecreasePositionResult memory result = _burnPosition(minted.tokenId);

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(minted.tokenId),
            0
        );

        uint256 expectedDecrease = _to18From6Decimals(result.amount0Received) + _to18From6Decimals(result.amount1Received);
        assertEq(initialWithdrawLimit - rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), expectedDecrease);
    }

    /**********************************************************************************************/
    /*** decreaseLiquidityUniswapV4 Tests                                                       ***/
    /**********************************************************************************************/

    function test_decreaseLiquidityUniswapV4_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.RELAYER()
            )
        );

        vm.startPrank(_unauthorized);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : 0,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
        vm.stopPrank();
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.expectRevert("UniswapV4Lib/tokenId-poolId-mismatch");

        vm.startPrank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : bytes32(0),
            tokenId           : minted.tokenId,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
        vm.stopPrank();
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenMaxSlippageNotSet() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.expectRevert("UniswapV4Lib/maxSlippage-not-set");

        vm.startPrank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
        vm.stopPrank();
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount0MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        ( uint256 amount0Forecasted, ) = _quoteLiquidity(minted.tickLower, minted.tickUpper, minted.liquidityIncrease / 2);

        vm.expectRevert("UniswapV4Lib/amount0Min-too-small");

        vm.startPrank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : (amount0Forecasted * 0.98e18) / 1e18,
            amount1Min        : 0
        });
        vm.stopPrank();
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount1MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        (
            uint256 amount0Forecasted,
            uint256 amount1Forecasted
        ) = _quoteLiquidity(minted.tickLower, minted.tickUpper, minted.liquidityIncrease / 2);

        vm.expectRevert("UniswapV4Lib/amount1Min-too-small");

        vm.startPrank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : ((amount0Forecasted + 1) * 0.98e18) / 1e18,
            amount1Min        : (amount1Forecasted * 0.98e18) / 1e18
        });
        vm.stopPrank();
    }

    function test_decreaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        vm.stopPrank();

        uint256 initialWithdrawLimit = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        DecreasePositionResult memory result = _decreasePosition(minted.tokenId, minted.liquidityIncrease / 2);

        assertEq(IPositionManagerLike(_POSITION_MANAGER).ownerOf(result.tokenId), address(almProxy));

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(result.tokenId),
            minted.liquidityIncrease - result.liquidityDecrease
        );

        uint256 expectedDecrease = _to18From6Decimals(result.amount0Received) + _to18From6Decimals(result.amount1Received);
        assertEq(initialWithdrawLimit - rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), expectedDecrease);
    }

    /**********************************************************************************************/
    /*** setUniswapV4TickLimits Tests                                                           ***/
    /**********************************************************************************************/

    function test_setUniswapV4tickLimits_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.startPrank(_unauthorized);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0);
        vm.stopPrank();
    }

    function test_setUniswapV4tickLimits_revertsWhenInvalidTicks() external {
        vm.expectRevert("MainnetController/invalid-ticks");

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 1, 0);
        vm.stopPrank();
    }

    function test_setUniswapV4tickLimits() external {
        vm.expectEmit(address(mainnetController));
        emit MainnetController.UniswapV4TickLimitsSet(_POOL_ID, -60, 60);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        ( int24 tickLowerMin, int24 tickUpperMax ) = mainnetController.uniswapV4Limits(_POOL_ID);

        assertEq(tickLowerMin, -60);
        assertEq(tickUpperMax, 60);
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _setupForLiquidityIncrease() internal returns (IncreasePositionResult memory minted) {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        minted = _mintPosition(-10, 0, 1_000_000e6);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 0, 0);
        vm.stopPrank();
    }

    function _mintPosition(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity
    ) internal returns (IncreasePositionResult memory result) {
        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            tickLower,
            tickUpper,
            liquidity
        );

        uint256 tokenIdToMint = IPositionManagerLike(_POSITION_MANAGER).nextTokenId();

        uint256 usdcStarting = usdc.balanceOf(address(almProxy));
        uint256 usdtStarting = usdt.balanceOf(address(almProxy));

        deal(address(usdc), address(almProxy), usdcStarting + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdtStarting + amount1Forecasted + 1);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 maxSlippage = mainnetController.maxSlippages(address(uint160(uint256(_POOL_ID))));

        vm.startPrank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : (amount0Forecasted * 1e18) / maxSlippage,
            amount1Max : (amount1Forecasted * 1e18) / maxSlippage
        });
        vm.stopPrank();

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        result.tokenId           = tokenIdToMint;
        result.amount0Spent      = usdcBeforeCall - usdcAfterCall;
        result.amount1Spent      = usdtBeforeCall - usdtAfterCall;
        result.liquidityIncrease = liquidity;
        result.tickLower         = tickLower;
        result.tickUpper         = tickUpper;
    }

    function _increasePosition(
        uint256 tokenId,
        uint128 liquidityIncrease
    ) internal returns (IncreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidityIncrease
        );

        uint256 usdcStarting = usdc.balanceOf(address(almProxy));
        uint256 usdtStarting = usdt.balanceOf(address(almProxy));

        deal(address(usdc), address(almProxy), usdcStarting + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdtStarting + amount1Forecasted + 1);

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 maxSlippage = mainnetController.maxSlippages(address(uint160(uint256(_POOL_ID))));

        vm.startPrank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : (amount0Forecasted * 1e18) / maxSlippage,
            amount1Max        : (amount1Forecasted * 1e18) / maxSlippage
        });
        vm.stopPrank();

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        result.tokenId           = tokenId;
        result.amount0Spent      = usdcBeforeCall - usdcAfterCall;
        result.amount1Spent      = usdtBeforeCall - usdtAfterCall;
        result.liquidityIncrease = liquidityIncrease;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();
    }

    function _burnPosition(
        uint256 tokenId
    ) internal returns (DecreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        uint128 liquidity = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidity
        );

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 maxSlippage = mainnetController.maxSlippages(address(uint160(uint256(_POOL_ID))));

        vm.startPrank(relayer);
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : tokenId,
            amount0Min : ((amount0Forecasted + 1) * maxSlippage) / 1e18,
            amount1Min : ((amount1Forecasted + 1) * maxSlippage) / 1e18
        });
        vm.stopPrank();

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        result.tokenId           = tokenId;
        result.amount0Received   = usdcAfterCall - usdcBeforeCall;
        result.amount1Received   = usdtAfterCall - usdtBeforeCall;
        result.liquidityDecrease = liquidity;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();
    }

    function _decreasePosition(
        uint256 tokenId,
        uint128 liquidityDecrease
    ) internal returns (DecreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        (uint256 amount0Forecasted, uint256 amount1Forecasted) = _quoteLiquidity(
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidityDecrease
        );

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        uint256 maxSlippage = mainnetController.maxSlippages(address(uint160(uint256(_POOL_ID))));

        vm.startPrank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : ((amount0Forecasted + 1) * maxSlippage) / 1e18,
            amount1Min        : ((amount1Forecasted + 1) * maxSlippage) / 1e18
        });
        vm.stopPrank();

        uint256 usdcAfterCall = usdc.balanceOf(address(almProxy));
        uint256 usdtAfterCall = usdt.balanceOf(address(almProxy));

        result.tokenId           = tokenId;
        result.amount0Received   = usdcAfterCall - usdcBeforeCall;
        result.amount1Received   = usdtAfterCall - usdtBeforeCall;
        result.liquidityDecrease = liquidityDecrease;
        result.tickLower         = positionInfo.tickLower();
        result.tickUpper         = positionInfo.tickUpper();
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

    function _quoteLiquidity(
        int24 tickLower,
        int24 tickUpper,
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

        assertEq(allowance, 0, "permit2 usdc allowance");

        assertEq(IERC20Like(token).allowance(address(almProxy), _PERMIT2), 0, "token usdc allowance");
    }

    function _to18From6Decimals(uint256 amount) internal pure returns (uint256) {
        return amount * 1e12;
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23470490;  // September 29, 2025
    }

}
