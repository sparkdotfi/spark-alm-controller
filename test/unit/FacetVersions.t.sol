// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { Test } from "../../lib/forge-std/src/Test.sol";

import { AaveFacet }          from "../../src/facets/aave/AaveFacet.sol";
import { BasinFacet }         from "../../src/facets/basin/BasinFacet.sol";
import { CCTPFacet }          from "../../src/facets/cctp/CCTPFacet.sol";
import { CentrifugeFacet }    from "../../src/facets/centrifuge/CentrifugeFacet.sol";
import { CurveFacet }         from "../../src/facets/curve/CurveFacet.sol";
import { DAIUSDSFacet }       from "../../src/facets/dai-usds/DAIUSDSFacet.sol";
import { ERC4626Facet }       from "../../src/facets/erc4626/ERC4626Facet.sol";
import { ERC7540Facet }       from "../../src/facets/erc7540/ERC7540Facet.sol";
import { FarmFacet }          from "../../src/facets/farm/FarmFacet.sol";
import { LayerZeroFacet }     from "../../src/facets/layer-zero/LayerZeroFacet.sol";
import { MapleFacet }         from "../../src/facets/maple/MapleFacet.sol";
import { MerklFacet }         from "../../src/facets/merkl/MerklFacet.sol";
import { OTCFacet }           from "../../src/facets/otc/OTCFacet.sol";
import { PendleFacet }        from "../../src/facets/pendle/PendleFacet.sol";
import { PSMFacet }           from "../../src/facets/psm/PSMFacet.sol";
import { PSM3Facet }          from "../../src/facets/psm3/PSM3Facet.sol";
import { SparkVaultFacet }    from "../../src/facets/spark-vault/SparkVaultFacet.sol";
import { SuperstateFacet }    from "../../src/facets/superstate/SuperstateFacet.sol";
import { TransferAssetFacet } from "../../src/facets/transfer-asset/TransferAssetFacet.sol";
import { UniswapV3Facet }     from "../../src/facets/uniswap-v3/UniswapV3Facet.sol";
import { UniswapV4Facet }     from "../../src/facets/uniswap-v4/UniswapV4Facet.sol";
import { USDEFacet }          from "../../src/facets/usde/USDEFacet.sol";
import { USDSFacet }          from "../../src/facets/usds/USDSFacet.sol";
import { WEETHFacet }         from "../../src/facets/weeth/WEETHFacet.sol";
import { WrapProxyETHFacet }  from "../../src/facets/wrap-proxy-eth/WrapProxyETHFacet.sol";
import { WSTETHFacet }        from "../../src/facets/wsteth/WSTETHFacet.sol";

contract FacetVersions_Tests is Test {

    address internal MOCK_ADDRESS = makeAddr("mockAddress");

    AaveFacet          internal aaveFacet;
    BasinFacet         internal basinFacet;
    CCTPFacet          internal cctpFacet;
    CentrifugeFacet    internal centrifugeFacet;
    CurveFacet         internal curveFacet;
    DAIUSDSFacet       internal daiUSDSFacet;
    ERC4626Facet       internal erc4626Facet;
    ERC7540Facet       internal erc7540Facet;
    FarmFacet          internal farmFacet;
    LayerZeroFacet     internal layerZeroFacet;
    MapleFacet         internal mapleFacet;
    MerklFacet         internal merklFacet;
    OTCFacet           internal otcFacet;
    PendleFacet        internal pendleFacet;
    PSMFacet           internal psmFacet;
    PSM3Facet          internal psm3Facet;
    SparkVaultFacet    internal sparkVaultFacet;
    SuperstateFacet    internal superstateFacet;
    TransferAssetFacet internal transferAssetFacet;
    UniswapV3Facet     internal uniswapV3Facet;
    UniswapV4Facet     internal uniswapV4Facet;
    USDEFacet          internal usdeFacet;
    USDSFacet          internal usdsFacet;
    WEETHFacet         internal weethFacet;
    WrapProxyETHFacet  internal wrapProxyETHFacet;
    WSTETHFacet        internal wstethFacet;

    function setUp() external {
        aaveFacet          = new AaveFacet();
        cctpFacet          = new CCTPFacet(MOCK_ADDRESS, MOCK_ADDRESS);
        basinFacet         = new BasinFacet();
        centrifugeFacet    = new CentrifugeFacet();
        curveFacet         = new CurveFacet();
        daiUSDSFacet       = new DAIUSDSFacet(MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS);
        erc4626Facet       = new ERC4626Facet();
        erc7540Facet       = new ERC7540Facet();
        farmFacet          = new FarmFacet();
        layerZeroFacet     = new LayerZeroFacet();
        mapleFacet         = new MapleFacet();
        merklFacet         = new MerklFacet(MOCK_ADDRESS);
        otcFacet           = new OTCFacet();
        pendleFacet        = new PendleFacet(MOCK_ADDRESS);
        psmFacet           = new PSMFacet(MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS);
        psm3Facet          = new PSM3Facet(MOCK_ADDRESS);
        sparkVaultFacet    = new SparkVaultFacet();
        superstateFacet    = new SuperstateFacet(MOCK_ADDRESS, MOCK_ADDRESS);
        transferAssetFacet = new TransferAssetFacet();
        uniswapV3Facet     = new UniswapV3Facet(MOCK_ADDRESS, MOCK_ADDRESS);
        uniswapV4Facet     = new UniswapV4Facet(MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS);
        usdeFacet          = new USDEFacet(MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS);
        usdsFacet          = new USDSFacet(MOCK_ADDRESS);
        weethFacet         = new WEETHFacet(MOCK_ADDRESS, MOCK_ADDRESS);
        wrapProxyETHFacet  = new WrapProxyETHFacet(MOCK_ADDRESS);
        wstethFacet        = new WSTETHFacet(MOCK_ADDRESS, MOCK_ADDRESS, MOCK_ADDRESS);
    }

    function test_version() external view {
        assertEq(aaveFacet.VERSION(),          "1.0.0");
        assertEq(basinFacet.VERSION(),         "1.0.0");
        assertEq(cctpFacet.VERSION(),          "1.0.0");
        assertEq(centrifugeFacet.VERSION(),    "1.0.0");
        assertEq(curveFacet.VERSION(),         "1.0.0");
        assertEq(daiUSDSFacet.VERSION(),       "1.0.0");
        assertEq(erc4626Facet.VERSION(),       "1.0.0");
        assertEq(erc7540Facet.VERSION(),       "1.0.0");
        assertEq(farmFacet.VERSION(),          "1.0.0");
        assertEq(layerZeroFacet.VERSION(),     "1.0.0");
        assertEq(mapleFacet.VERSION(),         "1.0.0");
        assertEq(merklFacet.VERSION(),         "1.0.0");
        assertEq(otcFacet.VERSION(),           "1.0.0");
        assertEq(pendleFacet.VERSION(),        "1.0.0");
        assertEq(psmFacet.VERSION(),           "1.0.0");
        assertEq(psm3Facet.VERSION(),          "1.0.0");
        assertEq(sparkVaultFacet.VERSION(),    "1.0.0");
        assertEq(superstateFacet.VERSION(),    "1.0.0");
        assertEq(transferAssetFacet.VERSION(), "1.0.0");
        assertEq(uniswapV3Facet.VERSION(),     "1.0.0");
        assertEq(uniswapV4Facet.VERSION(),     "1.0.0");
        assertEq(usdeFacet.VERSION(),          "1.0.0");
        assertEq(usdsFacet.VERSION(),          "1.0.0");
        assertEq(weethFacet.VERSION(),         "1.0.0");
        assertEq(wrapProxyETHFacet.VERSION(),  "1.0.0");
        assertEq(wstethFacet.VERSION(),        "1.0.0");
    }

}
