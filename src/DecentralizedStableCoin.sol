// SPDX-License-Identifier: MIT
//layout of contract
// version
pragma solidity ^0.8.24;

// imports
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// errors
// interfaces libraries, contracts
library DecentralizedStableCoin__Errors {
    error MustBeGreaterThanZero();
    error InputAmountExceedsBalance();
    error ZeroAddressTransfer();
}

// type declarations
// state variables
// events
// modifiers
// functions

// Layout of functions
// constructor
// receive function
// fallback function
// external functions
// public functions
// internal functions
// private functions
// pure functions view functions

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("PKR Stable Coin", "PKR") Ownable(msg.sender) {
        // mint 1000 PKR to the owner
        // _mint(msg.sender, 9000 * 10 ** decimals());
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        // check if the amount to burn is less than or equal to the balance
        if (_amount <= 0) {
            revert DecentralizedStableCoin__Errors.MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__Errors.InputAmountExceedsBalance();
        }
        // burn the _amount of PKR
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__Errors.ZeroAddressTransfer();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__Errors.MustBeGreaterThanZero();
        }

        // mint the amount of PKR to the address
        _mint(_to, _amount);
        return true;
    }
}
