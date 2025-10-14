// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

// import { IERC4626 } from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

import "./ForkTestBase.t.sol";

contract ERC4626DonationAttackTestBase is ForkTestBase {

    address morpho_vault = IERC4626(0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597);

    function setUp() override public {
        super.setUp();

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_DEPOSIT(),  address(morpho_vault));
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(mainnetController.LIMIT_4626_WITHDRAW(), address(morpho_vault));

        // Basic validation
        bytes memory data = abi.encodeWithSignature("symbol()");
        (, bytes memory returnData) = morpho_vault.call(data);
        assertEq(keccak256(returnData), keccak256(abi.encode("sparkUSDS")));

        data = abi.encodeWithSignature("totalAssets()");
        (, returnData) = morpho_vault.call(data);
        assertEq(abi.decode(returnData, (uint256)), 0);

        data = abi.encodeWithSignature("totalSupply()");
        (, returnData) = morpho_vault.call(data);
        assertEq(abi.decode(returnData, (uint256)), 0);

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
        usds.approve(morpho_vault, 1);
        // morpho_vault.call(abi.encodeWithSignature("deposit(uint256,address)", 1, mallory));
        usds.transfer(morpho_vault, 9);
        vm.stopPrank();

        // assertEq()

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

