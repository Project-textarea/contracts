// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MintSharingSystem.sol";
import "./interface/IWETH.sol";

contract MineCollector is Ownable {
    // lib
    using SafeERC20 for IWETH;

    // struct

    // constant

    // storage
    IWETH public wethAddress;
    MintSharingSystem public mintSharingSystemAddress;
    uint256 public maxTime = 1 days;
    uint256 public startBlock;
    uint256 public startTime;

    constructor(address _wethAddress, address _mintSharingSystemAddress){
        wethAddress = IWETH(_wethAddress);
        mintSharingSystemAddress = MintSharingSystem(_mintSharingSystemAddress);
    }

    function deposit() public payable{
        require(msg.value > 0, "value must > 0");

        if (startBlock == 0){
            startBlock = block.number;
            startTime = block.timestamp;
        }

        if (block.timestamp - startTime >= maxTime){
            uint256 diffBlock = block.number - startBlock;
            startBlock = block.number;
            startTime = block.timestamp;

            uint256 amount = (address(this)).balance;
            wethAddress.deposit{value:amount}();
            wethAddress.safeTransfer(address(mintSharingSystemAddress), amount);
            mintSharingSystemAddress.updateRewards(amount, diffBlock);
        }
    }

    function setMaxTime(uint256 time) public onlyOwner{
        maxTime = time;
    }

    fallback() external payable{
        deposit();
    }

    receive() external payable{
        deposit();
    }
}