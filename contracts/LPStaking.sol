//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

interface LKMIERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}


contract LPStaking is Ownable{
   using Counters for Counters.Counter;

   uint128 stakingFee = 0.005 ether;

   address public lpTokenAddress;

   function initialize() public {
       lpTokenAddress = 0x97d6864A34D051914894973Af56DCF0B10d26060;
   }

   function updateLPAddress(address lpAddress) public onlyOwner{
      lpTokenAddress = lpAddress;
   }

    


   



}
