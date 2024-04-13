// SPDX-License-Identifier: SEE LICENSE IN LICENSE
// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts

// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//imports

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Errors
error DecentralizedStableCoin__AmountMustBeMoreThanZero();
error DecentralizedStableCoin__BurnAmountExceedBalance();
error DecentralizedStableCoin__NotZeroAddress();

pragma solidity 0.8.22;

/**
 * @title DecentralizedStableCoin
 * @author GeorgeFalcon
 * Collateral: Exogenous (ETH & BTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This contract is meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stable coin system
 * This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the DSCEngine smart contract.
 *
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    //contract DecentralizedStableCoin 0x90193C961A926261B756D1E5bb255e67ff9498A1

    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance <= _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
