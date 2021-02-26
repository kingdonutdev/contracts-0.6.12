const bre = require("@nomiclabs/buidler");
const { ethers } = bre;
const addresses = require("./contract-addresses.json").bscTestnet;

const main = async () => {
  const DogeRebaseToken = await ethers.getContractFactory("DogeRebaseToken");
  const dogeRebaseToken = await DogeRebaseToken.attach(
    addresses.dogeRebaseToken
  );

  const DogeOracle = await ethers.getContractFactory("DogeOracle");
  const targetPriceOracle = await DogeOracle.attach(
    addresses.targetPriceOracle
  );
  const tokenPriceOracle = await DogeOracle.attach(addresses.tokenPriceOracle);

  await (await targetPriceOracle.storeData("" + (1 / 11) * 10 ** 18)).wait();
  await (await tokenPriceOracle.storeData("" + 1 * 10 ** 18)).wait();

  const DogeRebaseTokenOrchestrator = await ethers.getContractFactory(
    "DogeRebaseTokenOrchestrator"
  );
  const orchestrator = await DogeRebaseTokenOrchestrator.attach(
    addresses.dogeRebaseTokenOrchestrator
  );

  const DogeRebaseTokenMonetaryPolicy = await ethers.getContractFactory(
    "DogeRebaseTokenMonetaryPolicy"
  );
  const policy = await DogeRebaseTokenMonetaryPolicy.attach(
    addresses.dogeRebaseTokenMonetaryPolicy
  );

  //console.log((await mcapOracle.getData()).toString());

  //console.log(await policy.getNextSupplyDelta());

  /*
  await (
    await dogeRebaseToken.setMonetaryPolicy(
      addresses.dogeRebaseTokenMonetaryPolicy
    )
  ).wait();
  */

  /*
  await (
    await dogeRebaseToken.setMonetaryPolicy(
      "0x1f7283bedab59e843ba6671a95417244b532c3e6"
    )
  ).wait();

  await (
    await dogeRebaseToken.rebase("1", "68378367330038843418323620418")
  ).wait();
  */

  /*
  await (
    await policy.setOrchestrator(addresses.dogeRebaseTokenOrchestrator)
  ).wait();
  */

  //console.log((await policy.getNextSupplyDelta()).toString());

  //await (await policy.setRebaseTimingParameters(1, 0, 864000)).wait();

  await (await orchestrator.rebase()).wait();
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
