// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import { OTCBuffer } from "src/OTCBuffer.sol";

import "./ForkTestBase.t.sol";

contract MainnetControllerOTCSwapBase is ForkTestBase {

    bytes32 LIMIT_OTC_SWAP = keccak256("LIMIT_OTC_SWAP");

    bytes32 key;

    OTCBuffer otcBuffer;

    event OTCBufferSet(
        address indexed exchange,
        address indexed newOTCBuffer,
        address indexed oldOTCBuffer
    );

    event OTCRechargeRateSet(address indexed exchange, uint256 oldRate18, uint256 newRate18);

    address exchange = makeAddr("exchange");

    function setUp() public virtual override {
        super.setUp();

        // 1. Deploy OTCBuffer
        otcBuffer = new OTCBuffer(admin);

        // We cannot set allowance now because we will be using different assets, so it will have to
        // be done separately in each test.

        // 2. Set rate limits
        // We can do that because it doesn't depend on the asset
        key 
        vm.startPrank(Ethereum.SPARK_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_TO_USDC(), 0, 0);
        
        // 3. Set maxSliipage
    }
}

contract MainnetControllerOTCSwapFailureTests is MainnetControllerOTCSwapBase {

    // set otc buffer: admin @ exchange 0 @ exchange == otcbuffer
    // set otcConfigs[ex].buffer @ emit

    // set otc recharge rate: admin @ 
    // set otcConfigs[ex].rechargeRate18 @ emit

    // 3f + 1s + 1f + 1s = 4f + 2s

    // otcSwapSend: non-relayer @ rate-limited

    // otcSwapClaim: 
}

// Mock ERC20 with variable decimals
contract ERC20 is ERC20Mock {

    uint8 immutable internal _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

}

contract MainnetControllerOTCSwapSuccessTests is MainnetControllerOTCSwapBase {

    function _otcSwapSend_returnOneAsset(uint8 decimalsSend, uint8 decimalsReturn) internal {
        // ERC20 tokenSend = new ERC20(decimalsSend);
        // ERC20 tokenReturn = new ERC20(decimalsReturn);
        //
        // // Mint some tokens to the controller
        // deal(address(tokenSend), address(almProxy), 1e6 * 10 ** decimalsSend);
        // deal(address(tokenReturn), address(exchange), 1e6 * 10 ** decimalsReturn);
        //
        // // Replace real tokens with mocks in the controller (assuming setter functions exist)
        // vm.prank(mainnetController.owner());
        // mainnetController.setTokenAddress("USDS", address(usdsMock));
        // vm.prank(mainnetController.owner());
        // mainnetController.setTokenAddress("USDC", address(usdcMock));
        //
        // _otcSwapSend(decimalsSend, decimalsReturn, 0);
    }

    function _otcSwapSend_returnTwoAssets(uint8 decimalsSend, uint8 decimalsReturn, uint8 decimalsReturn2) internal {
        // uint256 usdsBalContr = usds.balanceOf(address(mainnetController));
        // uint256 usdcBalContr = usdc.balanceOf(address(mainnetController));
        //
        // // Define swap parameters
        // uint256 swapAmount = 1000e18; // 1000 USDS
        // address recipient = makeAddr("recipient");
        //
        // // Ensure controller has sufficient USDS balance
        // deal(address(usds), address(mainnetController), swapAmount);
        //
        // // Execute OTC swap (assuming a swap function exists)
        // vm.prank(relayer);
        // mainnetController.otcSwapSend(address(usds), address(usdc), swapAmount, recipient);
        //
        // // Verify balances changed as expected
        // assertEq(usds.balanceOf(address(mainnetController)), usdsBalContr);
        // assertGt(usdc.balanceOf(recipient), 0);

        // Verify rate limits were properly enforced
        // Add rate limit checks here
    }

    function test_otcSwapSend() external {
        // Try {6, 12, 18}³:
        for (uint8 decimalsSend = 6; decimalsSend <= 18; decimalsSend += 6) {
            for (uint8 decimalsReturn = 6; decimalsReturn <= 18; decimalsReturn += 6) {
                _otcSwapSend_returnOneAsset(decimalsSend, decimalsReturn);
                for (uint8 decimalsReturn2 = 6; decimalsReturn2 <= 18; decimalsReturn2 += 6) {
                    _otcSwapSend_returnTwoAssets(decimalsSend, decimalsReturn, decimalsReturn2);
                }
            }
        }
    }
}

