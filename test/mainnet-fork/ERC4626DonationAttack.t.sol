// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IMetaMorpho, Id } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParamsLib }       from "morpho-blue/src/libraries/MarketParamsLib.sol";
import { IMorpho, MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import "./ForkTestBase.t.sol";

contract ERC4626DonationAttackTestBase is ForkTestBase {

    IMetaMorpho morpho_vault = IMetaMorpho(0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597);

    address curator        = makeAddr("curator");
    address guardian       = makeAddr("guardian");
    address fee_recipient  = makeAddr("fee_recipient");
    address allocator      = makeAddr("allocator");
    address skim_recipient = makeAddr("skim_recipient");

    function setUp() override public {
        super.setUp();

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  address(morpho_vault));
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), address(morpho_vault));

        // Basic validation
        assertEq(keccak256(abi.encode(morpho_vault.symbol())), keccak256(abi.encode("sparkUSDS")));
        assertEq(morpho_vault.totalAssets(), 0);
        assertEq(morpho_vault.totalSupply(), 0);

        // Initialization
        vm.startPrank(Ethereum.SPARK_PROXY);
        morpho_vault.setCurator(curator);
        morpho_vault.submitGuardian(guardian);
        morpho_vault.setFeeRecipient(fee_recipient);
        morpho_vault.setIsAllocator(allocator, true);
        morpho_vault.setSkimRecipient(skim_recipient);

        // Choose the Morpho market you want to allocate to
        MarketParams memory marketParams = MarketParams({
            loanToken: Ethereum.USDS,
            collateralToken: address(0x0),
            oracle: address(0x0),
            irm: address(0x0),
            lltv: 0
        });
        Id marketId = MarketParamsLib.id(marketParams);

        morpho_vault.submitCap(marketParams, 10_000_000e18);
        skip(morpho_vault.timelock());  // Wait the timelock
        morpho_vault.acceptCap(marketParams);

        // Now that the market has a non-zero cap, set the supply queue order
        Id[] memory supplyOrder = new Id[](1);
        supplyOrder[0] = marketId;
        morpho_vault.setSupplyQueue(supplyOrder);
        vm.stopPrank();

        assertEq(morpho_vault.curator(), curator);
        assertEq(morpho_vault.guardian(), guardian);
        assertEq(morpho_vault.feeRecipient(), fee_recipient);
        assertTrue(morpho_vault.isAllocator(allocator));

        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(depositKey,  5_000_000e18, uint256(1_000_000e18) / 4 hours);
        rateLimits.setRateLimitData(withdrawKey, 5_000_000e18, uint256(1_000_000e18) / 4 hours);
        mainnetController.setMaxSlippage(address(susds), 1e18 - 1e4);  // Rounding slippage
        vm.stopPrank();
    }

    function _getBlock() internal override pure returns (uint256) {
        return 22932160;  // July 16, 2025
    }

}

contract ERC4626DonationAttack is ERC4626DonationAttackTestBase {

    function test_donationAttackERC4626_usds() external {
        address mallory = makeAddr("mallory");

        deal(address(usds), mallory, 10);

        vm.startPrank(mallory);
        usds.approve(address(morpho_vault), 1);
        morpho_vault.deposit(1, mallory);
        usds.transfer(address(morpho_vault), 9);
        vm.stopPrank();

        assertEq(morpho_vault.totalSupply(), 1);
        // assertEq(morpho_vault.totalAssets(), 10);
        // assertEq(morpho_vault.convertToAssets(1), 10);

        // usds.approve(address(mainnetController), type(uint256).max);

        // Deposit into vault
        // vm.startPrank(alice);
        // mainnetController.depositERC4626(address(susds), morpho_vault, 1_000_000e18, alice);

        // // Check shares received
        // bytes memory data = abi.encodeWithSignature("balanceOf(address)", alice);
        // (, bytes memory returnData) = morpho_vault.call(data);
        // uint256 shares = abi.decode(returnData, (uint256));
        // assertEq(shares, 1_000_000e18);
        //
        // // Check totalAssets and totalSupply
        // data = abi.encodeWithSignature("totalAssets()");
        // (, returnData) = morpho_vault.call(data);
        // assertEq(abi.decode(returnData, (uint256)), 1_000_000e18);
        //
        // data = abi.encodeWithSignature("totalSupply()");
        // (, returnData) = morpho_vault.call(data);
        // assertEq(abi.decode(returnData, (uint256)), 1_000_000e18);
        //
        // // Simulate donation attack by sending 1_000_000 susds directly to the vault
        // susds.transfer(morpho_vault, 1_000_000e18);
        //
        // // Check totalAssets and totalSupply after donation
        // data = abi.encodeWithSignature("totalAssets()");
        // (, returnData) = morpho_vault.call(data);
        // assertEq(abi.decode(returnData, (uint256)), 2_000_000e18);
        //
        // data = abi.encodeWithSignature("totalSupply()");
        // (, returnData) = morpho_vault.call(data);
        // assertEq(abi.decode(returnData, (uint256)), 1_000_000e18);
        //
        // // Withdraw all shares
        // mainnetController.withdrawERC4626(address(susds), morpho_vault, shares, alice, alice);
        //
        // // Check final susds balance of Alice
        // uint256 finalBalance = susds.balanceOf(alice);
        // // Alice should have more than her initial deposit due to the donation attack
        // assertGt(finalBalance, 1_000_000e18);
        //
        // vm.stopPrank();
    }

}

