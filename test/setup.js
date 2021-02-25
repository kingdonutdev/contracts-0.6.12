const bre = require("@nomiclabs/buidler");
const { ethers, web3, upgrades } = bre;
const BigNumber = ethers.BigNumber;
const BN = require("bn.js");
const chai = require("chai");
const expect = chai.expect;

if (typeof before !== "undefined") {
  before(setupChai);
} else {
  setupChai();
}

function setupChai() {
  chai
    .use(require("chai-bignumber")(BigNumber))
    .use(require("chai-as-promised"))
    .use(require("bn-chai")(BN))
    .should();
}

async function isEthException(promise) {
  let msg = "No Exception";
  try {
    let x = await promise;
    // if (!!x.wait) {
    //     await x.wait()
    // }
  } catch (e) {
    msg = e.message;
  }
  return (
    msg.includes("Transaction reverted") ||
    msg.includes("VM Exception while processing transaction: revert") ||
    msg.includes("invalid opcode") ||
    msg.includes("exited with an error (status 0)")
  );
}

async function awaitTx(tx) {
  return await (await tx).wait();
}

async function waitForSomeTime(provider, seconds) {
  await provider.send("evm_increaseTime", [seconds]);
}

async function currentTime(provider) {
  const block = await provider.send("eth_getBlockByNumber", ["latest", false]);
  return parseInt(block.timestamp, 16);
}

const DECIMALS = 9;

function toBASEDenomination(x) {
  return BigNumber.from(x).mul(10 ** DECIMALS);
}

module.exports = {
  ethers,
  web3,
  upgrades,
  expect,
  BigNumber,
  isEthException,
  awaitTx,
  waitForSomeTime,
  currentTime,
  toBASEDenomination,
  DECIMALS,
};
