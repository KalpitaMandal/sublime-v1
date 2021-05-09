const Web3 = require("web3");
const fs = require("fs");
const allConfigs = require("../config/config.json");
const keystore = require("../../keystore/keystore.json");

const proxyCompiled = require("../artifacts/contracts/Proxy.sol/SublimeProxy.json");

const aaveYieldCompiled = require("../build/contracts/yield/AaveYield.sol/AaveYield.json");
const compoundYieldCompiled = require("../build/contracts/yield/CompoundYield.sol/CompoundYield.json");
const yearnYieldCompiled = require("../build/contracts/yield/YearnYield.sol/YearnYield.json");
const strategyRegistryCompiled = require("../build/contracts/yield/StrategyRegistry.sol/StrategyRegistry.json");
const savingsAccountCompiled = require("../build/contracts/SavingsAccount/SavingsAccount.sol/SavingsAccount.json");
const priceOracleCompiled = require("../build/contracts/PriceOracle.sol/PriceOracle.json");
const verificationCompiled = require("../build/contracts/Verification/Verification.sol/Verification.json");
const repaymentsCompiled = require("../build/contracts/Repayments/Repayments.sol/Repayments.json");
const extensionCompiled = require("../build/contracts/Pool/Extension.sol/Extension.json");
const poolFactoryCompiled = require("../build/contracts/Pool/PoolFactory.sol/PoolFactory.json");
const creditLinesCompiled = require("../build/contracts/CreditLine/CreditLine.sol/CreditLine.json");
const poolCompiled = require("../build/contracts/Pool/Pool.sol/Pool.json");
const poolTokenCompiled = require("../build/contracts/Pool/PoolToken.sol/PoolToken.json");

const utils = require("./utils");

const config = allConfigs[allConfigs.network];

let web3 = new Web3(config.blockchain.url);

const proxyAdmin = config.actors.proxyAdmin;
const admin = config.actors.admin;
const deployer = config.actors.deployer;

const deploymentConfig = {
  from: deployer,
  gas: config.tx.gas,
  gasPrice: config.tx.gasPrice,
};

const adminDeploymentConfig = {
    from: admin,
    gas: config.tx.gas,
    gasPrice: config.tx.gasPrice
}

const addAccounts = async (web3, keystore) => {
    for (let account in keystore) {
        await web3.eth.accounts.wallet.add(keystore[account]);
    }
    return web3;
}

const deploy = async (web3) => {
    // deploy strategy Registry
    const strategyRegistryInitParams = [admin, config.strategies.max];
    const strategyRegistry = await utils.deployWithProxy(web3, strategyRegistryCompiled.abi, strategyRegistryCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, strategyRegistryInitParams, proxyAdmin, deploymentConfig);

    // deploy Creditlines
    const creditLinesInitParams = [admin];
    const creditLines = await utils.deployWithProxy(web3, creditLinesCompiled.abi, creditLinesCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, creditLinesInitParams, proxyAdmin, deploymentConfig);

    // deploy savingsAccount
    const savingsAccountInitParams = [admin, strategyRegistry.options.address, creditLines.options.address];
    const savingsAccount = await utils.deployWithProxy(web3, savingsAccountCompiled.abi, savingsAccountCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, savingsAccountInitParams, proxyAdmin, deploymentConfig);

    // deploy strategies
    const aaveYieldInitParams = [admin, savingsAccount.options.address, config.strategies.aave.wethGateway, config.strategies.aave.protocolDataProvider, config.strategies.aave.lendingPoolAddressesProvider];
    const aaveYield = await utils.deployWithProxy(web3, aaveYieldCompiled.abi, aaveYieldCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, aaveYieldInitParams, proxyAdmin, deploymentConfig);
    const compoundYieldInitParams = [admin, savingsAccount.options.address];
    const compoundYield = await utils.deployWithProxy(web3, compoundYieldCompiled.abi, compoundYieldCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, compoundYieldInitParams, proxyAdmin, deploymentConfig);
    const yearnYieldInitParams = [admin, savingsAccount.options.address];
    const yearnYield = await utils.deployWithProxy(web3, yearnYieldCompiled.abi, yearnYieldCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, yearnYieldInitParams, proxyAdmin, deploymentConfig);

    // add deployed strategies to registry
    await strategyRegistry.methods.addStrategy(aaveYield.options.address).send(adminDeploymentConfig).then(console.log);
    await strategyRegistry.methods.addStrategy(compoundYield.options.address).send(adminDeploymentConfig).then(console.log);
    await strategyRegistry.methods.addStrategy(yearnYield.options.address).send(adminDeploymentConfig).then(console.log);

    // deploy priceOracle - update it first
    const priceOracleInitParams = [admin];
    const priceOracle = await utils.deployWithProxy(web3, priceOracleCompiled.abi, priceOracleCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, priceOracleInitParams, proxyAdmin, deploymentConfig);
    // TODO add price oracles

    // deploy verification
    const verificationInitParams = [config.actors.verifier];
    const verification = await utils.deployWithProxy(web3, verificationCompiled.abi, verificationCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, verificationInitParams, proxyAdmin, deploymentConfig);

    // deploy poolFactory
    const poolFactory = await utils.deployWithProxy(web3, poolFactoryCompiled.abi, poolFactoryCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, null, proxyAdmin, deploymentConfig);

    // deploy Repayments
    const repaymentsInitParams = [admin, poolFactory.options.address, config.repayments.votingPassRatio, savingsAccount.options.address];
    const repayments = await utils.deployWithProxy(web3, repaymentsCompiled.abi, repaymentsCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, repaymentsInitParams, proxyAdmin, deploymentConfig);

    // deploy Extension
    const extensionInitParams = [poolFactory.options.address];
    const extension = await utils.deployWithProxy(web3, extensionCompiled.abi, extensionCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, extensionInitParams, proxyAdmin, deploymentConfig);

    const pool = await utils.deployContract(web3, poolCompiled.abi, poolCompiled.bytecode, [], deploymentConfig);

    // initialize PoolFactory
    const poolFactoryInitParams = [
        pool,
        verification.options.address,
        strategyRegistry.options.address,
        admin,
        config.pool.collectionPeriod,
        config.pool.matchCollateralRatioInterval,
        config.pool.marginCallDuration,
        config.pool.collateralVolatilityThreshold,
        config.pool.gracePeriodPenaltyFraction,
        web3.eth.abi.encodeFunctionSignature(utils.getInitializeABI(poolCompiled.abi)),
        config.pool.liquidatorRewardFraction,
        repayments.options.address,
        priceOracle.options.address,
        savingsAccount.options.address,
        extension.options.address
    ];
    await poolFactory.methods.initialize.apply(null, poolFactoryInitParams).send(deploymentConfig);

    const poolToken = await utils.deployContract(web3, poolTokenCompiled.abi, poolTokenCompiled.bytecode, [], deploymentConfig);

    const addresses = {
        "strategyRegistry": strategyRegistry.options.address,
        "savingsAccount": savingsAccount.options.address,
        "aaveYield": aaveYield.options.address,
        "compoundYield": compoundYield.options.address,
        "yearnYield": yearnYield.options.address,
        "priceOracle": priceOracle.options.address,
        "verification": verification.options.address,
        "poolFactory": poolFactory.options.address,
        "repayments": repayments.options.address,
        "extension": extension.options.address,
        "pool": pool,
        "creditLines": creditLines.options.address,
        "poolToken": poolToken
    }
    console.table(addresses);
}

addAccounts(web3, keystore).then(deploy);
// deploy(web3);
