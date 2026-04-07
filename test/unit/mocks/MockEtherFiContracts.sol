// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

contract MockWEETH {

    address public eETH;

    function __setEETH(address eETH_) external {
        eETH = eETH_;
    }

}

contract MockEETH {

    address public liquidityPool;

    constructor(address liquidityPool_) {
        liquidityPool = liquidityPool_;
    }

}

contract MockLiquidityPool {

    address public withdrawRequestNFT;

    constructor(address withdrawRequestNFT_) {
        withdrawRequestNFT = withdrawRequestNFT_;
    }

}

contract MockWithdrawRequestNFT {

    mapping(uint256 => bool) public isValid;
    mapping(uint256 => bool) public isFinalized;

    function __setIsValid(uint256 requestId, bool value) external {
        isValid[requestId] = value;
    }

    function __setIsFinalized(uint256 requestId, bool value) external {
        isFinalized[requestId] = value;
    }

    function claimWithdraw(uint256) external {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "MockWithdrawRequestNFT/claimWithdraw-failed");
    }

}

contract MockWETH {

    mapping(address => uint256) public balanceOf;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

}
