// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockTokenReturnFalse is ERC20 {

    constructor() ERC20("MockReturnFalse", "MockReturnFalse") {}

    // Overriding transfer to return false to simulate a failed transfer
    function transfer(address to, uint256 value) public override returns (bool) {
        _transfer(_msgSender(), to, value);
        return false;
    }

    // Overriding transferFrom to return false to simulate a failed transfer
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _spendAllowance(from, _msgSender(), value);
        _transfer(from, to, value);
        return false;
    }

}

contract MockTokenReturnNull {

    string public name;
    string public symbol;

    uint8 public immutable decimals;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;

    mapping(address => mapping(address => uint256)) public allowance;

    /**********************************************************************************************/
    /*** External Functions                                                                     ***/
    /**********************************************************************************************/

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name     = name_;
        symbol   = symbol_;
        decimals = decimals_;
    }

    /**********************************************************************************************/
    /*** External Functions                                                                     ***/
    /**********************************************************************************************/

    function approve(address spender_, uint256 amount_) public virtual returns (bool success_) {
        _approve(msg.sender, spender_, amount_);
        return true;
    }

    function decreaseAllowance(address spender_, uint256 subtractedAmount_)
        public virtual returns (bool success_)
    {
        _decreaseAllowance(msg.sender, spender_, subtractedAmount_);
        return true;
    }

    function increaseAllowance(address spender_, uint256 addedAmount_)
        public virtual returns (bool success_)
    {
        _approve(msg.sender, spender_, allowance[msg.sender][spender_] + addedAmount_);
        return true;
    }

    function transfer(address recipient_, uint256 amount_) public virtual {
        _transfer(msg.sender, recipient_, amount_);
    }

    function transferFrom(address owner_, address recipient_, uint256 amount_)
        public virtual
    {
        _decreaseAllowance(owner_, msg.sender, amount_);
        _transfer(owner_, recipient_, amount_);
    }

    /**********************************************************************************************/
    /*** Mock Functions                                                                         ***/
    /**********************************************************************************************/

    function mint(address account_, uint256 amount_) external virtual returns (bool success_) {
        _mint(account_, amount_);
        return true;
    }

    function burn(address account_, uint256 amount_) external virtual returns (bool success_) {
        _burn(account_, amount_);
        return true;
    }

    /**********************************************************************************************/
    /*** Internal Functions                                                                     ***/
    /**********************************************************************************************/

    function _approve(address owner_, address spender_, uint256 amount_) internal {
        allowance[owner_][spender_] = amount_;
    }

    function _burn(address owner_, uint256 amount_) internal {
        balanceOf[owner_] -= amount_;

        // Cannot underflow because a user's balance will never be larger than the total supply.
        unchecked { totalSupply -= amount_; }
    }

    function _decreaseAllowance(address owner_, address spender_, uint256 subtractedAmount_) internal {
        uint256 spenderAllowance = allowance[owner_][spender_];  // Cache to memory.

        if (spenderAllowance != type(uint256).max) {
            _approve(owner_, spender_, spenderAllowance - subtractedAmount_);
        }
    }

    function _mint(address recipient_, uint256 amount_) internal {
        totalSupply += amount_;

        // Cannot overflow because totalSupply would first overflow in the statement above.
        unchecked { balanceOf[recipient_] += amount_; }
    }

    function _transfer(address owner_, address recipient_, uint256 amount_) internal {
        balanceOf[owner_] -= amount_;

        // Cannot overflow because minting prevents overflow of totalSupply,
        // and sum of user balances == totalSupply.
        unchecked { balanceOf[recipient_] += amount_; }
    }

}
