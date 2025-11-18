// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ReentrancyGuard } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import { PoolId }       from "../../lib/uniswap-v4-core/src/types/PoolId.sol";
import { PoolKey }      from "../../lib/uniswap-v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../lib/uniswap-v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { FullMath }     from "../../lib/uniswap-v4-core/src/libraries/FullMath.sol";
import { TickMath }     from "../../lib/uniswap-v4-core/src/libraries/TickMath.sol";

import { Actions }   from "../../lib/uniswap-v4-periphery/src/libraries/Actions.sol";
import { IV4Router } from "../../lib/uniswap-v4-periphery/src/interfaces/IV4Router.sol";

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

interface IStateViewLike {

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);

}

interface IPermit2Like {

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    function allowance(
        address user,
        address token,
        address spender
    ) external view returns (uint160 allowance, uint48 expiration, uint48 nonce);
}

interface IUniversalRouterLike {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external;
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

    bytes32 internal constant _DEPOSIT_LIMIT_KEY  = keccak256(abi.encode(_LIMIT_DEPOSIT, _POOL_ID));
    bytes32 internal constant _WITHDRAW_LIMIT_KEY = keccak256(abi.encode(_LIMIT_WITHDRAW, _POOL_ID));

    address internal constant _PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant _POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    address internal constant _ROUTER           = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address internal constant _STATE_VIEW       = 0x7fFE42C4a5DEeA5b0feC41C94C136Cf115597227;

    // Uniswap V4 USDC/USDT pool
    bytes32 internal constant _POOL_ID = 0x8aa4e11cbdf30eedc92100f4c8a31ff748e201d44712cc8c90d189edaa8e4e47;

    address internal immutable _alice = makeAddr("alice");
    address internal immutable _unauthorized = makeAddr("unauthorized");

    function setUp() public virtual override  {
        super.setUp();

        vm.startPrank(SPARK_PROXY);
        rateLimits.setRateLimitData(_DEPOSIT_LIMIT_KEY,  2_000_000e18, uint256(2_000_000e18) / 1 days);
        rateLimits.setRateLimitData(_WITHDRAW_LIMIT_KEY, 2_000_000e18, uint256(2_000_000e18) / 1 days);
        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** Attack Tests                                                                           ***/
    /**********************************************************************************************/

    function test_uniswap_attack_version1() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        uint256 amountOut1 = _swap(relayer, address(usdt), 1_000_000e6);

        /******************************************************************************************/
        /*** Add Liquidity                                                                      ***/
        /******************************************************************************************/

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 0, 1_000_000_000e6, 0.99e18);

        assertEq(increaseResult.amount0Spent, 315_284.384200e6);
        assertEq(increaseResult.amount1Spent, 184_665.023706e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 499_949.407906e6);

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        uint256 amountOut2 = _swap(relayer, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 999_980.632416e6);
        assertEq(usdc.balanceOf(relayer), 0);
        assertEq(usdt.balanceOf(relayer), 999_980.632416e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        DecreasePositionResult memory decreaseResult = _burnPosition(increaseResult.tokenId, 0.99e18);

        assertEq(decreaseResult.amount0Received, 340_123.860866e6);
        assertEq(decreaseResult.amount1Received, 159_842.067259e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 499_965.928125e6); // Gained 16 USD.
    }

    function test_uniswap_attack_version2() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        uint256 amountOut1 = _swap(relayer, address(usdt), 10_000_000e6);

        /******************************************************************************************/
        /*** Add Liquidity                                                                      ***/
        /******************************************************************************************/

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 0, 1_000_000_000e6, 0.99e18);

        assertEq(increaseResult.amount0Spent, 110_062.448258e6);
        assertEq(increaseResult.amount1Spent, 389_799.699146e6);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 499_862.147404e6);

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        uint256 amountOut2 = _swap(relayer, address(usdc), uint128(amountOut1));

        assertEq(amountOut2, 9_999_851.879880e6);
        assertEq(usdc.balanceOf(relayer), 0);
        assertEq(usdt.balanceOf(relayer), 9_999_851.879880e6);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        DecreasePositionResult memory decreaseResult = _burnPosition(increaseResult.tokenId, 0.99e18);

        assertEq(decreaseResult.amount0Received, 335_029.313235e6);
        assertEq(decreaseResult.amount1Received, 164_935.176966e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 499_964.490201e6); // Gained 102 USD.
    }

    function test_uniswap_attack_version4() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        uint256 amountOut1 = _swap(relayer, address(usdc), 10_000_000e6);

        /******************************************************************************************/
        /*** Add Liquidity                                                                      ***/
        /******************************************************************************************/

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 0, 1_000_000_000e6, 0.99e18);

        assertEq(increaseResult.amount0Spent, 500_100.010001e6);
        assertEq(increaseResult.amount1Spent, 0);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 500_100.010001e6);

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        uint256 amountOut2 = _swap(relayer, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 9_999_889.989431e6);
        assertEq(usdc.balanceOf(relayer), 9_999_889.989431e6);
        assertEq(usdt.balanceOf(relayer), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        DecreasePositionResult memory decreaseResult = _burnPosition(increaseResult.tokenId, 0.99e18);

        assertEq(decreaseResult.amount0Received, 344_711.868438e6);
        assertEq(decreaseResult.amount1Received, 155_258.504464e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 499_970.372902e6); // Gained 129 USD.
    }

    function test_uniswap_attack_version5() public {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        /******************************************************************************************/
        /*** Frontrun                                                                           ***/
        /******************************************************************************************/

        uint256 amountOut1 = _swap(relayer, address(usdc), 100_000_000e6);

        /******************************************************************************************/
        /*** Add Liquidity                                                                      ***/
        /******************************************************************************************/

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 0, 1_000_000_000e6, 0.99e18);

        assertEq(increaseResult.amount0Spent, 500_100.010001e6);
        assertEq(increaseResult.amount1Spent, 0);
        assertEq(increaseResult.amount1Spent + increaseResult.amount0Spent, 500_100.010001e6);

        /******************************************************************************************/
        /*** Backrun                                                                            ***/
        /******************************************************************************************/

        uint256 amountOut2 = _swap(relayer, address(usdt), uint128(amountOut1));

        assertEq(amountOut2, 99_998_989.675954e6);
        assertEq(usdc.balanceOf(relayer), 99_998_989.675954e6);
        assertEq(usdt.balanceOf(relayer), 0);

        /******************************************************************************************/
        /*** Remove Liquidity                                                                   ***/
        /******************************************************************************************/

        DecreasePositionResult memory decreaseResult = _burnPosition(increaseResult.tokenId, 0.99e18);

        assertEq(decreaseResult.amount0Received, 344_711.876212e6);
        assertEq(decreaseResult.amount1Received, 155_258.496696e6);
        assertEq(decreaseResult.amount0Received + decreaseResult.amount1Received, 499_970.372907e6); // Gained 129 USD.
    }

    /**********************************************************************************************/
    /*** mintPositionUniswapV4 Tests                                                            ***/
    /**********************************************************************************************/

    function test_mintPositionUniswapV4_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
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

    function test_mintPositionUniswapV4_revertsWhenTickLowerTooLow() external {
        vm.prank(relayer);
        vm.expectRevert("MC/tickLower-too-low");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -1,
            tickUpper  : 0,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsWhenTickUpperTooHigh() external {
        vm.prank(relayer);
        vm.expectRevert("MC/tickUpper-too-high");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : 0,
            tickUpper  : 1,
            liquidity  : 0,
            amount0Max : 0,
            amount1Max : 0
        });
    }

    function test_mintPositionUniswapV4_revertsWhenMaxSlippageNotSet() external {
        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            -10,
            0,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("MC/maxSlippage-not-set");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max : (amount1Forecasted * 1e18) / 0.98e18
        });
    }

    function test_mintPositionUniswapV4_revertsWhenAmount0MaxTooHigh() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            -10,
            0,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("MC/amount0Max-too-high");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : ((amount0Forecasted + 2) * 1e18) / 0.98e18,
            amount1Max : (amount1Forecasted * 1e18) / 0.98e18
        });
    }

    function test_mintPositionUniswapV4_revertsWhenAmount1MaxTooHigh() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            -10,
            0,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("MC/amount1Max-too-high");
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : -10,
            tickUpper  : 0,
            liquidity  : 1_000_000e6,
            amount0Max : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max : ((amount1Forecasted + 2) * 1e18) / 0.98e18
        });
    }

    function test_mintPositionUniswapV4() external {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        uint256 initialDepositLimit = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        IncreasePositionResult memory result = _mintPosition(-10, 0, 1_000_000e6, 0.99e18);

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
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

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
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

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

    function test_increaseLiquidityUniswapV4_revertsWhenMaxSlippageNotSet() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("MC/maxSlippage-not-set");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max        : (amount1Forecasted * 1e18) / 0.98e18
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenAmount0MaxTooHigh() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("MC/amount0Max-too-high");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : ((amount0Forecasted + 2) * 1e18) / 0.98e18,
            amount1Max        : (amount1Forecasted * 1e18) / 0.98e18
        });
    }

    function test_increaseLiquidityUniswapV4_revertsWhenAmount1MaxTooHigh() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            1_000_000e6
        );

        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount0Forecasted + 1);
        deal(address(usdt), address(almProxy), usdt.balanceOf(address(almProxy)) + amount1Forecasted + 1);

        vm.prank(relayer);
        vm.expectRevert("MC/amount1Max-too-high");
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityIncrease : 1_000_000e6,
            amount0Max        : (amount0Forecasted * 1e18) / 0.98e18,
            amount1Max        : ((amount1Forecasted + 2) * 1e18) / 0.98e18
        });
    }

    function test_increaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        uint256 initialDepositLimit = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        IncreasePositionResult memory result = _increasePosition(minted.tokenId, 1_000_000e6, 0.99e18);

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

        vm.prank(_unauthorized);
        mainnetController.burnPositionUniswapV4({
            poolId     : bytes32(0),
            tokenId    : 0,
            amount0Min : 0,
            amount1Min : 0
        });
    }

    function test_burnPositionUniswapV4_revertsWhenTokenIsNotForPool() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(relayer);
        vm.expectRevert("MC/tokenId-poolId-mismatch");
        mainnetController.burnPositionUniswapV4({
            poolId     : bytes32(0),
            tokenId    : minted.tokenId,
            amount0Min : 0,
            amount1Min : 0
        });
    }

    function test_burnPositionUniswapV4_revertsWhenMaxSlippageNotSet() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(relayer);
        vm.expectRevert("MC/maxSlippage-not-set");
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : 0,
            amount1Min : 0
        });
    }

    function test_burnPositionUniswapV4_revertsWhenAmount0MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        ( uint256 amount0Forecasted, ) = _quoteLiquidity(minted.tickLower, minted.tickUpper, minted.liquidityIncrease);

        vm.prank(relayer);
        vm.expectRevert("MC/amount0Min-too-small");
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : (amount0Forecasted * 0.98e18) / 1e18,
            amount1Min : 0
        });
    }

    function test_burnPositionUniswapV4_revertsWhenAmount1MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease
        );

        vm.prank(relayer);
        vm.expectRevert("MC/amount1Min-too-small");
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : minted.tokenId,
            amount0Min : ((amount0Forecasted + 1) * 0.98e18) / 1e18,
            amount1Min : (amount1Forecasted * 0.98e18) / 1e18
        });
    }

    function test_burnPositionUniswapV4() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        uint256 initialWithdrawLimit = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        DecreasePositionResult memory result = _burnPosition(minted.tokenId, 0.99e18);

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
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

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

    function test_decreaseLiquidityUniswapV4_revertsWhenMaxSlippageNotSet() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(relayer);
        vm.expectRevert("MC/maxSlippage-not-set");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : 0,
            amount0Min        : 0,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount0MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        ( uint256 amount0Forecasted, ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);
        vm.expectRevert("MC/amount0Min-too-small");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : (amount0Forecasted * 0.98e18) / 1e18,
            amount1Min        : 0
        });
    }

    function test_decreaseLiquidityUniswapV4_revertsWhenAmount1MinTooSmall() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            minted.tickLower,
            minted.tickUpper,
            minted.liquidityIncrease / 2
        );

        vm.prank(relayer);
        vm.expectRevert("MC/amount1Min-too-small");
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : minted.tokenId,
            liquidityDecrease : minted.liquidityIncrease / 2,
            amount0Min        : ((amount0Forecasted + 1) * 0.98e18) / 1e18,
            amount1Min        : (amount1Forecasted * 0.98e18) / 1e18
        });
    }

    function test_decreaseLiquidityUniswapV4() external {
        IncreasePositionResult memory minted = _setupForLiquidityIncrease();

        vm.prank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);

        uint256 initialWithdrawLimit = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        DecreasePositionResult memory result = _decreasePosition(minted.tokenId, minted.liquidityIncrease / 2, 0.99e18);

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

    function test_setUniswapV4tickLimits_reentrancy() external {
        _setControllerEntered();
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0);
    }

    function test_setUniswapV4tickLimits_revertsForNonRelayer() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                _unauthorized,
                mainnetController.DEFAULT_ADMIN_ROLE()
            )
        );

        vm.prank(_unauthorized);
        mainnetController.setUniswapV4TickLimits(bytes32(0), 0, 0);
    }

    function test_setUniswapV4tickLimits_revertsWhenInvalidTicks() external {
        vm.prank(SPARK_PROXY);
        vm.expectRevert("MC/invalid-ticks");
        mainnetController.setUniswapV4TickLimits(bytes32(0), 1, 0);
    }

    function test_setUniswapV4tickLimits() external {
        vm.expectEmit(address(mainnetController));
        emit MainnetController.UniswapV4TickLimitsSet(_POOL_ID, -60, 60);

        vm.prank(SPARK_PROXY);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);

        ( int24 tickLowerMin, int24 tickUpperMax ) = mainnetController.uniswapV4Limits(_POOL_ID);

        assertEq(tickLowerMin, -60);
        assertEq(tickUpperMax, 60);
    }

    /**********************************************************************************************/
    /*** Story Tests                                                                            ***/
    /**********************************************************************************************/

    function test_uniswapV4_story1() external {
        // Setup the pool and the controller.
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        // 1. The user mints a position with 1,000,000 liquidity.
        uint256 initialDepositLimit = rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY);

        IncreasePositionResult memory increaseResult = _mintPosition(-10, 0, 1_000_000e6, 0.99e18);

        uint256 expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + _to18From6Decimals(increaseResult.amount1Spent);
        assertEq(initialDepositLimit - rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), expectedDecrease);

        // 2. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 3. Some user swaps 500,000 USDT for USDC.
        _swap(_alice, address(usdt), 500_000e6);

        // 4. The user increases the liquidity position by 50%.
        increaseResult = _increasePosition(increaseResult.tokenId, 500_000e6, 0.99e18);

        expectedDecrease = _to18From6Decimals(increaseResult.amount0Spent) + _to18From6Decimals(increaseResult.amount1Spent);
        assertEq(initialDepositLimit - rateLimits.getCurrentRateLimit(_DEPOSIT_LIMIT_KEY), expectedDecrease);

        return;

        // 5. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 6. Some user swaps 750,000 USDC for USDT.
        _swap(_alice, address(usdc), 750_000e6);

        // 7. The user decreases the liquidity position by 50%.
        uint256 initialWithdrawLimit = rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY);

        DecreasePositionResult memory decreaseResult = _decreasePosition(increaseResult.tokenId, 750_000e6, 0.99e18);

        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + _to18From6Decimals(decreaseResult.amount1Received);
        assertEq(initialWithdrawLimit - rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), expectedDecrease);

        // 8. 90 days elapse.
        vm.warp(block.timestamp + 90 days);

        // 9. Some user swaps 1,000,000 USDT for USDC.
        _swap(_alice, address(usdt), 1_000_000e6);

        // 7. The user burns the remaining liquidity position.
        decreaseResult = _burnPosition(increaseResult.tokenId, 0.99e18);

        expectedDecrease = _to18From6Decimals(decreaseResult.amount0Received) + _to18From6Decimals(decreaseResult.amount1Received);
        assertEq(initialWithdrawLimit - rateLimits.getCurrentRateLimit(_WITHDRAW_LIMIT_KEY), expectedDecrease);

        assertEq(
            IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(decreaseResult.tokenId),
            0
        );
    }

    /**********************************************************************************************/
    /*** Helper Functions                                                                       ***/
    /**********************************************************************************************/

    function _setupForLiquidityIncrease() internal returns (IncreasePositionResult memory minted) {
        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0.98e18);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, -60, 60);
        vm.stopPrank();

        minted = _mintPosition(-10, 0, 1_000_000e6, 0.99e18);

        vm.startPrank(SPARK_PROXY);
        mainnetController.setMaxSlippage(address(uint160(uint256(_POOL_ID))), 0);
        mainnetController.setUniswapV4TickLimits(_POOL_ID, 0, 0);
        vm.stopPrank();
    }

    function _mintPosition(
        int24   tickLower,
        int24   tickUpper,
        uint128 liquidity,
        uint256 maxSlippage
    ) internal returns (IncreasePositionResult memory result) {
        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
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

        vm.prank(relayer);
        mainnetController.mintPositionUniswapV4({
            poolId     : _POOL_ID,
            tickLower  : tickLower,
            tickUpper  : tickUpper,
            liquidity  : liquidity,
            amount0Max : (amount0Forecasted * 1e18) / maxSlippage,
            amount1Max : (amount1Forecasted * 1e18) / maxSlippage
        });

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
        uint128 liquidityIncrease,
        uint256 maxSlippage
    ) internal returns (IncreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
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

        vm.prank(relayer);
        mainnetController.increaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : tokenId,
            liquidityIncrease : liquidityIncrease,
            amount0Max        : (amount0Forecasted * 1e18) / maxSlippage,
            amount1Max        : (amount1Forecasted * 1e18) / maxSlippage
        });

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
        uint256 tokenId,
        uint256 maxSlippage
    ) internal returns (DecreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        uint128 liquidity = IPositionManagerLike(_POSITION_MANAGER).getPositionLiquidity(tokenId);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidity
        );

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        vm.prank(relayer);
        mainnetController.burnPositionUniswapV4({
            poolId     : _POOL_ID,
            tokenId    : tokenId,
            amount0Min : ((amount0Forecasted + 1) * maxSlippage) / 1e18,
            amount1Min : ((amount1Forecasted + 1) * maxSlippage) / 1e18
        });

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
        uint128 liquidityDecrease,
        uint256 maxSlippage
    ) internal returns (DecreasePositionResult memory result) {
        (
            , // PoolKey
            PositionInfo positionInfo
        ) = IPositionManagerLike(_POSITION_MANAGER).getPoolAndPositionInfo(tokenId);

        ( uint256 amount0Forecasted, uint256 amount1Forecasted ) = _quoteLiquidity(
            positionInfo.tickLower(),
            positionInfo.tickUpper(),
            liquidityDecrease
        );

        uint256 usdcBeforeCall = usdc.balanceOf(address(almProxy));
        uint256 usdtBeforeCall = usdt.balanceOf(address(almProxy));

        vm.prank(relayer);
        mainnetController.decreaseLiquidityUniswapV4({
            poolId            : _POOL_ID,
            tokenId           : tokenId,
            liquidityDecrease : liquidityDecrease,
            amount0Min        : ((amount0Forecasted + 1) * maxSlippage) / 1e18,
            amount1Min        : ((amount1Forecasted + 1) * maxSlippage) / 1e18
        });

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

        assertEq(allowance, 0, "permit2 usdc allowance");

        assertEq(IERC20Like(token).allowance(address(almProxy), _PERMIT2), 0, "token usdc allowance");
    }

    function _to18From6Decimals(uint256 amount) internal pure returns (uint256) {
        return amount * 1e12;
    }

    function _getBlock() internal pure override returns (uint256) {
        return 23470490;  // September 29, 2025
    }

    function _swap(address account, address tokenIn, uint128 amountIn) internal returns (uint256 amountOut) {
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
                poolKey: IPositionManagerLike(_POSITION_MANAGER).poolKeys(bytes25(_POOL_ID)),
                zeroForOne: tokenIn == address(usdc) ? true : false,
                amountIn: amountIn,
                amountOutMinimum: 0,
                hookData: bytes("")
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
