// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FakeDai is ERC20 {
    constructor() ERC20("FakeDai", "fDai"){
        _mint(msg.sender, 1000000 /** 10 ** 18*/);
    }
}