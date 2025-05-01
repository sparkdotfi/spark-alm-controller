// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IWhitelistLike {
    function addWallet(address account, string memory id) external;
    function registerInvestor(string memory id, string memory collisionHash) external;
}

interface IBuidlLike is IERC20 {
    function issueTokens(address to, uint256 amount) external;
}

contract MainnetControllerBUIDLTestBase is ForkTestBase {
    function _getBlock() internal pure override returns (uint256) {
        return 22382193; // April 30, 2025
    }
}

contract MainnetControllerRedeemBUIDLFailureTests is MainnetControllerBUIDLTestBase {

    address admin = 0x5072Ed40EBa6bE38C2370cAD1Cb1df0202924e53;

    IWhitelistLike whitelist = IWhitelistLike(0xf8e91Fa34311876302D36D14B4F246044FD4332a);

    IBuidlLike buidl = IBuidlLike(0x6a9DA2D710BB9B700acde7Cb81F10F1fF8C89041);
    
    function test_swapDSTokenFacility_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapDSTokenFacility(1_000_000e6);
    }

    function test_swapDSTokenFacility_zeroMaxAmount() external {
        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.swapDSTokenFacility(1_000_000e6);
    }

    function test_swapDSTokenFacility_rateLimitsBoundary() external {
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(
            mainnetController.LIMIT_DSTOKEN_SWAP(),
            1_000_000e6,
            uint256(1_000_000e6) / 1 days
        );
        vm.stopPrank();

        // Set up success case
        vm.startPrank(admin);
        whitelist.registerInvestor("spark-almProxy", "collisionHash");
        whitelist.addWallet(address(almProxy), "spark-almProxy");
        buidl.issueTokens(address(almProxy), 1_000_000e6);
        vm.stopPrank();

        skip(365 days);

        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapDSTokenFacility(1_000_000e6 + 1);

        mainnetController.swapDSTokenFacility(1_000_000e6);
    }

}
