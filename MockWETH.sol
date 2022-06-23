// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IWETH.sol";

contract MockWETH is ERC20, Ownable, IWETH {

    mapping(address=>uint256) public store;

    constructor() ERC20("MockWETH", "WETH") {
    }

    function deposit() public payable override{
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint wad) public override{
        require(balanceOf(msg.sender) >= wad);
        _burn(msg.sender, wad);
        (payable(msg.sender)).transfer(wad);
    }

    fallback() external payable{
        deposit();
    }

    receive() external payable{
        deposit();
    }
}