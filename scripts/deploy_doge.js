const bre = require("@nomiclabs/buidler");
const { ethers, upgrades } = bre;
const { getSavedContractAddresses, saveContractAddress } = require("./utils");

async function main() {
  await bre.run("compile");

  const DogeOracle = await ethers.getContractFactory("DogeOracle");

  const mcapOracle = await DogeOracle.deploy("Market Cap Oracle");
  await mcapOracle.deployed();
  console.log("Market cap oracle deployed to:", mcapOracle.address);
  saveContractAddress(bre.network.name, "mcapOracle", mcapOracle.address);

  const tokenPriceOracle = await DogeOracle.deploy("Token Price Oracle");
  await tokenPriceOracle.deployed();
  console.log("Token price oracle deployed to:", tokenPriceOracle.address);
  saveContractAddress(
    bre.network.name,
    "tokenPriceOracle",
    tokenPriceOracle.address
  );

  const DogeRebaseToken = await ethers.getContractFactory("DogeRebaseToken");
  const dogeRebaseToken = await upgrades.deployProxy(DogeRebaseToken, []);
  await dogeRebaseToken.deployed();
  console.log("DogeRebaseToken deployed to:", dogeRebaseToken.address);
  saveContractAddress(
    bre.network.name,
    "dogeRebaseToken",
    dogeRebaseToken.address
  );

  const DogeRebaseTokenMonetaryPolicy = await ethers.getContractFactory(
    "DogeRebaseTokenMonetaryPolicy"
  );
  const dogeRebaseTokenMonetaryPolicy = await upgrades.deployProxy(
    DogeRebaseTokenMonetaryPolicy,
    [dogeRebaseToken.address]
  );
  await dogeRebaseTokenMonetaryPolicy.deployed();
  console.log(
    "DogeRebaseTokenMonetaryPolicy deployed to:",
    dogeRebaseTokenMonetaryPolicy.address
  );
  saveContractAddress(
    bre.network.name,
    "dogeRebaseTokenMonetaryPolicy",
    dogeRebaseTokenMonetaryPolicy.address
  );

  await (
    await dogeRebaseTokenMonetaryPolicy.setMcapOracle(mcapOracle.address)
  ).wait();
  await (
    await dogeRebaseTokenMonetaryPolicy.setTokenPriceOracle(
      tokenPriceOracle.address
    )
  ).wait();

  await (
    await dogeRebaseToken.setMonetaryPolicy(
      dogeRebaseTokenMonetaryPolicy.address
    )
  ).wait();

  const DogeRebaseTokenOrchestrator = await ethers.getContractFactory(
    "DogeRebaseTokenOrchestrator"
  );
  const dogeRebaseTokenOrchestrator = await upgrades.deployProxy(
    DogeRebaseTokenOrchestrator,
    [dogeRebaseTokenMonetaryPolicy.address]
  );
  await dogeRebaseTokenOrchestrator.deployed();
  console.log(
    "DogeRebaseTokenOrchestrator deployed to:",
    dogeRebaseTokenOrchestrator.address
  );
  saveContractAddress(
    bre.network.name,
    "dogeRebaseTokenOrchestrator",
    dogeRebaseTokenOrchestrator.address
  );

  await (
    await dogeRebaseTokenMonetaryPolicy.setOrchestrator(
      dogeRebaseTokenOrchestrator.address
    )
  ).wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
