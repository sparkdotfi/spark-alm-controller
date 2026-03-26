// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { AccessControlEnumerable } from "../lib/openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";

import { CentrifugeLib }    from "./libraries/CentrifugeLib.sol";
import { CurveLib }         from "./libraries/CurveLib.sol";
import { LayerZeroLib }     from "./libraries/LayerZeroLib.sol";
import { PendleLib }        from "./libraries/PendleLib.sol";
import { MerklLib }         from "./libraries/MerklLib.sol";
import { UniswapV3Lib }     from "./libraries/UniswapV3Lib.sol";

import { IALMProxy }   from "./interfaces/IALMProxy.sol";
import { IRateLimits } from "./interfaces/IRateLimits.sol";

import { Controller } from "./Controller.sol";

contract ForeignController is Controller, AccessControlEnumerable {

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event MaxSlippageSet(address indexed pool, uint256 maxSlippage);

    event RelayerRemoved(address indexed relayer);

    event PendleRouterSet(address indexed pendleRouter);

    event MerklDistributorSet(address indexed merklDistributor);

    event UniswapV3SwapRouterSet(address indexed swapRouter);

    event UniswapV3PositionManagerSet(address indexed manager);

    /**********************************************************************************************/
    /*** State variables                                                                        ***/
    /**********************************************************************************************/

    bytes32 public constant FREEZER = keccak256("FREEZER");
    bytes32 public constant RELAYER = keccak256("RELAYER");

    bytes32 public constant LIMIT_CENTRIFUGE_TRANSFER = CentrifugeLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_CURVE_DEPOSIT       = CurveLib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_CURVE_SWAP          = CurveLib.LIMIT_SWAP;
    bytes32 public constant LIMIT_CURVE_WITHDRAW      = CurveLib.LIMIT_WITHDRAW;
    bytes32 public constant LIMIT_LAYERZERO_TRANSFER  = LayerZeroLib.LIMIT_TRANSFER;
    bytes32 public constant LIMIT_PENDLE_PT_REDEEM    = PendleLib.LIMIT_REDEEM;
    bytes32 public constant LIMIT_UNISWAP_V3_DEPOSIT  = UniswapV3Lib.LIMIT_DEPOSIT;
    bytes32 public constant LIMIT_UNISWAP_V3_SWAP     = UniswapV3Lib.LIMIT_SWAP;
    bytes32 public constant LIMIT_UNISWAP_V3_WITHDRAW = UniswapV3Lib.LIMIT_WITHDRAW;

    IALMProxy   public immutable proxy;
    address     public immutable cctp;
    address     public immutable psm;
    IRateLimits public immutable rateLimits;

    address public uniswapV3Router;
    address public uniswapV3PositionManager;

    address public immutable usdc;

    address public merklDistributor;

    address public pendleRouter;

    mapping(address pool => uint256 maxSlippage) public maxSlippages;  // 1e18 precision

    mapping(uint32 destinationEndpointId => bytes32 layerZeroRecipient) public layerZeroRecipients;
    mapping(uint16 destinationCentrifugeId => bytes32 recipient)        public centrifugeRecipients;

    // Uniswap V3 pool params
    mapping(address pool => UniswapV3Lib.PoolParams params) public uniswapV3PoolParams;

    /**********************************************************************************************/
    /*** Initialization                                                                         ***/
    /**********************************************************************************************/

    constructor(
        address admin_,
        address proxy_,
        address rateLimits_,
        address accessControls_,
        address psm_,
        address usdc_,
        address cctp_
    ) Controller(accessControls_, proxy_, rateLimits_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);

        proxy      = IALMProxy(proxy_);
        rateLimits = IRateLimits(rateLimits_);
        psm        = psm_;
        usdc       = usdc_;
        cctp       = cctp_;
    }

    /**********************************************************************************************/
    /*** Admin functions                                                                        ***/
    /**********************************************************************************************/

    function setMaxSlippage(address pool, uint256 maxSlippage)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool != address(0), "FC/pool-zero-address");

        maxSlippages[pool] = maxSlippage;
        emit MaxSlippageSet(pool, maxSlippage);
    }

    function setLayerZeroRecipient(uint32 destinationEndpointId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        LayerZeroLib.setRecipient(layerZeroRecipients, destinationEndpointId, recipient);
    }

    function setPendleRouter(address pendleRouter_)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        pendleRouter = pendleRouter_;
        emit PendleRouterSet(pendleRouter_);
    }

    function setMerklDistributor(address merklDistributor_)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        merklDistributor = merklDistributor_;
        emit MerklDistributorSet(merklDistributor_);
    }

    function setCentrifugeRecipient(uint16 centrifugeId, bytes32 recipient)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        CentrifugeLib.setCentrifugeRecipient(centrifugeRecipients, centrifugeId, recipient);
    }

    function setUniswapV3PositionManager(address manager)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit UniswapV3PositionManagerSet(uniswapV3PositionManager = manager);
    }

    function setUniswapV3SwapRouter(address swapRouter)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        emit UniswapV3SwapRouterSet(uniswapV3Router = swapRouter);
    }

    function setUniswapV3PoolMaxTickDelta(address pool, uint24 maxTickDelta)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setPoolMaxTickDelta(pool, maxTickDelta, uniswapV3PoolParams);
    }

    function setUniswapV3AddLiquidityLowerTickBound(address pool, int24 lowerTickBound)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setAddLiquidityLowerTickBound(pool, lowerTickBound, uniswapV3PoolParams);
    }

    function setUniswapV3AddLiquidityUpperTickBound(address pool, int24 upperTickBound)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setAddLiquidityUpperTickBound(pool, upperTickBound, uniswapV3PoolParams);
    }

    function setUniswapV3TWAPSecondsAgo(address pool, uint32 twapSecondsAgo)
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        UniswapV3Lib.setTWAPSecondsAgo(pool, twapSecondsAgo, uniswapV3PoolParams);
    }

    /**********************************************************************************************/
    /*** Freezer functions                                                                      ***/
    /**********************************************************************************************/

    function removeRelayer(address relayer) external nonReentrant onlyRole(FREEZER) {
        _revokeRole(RELAYER, relayer);
        emit RelayerRemoved(relayer);
    }

    /**********************************************************************************************/
    /*** Relayer UniswapV3 functions                                                            ***/
    /**********************************************************************************************/

    function swapUniswapV3(
        address pool,
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24  maxTickDelta
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountOut)
    {
        return UniswapV3Lib.swap({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            pool         : pool,
            router       : uniswapV3Router,
            tokenIn      : tokenIn,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            tickDelta    : maxTickDelta,
            poolParams   : uniswapV3PoolParams
        });
    }

    function addLiquidityUniswapV3(
        address                            pool,
        uint256                            tokenId,
        UniswapV3Lib.Ticks        calldata ticks,
        UniswapV3Lib.TokenAmounts calldata target,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                            deadline
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 tokenId_, uint128 liquidity_, UniswapV3Lib.TokenAmounts memory amounts_)
    {
        ( tokenId_, liquidity_, amounts_ ) = UniswapV3Lib.addLiquidity({
            proxy           : address(proxy),
            rateLimits      : address(rateLimits),
            pool            : pool,
            positionManager : uniswapV3PositionManager,
            tokenId         : tokenId,
            ticks           : ticks,
            target          : target,
            min             : min,
            deadline        : deadline,
            maxSlippages    : maxSlippages,
            poolParams      : uniswapV3PoolParams
        });
    }

    function removeLiquidityUniswapV3(
        address                            pool,
        uint256                            tokenId,
        uint128                            liquidity,
        UniswapV3Lib.TokenAmounts calldata min,
        uint256                            deadline
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (UniswapV3Lib.TokenAmounts memory amounts_)
    {
        return UniswapV3Lib.removeLiquidity({
            proxy           : address(proxy),
            rateLimits      : address(rateLimits),
            pool            : pool,
            positionManager : uniswapV3PositionManager,
            tokenId         : tokenId,
            liquidity       : liquidity,
            min             : min,
            deadline        : deadline,
            maxSlippages    : maxSlippages
        });
    }

    // NOTE: !!! This function was deployed without integration testing !!!
    //       KEEP RATE LIMIT AT ZERO until LayerZero dependencies are live and
    //       all functionality has been thoroughly integration tested.
    function transferTokenLayerZero(
        address oftAddress,
        uint256 amount,
        uint32  destinationEndpointId
    )
        external
        payable
        nonReentrant
        onlyRole(RELAYER)
    {
        LayerZeroLib.transfer({
            proxy                 : address(proxy),
            rateLimits            : address(rateLimits),
            oftAddress            : oftAddress,
            amount                : amount,
            destinationEndpointId : destinationEndpointId,
            layerZeroRecipients   : layerZeroRecipients
        });
    }

    /**********************************************************************************************/
    /*** Relayer Curve StableSwap functions                                                     ***/
    /**********************************************************************************************/

    function swapCurve(
        address pool,
        uint256 inputIndex,
        uint256 outputIndex,
        uint256 amountIn,
        uint256 minAmountOut
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 amountOut)
    {
        return CurveLib.swap({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            pool         : pool,
            inputIndex   : inputIndex,
            outputIndex  : outputIndex,
            amountIn     : amountIn,
            minAmountOut : minAmountOut,
            maxSlippages : maxSlippages
        });
    }

    function addLiquidityCurve(address pool, uint256[] memory depositAmounts, uint256 minLpAmount)
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256 shares)
    {
        return CurveLib.addLiquidity({
            proxy          : address(proxy),
            rateLimits     : address(rateLimits),
            pool           : pool,
            minLpAmount    : minLpAmount,
            depositAmounts : depositAmounts,
            maxSlippages   : maxSlippages
        });
    }

    function removeLiquidityCurve(
        address   pool,
        uint256   lpBurnAmount,
        uint256[] memory minWithdrawAmounts
    )
        external
        nonReentrant
        onlyRole(RELAYER)
        returns (uint256[] memory withdrawnTokens)
    {
        return CurveLib.removeLiquidity({
            proxy              : address(proxy),
            rateLimits         : address(rateLimits),
            pool               : pool,
            lpBurnAmount       : lpBurnAmount,
            minWithdrawAmounts : minWithdrawAmounts,
            maxSlippages       : maxSlippages
        });
    }

    /**********************************************************************************************/
    /*** Relayer Merkl functions                                                                ***/
    /**********************************************************************************************/

    function toggleOperatorMerkl(address operator) external nonReentrant onlyRole(RELAYER) {
        MerklLib.toggleOperator({
            proxy       : address(proxy),
            distributor : merklDistributor,
            operator    : operator
        });
    }

    /**********************************************************************************************/
    /*** Relayer Pendle functions                                                               ***/
    /**********************************************************************************************/

    function redeemPendlePT(address pendleMarket, uint256 pyAmountIn, uint256 minAmountOut)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        PendleLib.redeem({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            market       : pendleMarket,
            router       : pendleRouter,
            pyAmountIn   : pyAmountIn,
            minAmountOut : minAmountOut
        });
    }

    /**********************************************************************************************/
    /*** Relayer Centrifuge functions                                                           ***/
    /**********************************************************************************************/

    // NOTE: These cancellation methods are compatible with ERC-7887

    function cancelCentrifugeDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.cancelDepositRequest(address(proxy), address(rateLimits), token);
    }

    function claimCentrifugeCancelDepositRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.claimCancelDepositRequest(address(proxy), address(rateLimits), token);
    }

    function cancelCentrifugeRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.cancelRedeemRequest(address(proxy), address(rateLimits), token);
    }

    function claimCentrifugeCancelRedeemRequest(address token)
        external
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.claimCancelRedeemRequest(address(proxy), address(rateLimits), token);
    }

    function transferSharesCentrifuge(address token, uint128 amount, uint16 centrifugeId)
        external
        payable
        nonReentrant
        onlyRole(RELAYER)
    {
        CentrifugeLib.transferShares({
            proxy        : address(proxy),
            rateLimits   : address(rateLimits),
            token        : token,
            centrifugeId : centrifugeId,
            amount       : amount,
            recipients   : centrifugeRecipients
        });
    }

}
