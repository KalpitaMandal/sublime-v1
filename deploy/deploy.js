const Web3 = require('web3');
const allConfigs = require("../config/config.json");

const proxyCompiled = require("../build/contracts/SublimeProxy.json");

const aaveYieldCompiled = require("../build/contracts/AaveYield.json");
const compoundYieldCompiled = require("../build/contracts/CompoundYield.json");
const yearnYieldCompiled = require("../build/contracts/YearnYield.json");
const strategyRegistryCompiled = require("../build/contracts/StrategyRegistry.json");
const savingsAccountCompiled = require("../build/contracts/SavingsAccount.json");
const priceOracleCompiled = require("../build/contracts/PriceOracle.json");
const verificationCompiled = require("../build/contracts/Verification.json");
const repaymentsCompiled = require("../build/contracts/Repayments.json");
const extensionCompiled = require("../build/contracts/Extension.json");
const poolFactoryCompiled = require("../build/contracts/PoolFactory.json");
const creditLinesCompiled = require("../build/contracts/CreditLine.json");
const poolCompiled = require("../build/contracts/Pool.json");

const utils = require("./utils");

const config = allConfigs[allConfigs.network];

const web3 = new Web3(config.blockchain.url);

const proxyAdmin = config.actors.proxyAdmin;
const admin = config.actors.admin;
const deployer = config.actors.deployer;

const deploymentConfig = {
    from: deployer,
    gas: config.tx.gas,
    gasPrice: config.tx.gasPrice
};

const adminDeploymentConfig  = {
    from: admin,
    gas: config.tx.gas,
    gasPrice: config.tx.gasPrice
}

const deploy = async (web3) => {
    // deploy strategy Registry
    const strategyRegistryInitParams = [admin, config.strategies.max];  
    const strategyRegistry = await utils.deployWithProxy(strategyRegistryCompiled.abi, strategyRegistryCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, strategyRegistryInitParams, proxyAdmin, deploymentConfig);

    // deploy savingsAccount
    const savingsAccountInitParams =  [admin, strategyRegistry.options.address];
    const savingsAccount = await utils.deployWithProxy(savingsAccountCompiled.abi, savingsAccountCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, savingsAccountInitParams, proxyAdmin, deploymentConfig);

    // deploy strategies
    const aaveYieldInitParams = [admin, savingsAccount.options.address, config.strategies.aave.wethGateway, config.strategies.aave.protocolDataProvider, config.strategies.aave.lendingPoolAddressesProvider];
    const aaveYield = await utils.deployWithProxy(aaveYieldCompiled.abi, aaveYieldCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, aaveYieldInitParams, proxyAdmin, deploymentConfig);
    const compoundYieldInitParams = [admin, savingsAccount.options.address];
    const compoundYield = await utils.deployWithProxy(compoundYieldCompiled.abi, compoundYieldCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, compoundYieldInitParams, proxyAdmin, deploymentConfig);
    const yearnYieldInitParams = [admin, savingsAccount.options.address];
    const yearnYield = await utils.deployWithProxy(yearnYieldCompiled.abi, yearnYieldCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, yearnYieldInitParams, proxyAdmin, deploymentConfig);
    
    // add deployed strategies to registry
    await strategyRegistry.methods.addStrategy(aaveYield.options.address).send(adminDeploymentConfig);
    await strategyRegistry.methods.addStrategy(compoundYield.options.address).send(adminDeploymentConfig);
    await strategyRegistry.methods.addStrategy(yearnYield.options.address).send(adminDeploymentConfig);

    // deploy priceOracle - update it first
    // TODO - Update the contract and then add init params
    const priceOracleInitParams =  [];
    const priceOracle = await utils.deployWithProxy(priceOracleCompiled.abi, priceOracleCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, priceOracleInitParams, proxyAdmin, deploymentConfig);

    // deploy verification
    const verificationInitParams =  [config.actors.verifier];
    const verification = await utils.deployWithProxy(verificationCompiled.abi, verificationCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, verificationInitParams, proxyAdmin, deploymentConfig);

    // deploy poolFactory
    const poolFactory = await utils.deployWithProxy(poolFactoryCompiled.abi, poolFactoryCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, null, proxyAdmin, deploymentConfig);
    
    // deploy Repayments
    // TODO: Add owner to repayments
    const repaymentsInitParams = [admin, poolFactory.options.address, config.repayments.votingExtensionlength, config.repayments.votingPassRatio];
    const repayments = await utils.deployWithProxy(repaymentsCompiled.abi, repaymentsCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, repaymentsInitParams, proxyAdmin, deploymentConfig);
    
    // deploy Extension
    const extensionInitParams =  [poolFactory.options.address];
    const extension = await utils.deployWithProxy(extensionCompiled.abi, extensionCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, extensionInitParams, proxyAdmin, deploymentConfig);

    const pool = await utils.deployContract(web3, poolCompiled.abi, poolCompiled.bytecode, [], deploymentConfig);
    
    // initialize PoolFactory
    const poolFactoryInitParams =  [
        pool.options.address, 
        verification.options.address,
        strategyRegistry.options.address,
        admin,
        config.pool.collectionPeriod,
        config.pool.matchCollateralRatioInterval,
        config.pool.marginCallDuration,
        config.pool.collateralVolatilityThreshold,
        config.pool.gracePeriodPenaltyFraction,
        web3.eth.abi.encodeFunctionSignature(poolCompiled.abi.initialize),
        config.pool.liquidatorRewardFraction,
        repayments.options.address,
        priceOracle.options.address,
        savingsAccount.options.address,
        extension.options.address
    ];
    await poolFactory.methods.initialize.apply(null, poolFactoryInitParams).send(deploymentConfig);
    
    // deploy Creditlines
    const creditLinesInitParams = [admin];
    const creditLines = await utils.deployWithProxy(creditLinesCompiled.abi, creditLinesCompiled.bytecode, proxyCompiled.abi, proxyCompiled.bytecode, creditLinesInitParams, proxyAdmin, deploymentConfig);
}

deploy(web3);