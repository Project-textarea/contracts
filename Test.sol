// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract Test{
    uint256 public temp;
    function testSend(address addr) public payable{
        (bool suc,) = addr.call{value:msg.value}("a");
        require(suc, "send fail");
    }

    function testTransfer(address addr) public payable{
        (payable(addr)).transfer(msg.value);
    }
}