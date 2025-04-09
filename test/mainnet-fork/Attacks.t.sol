// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

import { MainnetControllerBUIDLTestBase }  from "./Buidl.t.sol";
import { MainnetControllerEthenaE2ETests } from "./Ethena.t.sol";
import { MapleTestBase }                   from "./Maple.t.sol";

import { Id, MarketParamsLib, MorphoTestBase, MarketAllocation } from "./MorphoAllocations.t.sol";

import { IMapleTokenLike } from "../../src/MainnetController.sol";

interface IBuidlLike is IERC20 {
    function issueTokens(address to, uint256 amount) external;
}

interface IMapleTokenExtended is IMapleTokenLike {
    function manager() external view returns (address);
}

interface IPermissionManagerLike {
    function admin() external view returns (address);
    function setLenderAllowlist(
        address            poolManager_,
        address[] calldata lenders_,
        bool[]    calldata booleans_
    ) external;
}

interface IPoolManagerLike {
    function withdrawalManager() external view returns (address);
    function poolDelegate() external view returns (address);
}

interface IWhitelistLike {
    function addWallet(address account, string memory id) external;
    function registerInvestor(string memory id, string memory collisionHash) external;
}

contract EthenaAttackTests is MainnetControllerEthenaE2ETests {

    function test_attack_compromisedRelayer_lockingFundsInEthenaSilo() external {
        deal(address(susde), address(almProxy), 1_000_000e18);

        address silo = susde.silo();

        uint256 startingSiloBalance = usde.balanceOf(silo);

        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(1_000_000e18);

        skip(7 days);

        // Relayer is now compromised and wants to lock funds in the silo
        vm.prank(relayer);
        mainnetController.cooldownAssetsSUSDe(1);

        // Real relayer cannot withdraw when they want to
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidCooldown()"));
        mainnetController.unstakeSUSDe();

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(freezer);
        mainnetController.removeRelayer(relayer);

        skip(7 days);

        // Compromised relayer cannot perform attack anymore
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER
        ));
        mainnetController.cooldownAssetsSUSDe(1);

        // Funds have been locked in the silo this whole time
        assertEq(usde.balanceOf(address(almProxy)), 0);
        assertEq(usde.balanceOf(silo),              startingSiloBalance + 1_000_000e18 + 1);  // 1 wei deposit as well

        // Backstop relayer can unstake the funds
        vm.prank(backstopRelayer);
        mainnetController.unstakeSUSDe();

        assertEq(usde.balanceOf(address(almProxy)), 1_000_000e18 + 1);
        assertEq(usde.balanceOf(silo),              startingSiloBalance);
    }

}

contract MapleAttackTests is MapleTestBase {

    function test_attack_compromisedRelayer_delayRequestMapleRedemption() external {
        deal(address(usdc), address(almProxy), 1_000_000e6);

        vm.prank(relayer);
        mainnetController.depositERC4626(address(syrup), 1_000_000e6);

        // Malicious relayer delays the request for redemption for 1m
        // because new requests can't be fulfilled until the previous is fulfilled or cancelled
        vm.prank(relayer);
        mainnetController.requestMapleRedemption(address(syrup), 1);

        // Cannot process request
        vm.prank(relayer);
        vm.expectRevert("WM:AS:IN_QUEUE");
        mainnetController.requestMapleRedemption(address(syrup), 500_000e6);

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(freezer);
        mainnetController.removeRelayer(relayer);

        // Compromised relayer cannot perform attack anymore
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER
        ));
        mainnetController.requestMapleRedemption(address(syrup), 1);

        // Governance relayer can cancel and submit the real request
        vm.startPrank(backstopRelayer);
        mainnetController.cancelMapleRedemption(address(syrup), 1);
        mainnetController.requestMapleRedemption(address(syrup), 500_000e6);
        vm.stopPrank();
    }

}

contract BUIDLAttackTests is MainnetControllerBUIDLTestBase {

    address admin = 0xe01605f6b6dC593b7d2917F4a0940db2A625b09e;

    IBuidlLike     buidl     = IBuidlLike(0x7712c34205737192402172409a8F7ccef8aA2AEc);
    IWhitelistLike whitelist = IWhitelistLike(0x0Dac900f26DE70336f2320F7CcEDeE70fF6A1a5B);


    uint256 internal speedup = 10;

    function setUp() public virtual override {
        super.setUp();

        vm.label(address(0x0A65a40a4B2F64D3445A628aBcFC8128625483A4), "LOCK_MANAGER");
        vm.label(address(0x1dc378568cefD4596C5F9f9A14256D8250b56369), "COMPLIANCE_CONFIGURATION_SERVICE");
        vm.label(address(0x07A1EBFb9a9A421249DDC71Bddb8860cc077E3a9), "COMPLIANCE_SERVICE");

        bytes32 depositKey = RateLimitHelpers.makeAssetDestinationKey(
            mainnetController.LIMIT_ASSET_TRANSFER(), address(usdc), address(buidlDeposit)
        );

        bytes32 redeemKey = mainnetController.LIMIT_BUIDL_REDEEM_CIRCLE();

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey, 2_000_000e6, uint256(2_000_000e6) / 1 days);
        rateLimits.setRateLimitData(redeemKey,  2_000_000e6, uint256(2_000_000e6) / 1 days);
        vm.stopPrank();

        vm.startPrank(admin);
        whitelist.registerInvestor("spark-almProxy", "collisionHash");
        whitelist.addWallet(address(almProxy), "spark-almProxy");
        vm.stopPrank();

        deal(address(usdc), address(almProxy), 2_000_000e6);

        // Step 1: Deposit into BUIDL
        vm.prank(relayer);
        mainnetController.transferAsset(address(usdc), buidlDeposit, 1_000_000e6);

        // Step 2: BUIDL gets minted into proxy
        assertEq(buidl.balanceOf(address(almProxy)), 0);

        vm.prank(admin);
        buidl.issueTokens(address(almProxy), 1_000_000e6);

        assertEq(buidl.balanceOf(address(almProxy)), 1_000_000e6);

        // Step 3: Malicious relayer spams transfers & redemptions
        //         Every iteration uses a cold `sload` so need at most 30e6 / 2100 = 14_286
        //         The iterations gas cost is roughly linear per iteration, to speed up the test we scale
        //         down both iterations and gas used.
        for (uint256 i; i < 10_000 / speedup; i++) {
            vm.prank(relayer);
            mainnetController.transferAsset(address(usdc), buidlDeposit, 1e6);
            vm.prank(admin);
            buidl.issueTokens(address(almProxy), 1e6);
        }

        // Skip time lock
        skip(24 hours);
    }

    // Run test in its own transaction so the sloads are cold
    function test_attack_issuanceDos() public {
        // Step 4: Redeem non-malicious BUIDL after timelock is passed
        vm.startPrank(relayer);
        vm.expectRevert("SafeERC20: low-level call failed");
        mainnetController.redeemBUIDLCircleFacility{gas: 30e6 / speedup}(1_000_000e6);
        vm.stopPrank();
    }
}

contract MorphoAttackTests is MorphoTestBase {

    function test_attack_compromisedRelayer_setSupplyQueue() external {
        Id[] memory supplyQueueUSDC = new Id[](2);
        supplyQueueUSDC[0] = MarketParamsLib.id(market1);
        supplyQueueUSDC[1] = MarketParamsLib.id(market2);

        // No supply queue to start, but caps are above zero
        assertEq(morphoVault.supplyQueueLength(), 0);

        vm.prank(relayer);
        mainnetController.setSupplyQueueMorpho(address(morphoVault), supplyQueueUSDC);

        assertEq(morphoVault.supplyQueueLength(), 2);

        assertEq(Id.unwrap(morphoVault.supplyQueue(0)), Id.unwrap(MarketParamsLib.id(market1)));
        assertEq(Id.unwrap(morphoVault.supplyQueue(1)), Id.unwrap(MarketParamsLib.id(market2)));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_4626_DEPOSIT(),
                address(morphoVault)
            ),
            25_000_000e18,
            uint256(5_000_000e18) / 1 days
        );
        vm.stopPrank();

        deal(address(dai), address(almProxy), 1_000_000e18);

        // Able to deposit
        vm.prank(relayer);
        mainnetController.depositERC4626(address(morphoVault), 500_000e18);

        Id[] memory emptySupplyQueue = new Id[](0);

        // Malicious relayer empties the supply queue
        vm.prank(relayer);
        mainnetController.setSupplyQueueMorpho(address(morphoVault), emptySupplyQueue);

        // DOS deposits into morpho vault
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature("AllCapsReached()"));
        mainnetController.depositERC4626(address(morphoVault), 500_000e18);

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(freezer);
        mainnetController.removeRelayer(relayer);

        // Compromised relayer can no longer perform the attack
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER
        ));
        mainnetController.setSupplyQueueMorpho(address(morphoVault), emptySupplyQueue);

        // Backstop relayer can restore original supply queue
        vm.prank(backstopRelayer);
        mainnetController.setSupplyQueueMorpho(address(morphoVault), supplyQueueUSDC);

        // Deposit works again
        vm.prank(backstopRelayer);
        mainnetController.depositERC4626(address(morphoVault), 500_000e18);
    }

    function test_attack_compromisedRelayer_reallocateMorpho() public {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                mainnetController.LIMIT_4626_DEPOSIT(),
                address(morphoVault)
            ),
            25_000_000e6,
            uint256(5_000_000e6) / 1 days
        );
        vm.stopPrank();

        uint256 market1Position = positionAssets(market1);
        uint256 market2Position = positionAssets(market2);

        // Move 1m from market1 to market2
        MarketAllocation[] memory reallocations = new MarketAllocation[](2);
        reallocations[0] = MarketAllocation({
            marketParams : market1,
            assets       : market1Position - 1_000_000e18
        });
        reallocations[1] = MarketAllocation({
            marketParams : market2,
            assets       : type(uint256).max
        });

        // Malicious relayer reallocates freely
        vm.prank(relayer);
        mainnetController.reallocateMorpho(address(morphoVault), reallocations);

        // Frezer can remove the compromised relayer and fallback to the governance relayer
        vm.prank(freezer);
        mainnetController.removeRelayer(relayer);

        // Compromised relayer can no longer perform the attack
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            relayer,
            RELAYER
        ));
        mainnetController.reallocateMorpho(address(morphoVault), reallocations);

        market1Position = positionAssets(market1);
        market2Position = positionAssets(market2);

        // Backstop relayer can restore original allocations
        reallocations[0] = MarketAllocation({
            marketParams : market2,
            assets       : market2Position - 1_000_000e18
        });
        reallocations[1] = MarketAllocation({
            marketParams : market1,
            assets       : type(uint256).max
        });
        vm.prank(backstopRelayer);
        mainnetController.reallocateMorpho(address(morphoVault), reallocations);
    }

}
