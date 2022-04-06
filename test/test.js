const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Token Contracts", function () {


  let lpToken;
  let ecioToken;
  let lpStaking;
  let owner;
  let addr1;
  let addr2;
  let addrs;  

  before(async function () {

    [owner, addr1, addr2, addrs] = await ethers.getSigners();

    const LPToken = await ethers.getContractFactory("ABCToken");
    lpToken = await LPToken.deploy();
    await lpToken.deployed();

    const ECIOToken = await ethers.getContractFactory("ZXCToken");
    ecioToken = await ECIOToken.deploy();
    await ecioToken.deployed();

    const LPStaking = await ethers.getContractFactory("LPStakingECIOUSD");
    lpStaking = await LPStaking.deploy();
    await lpStaking.deployed();

  });



  it("Should transfer tokens between accounts", async function () {
    await lpToken.transfer(addr1.address, 100);
    const addr1Balance = await lpToken.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(100);

    // Transfer 50 tokens from addr1 to addr2
    // We use .connect(signer) to send a transaction from another account
    await lpToken.connect(addr1).transfer(addr2.address, 50);
    const addr2Balance = await lpToken.balanceOf(addr2.address);
    expect(addr2Balance).to.equal(50);
    
  });

  

});
