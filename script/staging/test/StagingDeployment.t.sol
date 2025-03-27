// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import "forge-std/Test.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { Usds } from "usds/src/Usds.sol";

import { SUsds } from "sdai/src/SUsds.sol";

import { Ethereum } from "bloom-address-registry/Ethereum.sol";

import { PSM3 } from "spark-psm/src/PSM3.sol";

import { MainnetControllerDeploy } from "../../../deploy/ControllerDeploy.sol";
import { MainnetControllerInit }   from "../../../deploy/MainnetControllerInit.sol";

import { IRateLimits } from "../../../src/interfaces/IRateLimits.sol";

import { ALMProxy }          from "../../../src/ALMProxy.sol";
import { MainnetController } from "../../../src/MainnetController.sol";
import { RateLimits }        from "../../../src/RateLimits.sol";

import { RateLimitHelpers }  from "../../../src/RateLimitHelpers.sol";

interface IVatLike {
    function can(address, address) external view returns (uint256);
}

contract StagingDeploymentTestBase is Test {

    using stdJson       for *;
    using ScriptTools   for *;

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 constant RELEASE_DATE = 20241227;

    // Common variables
    address admin;

    // Configuration data
    string inputMainnet;
    string outputMainnet;
    string outputMainnetDeps;

    // Mainnet contracts

    Usds   usds;
    SUsds  susds;
    IERC20 usdc;
    IERC20 dai;

    address vault;
    address relayerSafe;
    address usdsJoin;

    ALMProxy          almProxy;
    MainnetController mainnetController;
    RateLimits        rateLimits;

    /**********************************************************************************************/
    /**** Setup                                                                                 ***/
    /**********************************************************************************************/

    function setUp() public virtual {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1");

        vm.createSelectFork(getChain("mainnet").rpcUrl, 21600000);  // Jan 11, 2025

        // JSON data
        inputMainnet = ScriptTools.readInput("mainnet-staging");

        outputMainnet     = ScriptTools.readOutput("mainnet-staging-release",      RELEASE_DATE);
        outputMainnetDeps = ScriptTools.readOutput("mainnet-staging-deps-release", RELEASE_DATE);

        // Roles
        admin       = outputMainnetDeps.readAddress(".admin");
        relayerSafe = outputMainnetDeps.readAddress(".relayer");

        // Tokens
        usds  = Usds(outputMainnetDeps.readAddress(".usds"));
        susds = SUsds(outputMainnetDeps.readAddress(".susds"));
        usdc  = IERC20(outputMainnetDeps.readAddress(".usdc"));
        dai   = IERC20(outputMainnetDeps.readAddress(".dai"));

        // Dependencies
        vault    = outputMainnetDeps.readAddress(".allocatorVault");
        usdsJoin = outputMainnetDeps.readAddress(".usdsJoin");

        // ALM system
        almProxy          = ALMProxy(payable(outputMainnet.readAddress(".almProxy")));
        rateLimits        = RateLimits(outputMainnet.readAddress(".rateLimits"));
        mainnetController = MainnetController(outputMainnet.readAddress(".controller"));

        deal(address(usds), address(usdsJoin), 1000e18);  // Ensure there is enough balance
    }
}

contract MainnetStagingDeploymentTests is StagingDeploymentTestBase {

    function test_mintUSDS() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.prank(relayerSafe);
        mainnetController.mintUSDS(10e18);

        assertEq(usds.balanceOf(address(almProxy)), startingBalance + 10e18);
    }

    function test_mintAndSwapToUSDC() public {
        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(almProxy)), startingBalance + 10e6);
    }

    function test_depositAndWithdrawUsdsFromSUsds() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 10e18);
        skip(1 days);
        mainnetController.withdrawERC4626(Ethereum.SUSDS, 10e18);
        vm.stopPrank();

        assertEq(usds.balanceOf(address(almProxy)), startingBalance + 10e18);

        assertGe(IERC4626(Ethereum.SUSDS).balanceOf(address(almProxy)), 0);  // Interest earned
    }

    function test_depositAndRedeemUsdsFromSUsds() public {
        uint256 startingBalance = usds.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.depositERC4626(Ethereum.SUSDS, 10e18);
        skip(1 days);
        mainnetController.redeemERC4626(Ethereum.SUSDS, IERC4626(Ethereum.SUSDS).balanceOf(address(almProxy)));
        vm.stopPrank();

        assertGe(usds.balanceOf(address(almProxy)), startingBalance + 10e18);  // Interest earned

        assertEq(IERC4626(Ethereum.SUSDS).balanceOf(address(almProxy)), 0);
    }

    function test_mintDepositCooldownAssetsBurnUsde() public {
        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.prepareUSDeMint(10e6);
        vm.stopPrank();

        _simulateUsdeMint(10e6);

        vm.startPrank(relayerSafe);
        mainnetController.depositERC4626(Ethereum.SUSDE, 10e18);
        skip(1 days);
        mainnetController.cooldownAssetsSUSDe(10e18 - 1);  // Rounding
        skip(7 days);
        mainnetController.unstakeSUSDe();
        mainnetController.prepareUSDeBurn(10e18 - 1);
        vm.stopPrank();

        _simulateUsdeBurn(10e18 - 1);

        assertEq(usdc.balanceOf(address(almProxy)), startingBalance + 10e6 - 1);  // Rounding not captured

        assertGe(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)), 0);  // Interest earned
    }

    function test_mintDepositCooldownSharesBurnUsde() public {
        vm.startPrank(relayerSafe);
        mainnetController.mintUSDS(10e18);
        mainnetController.swapUSDSToUSDC(10e6);
        mainnetController.prepareUSDeMint(10e6);
        vm.stopPrank();

        uint256 startingBalance = usdc.balanceOf(address(almProxy));

        _simulateUsdeMint(10e6);

        vm.startPrank(relayerSafe);
        mainnetController.depositERC4626(Ethereum.SUSDE, 10e18);
        skip(1 days);
        uint256 usdeAmount = mainnetController.cooldownSharesSUSDe(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)));
        skip(7 days);
        mainnetController.unstakeSUSDe();

        // Handle situation where usde balance of ALM Proxy is higher than max rate limit
        uint256 maxBurnAmount = rateLimits.getCurrentRateLimit(mainnetController.LIMIT_USDE_BURN());
        uint256 burnAmount    = usdeAmount > maxBurnAmount ? maxBurnAmount : usdeAmount;
        mainnetController.prepareUSDeBurn(burnAmount);

        vm.stopPrank();

        _simulateUsdeBurn(burnAmount);

        assertGe(usdc.balanceOf(address(almProxy)), startingBalance - 1);  // Interest earned (rounding)

        assertEq(IERC4626(Ethereum.SUSDE).balanceOf(address(almProxy)), 0);
    }

    /**********************************************************************************************/
    /**** Helper functions                                                                      ***/
    /**********************************************************************************************/

    // NOTE: In reality these actions are performed by the signer submitting an order with an
    //       EIP712 signature which is verified by the ethenaMinter contract,
    //       minting/burning USDe into the ALMProxy. Also, for the purposes of this test,
    //       minting/burning is done 1:1 with USDC.

    // TODO: Try doing ethena minting with EIP-712 signatures (vm.sign)

    function _simulateUsdeMint(uint256 amount) internal {
        vm.prank(Ethereum.ETHENA_MINTER);
        usdc.transferFrom(address(almProxy), Ethereum.ETHENA_MINTER, amount);
        deal(
            Ethereum.USDE,
            address(almProxy),
            IERC20(Ethereum.USDE).balanceOf(address(almProxy)) + amount * 1e12
        );
    }

    function _simulateUsdeBurn(uint256 amount) internal {
        vm.prank(Ethereum.ETHENA_MINTER);
        IERC20(Ethereum.USDE).transferFrom(address(almProxy), Ethereum.ETHENA_MINTER, amount);
        deal(address(usdc), address(almProxy), usdc.balanceOf(address(almProxy)) + amount / 1e12);
    }

}
