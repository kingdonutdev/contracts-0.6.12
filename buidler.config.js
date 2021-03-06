require("dotenv").config();
usePlugin("@nomiclabs/buidler-waffle");
usePlugin("@nomiclabs/buidler-ethers");
usePlugin("@nomiclabs/buidler-web3");
usePlugin("@openzeppelin/buidler-upgrades");

// This is a sample Buidler task. To learn how to create your own go to
// https://buidler.dev/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});

// You have to export an object to set up your config
// This object can have the following optional entries:
// defaultNetwork, networks, solc, and paths.
// Go to https://buidler.dev/config/ to learn more
module.exports = {
  //defaultNetwork: "goerli",
  networks: {
    local: {
      url: "http://localhost:8545",
    },
    goerli: {
      url: process.env.GOERLI_URL,
      accounts: [process.env.GOERLI_PRIVATE_KEY],
    },
    bscTestnet: {
      url: process.env.BINANCE_TESTNET_URL,
      accounts: [process.env.BINANCE_TESTNET_PRIVATE_KEY],
    },
    bsc: {
      url: process.env.BSC_URL,
      accounts: [process.env.BSC_PRIVATE_KEY],
    },
  },
  solc: {
    version: "0.6.12",
  },
  paths: {
    tests: "./test/unit",
  },
};
