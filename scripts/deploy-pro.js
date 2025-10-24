const hre = require("hardhat");

async function main() {
  console.log("Deploying MegaETH Launch Kit Pro - Professional Level...");

  // Get the deployer account
  const [deployer, admin, operator, feeCollector, treasury] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy mock tokens for testing
  console.log("\nDeploying Mock Tokens...");
  const MockToken = await hre.ethers.getContractFactory("MockERC20");
  const mockToken = await MockToken.deploy("Test Token", "TEST", hre.ethers.utils.parseEther("1000000"));
  await mockToken.deployed();
  console.log("Mock Token deployed to:", mockToken.address);

  const governanceToken = await MockToken.deploy("Governance Token", "GOV", hre.ethers.utils.parseEther("1000000"));
  await governanceToken.deployed();
  console.log("Governance Token deployed to:", governanceToken.address);

  // Deploy Core Contracts
  console.log("\nDeploying Core Contracts...");
  
  const MegaPayPro = await hre.ethers.getContractFactory("MegaPayPro");
  const megaPayPro = await MegaPayPro.deploy(admin.address, treasury.address);
  await megaPayPro.deployed();
  console.log("MegaPayPro deployed to:", megaPayPro.address);

  const MegaCommerce = await hre.ethers.getContractFactory("MegaCommerce");
  const megaCommerce = await MegaCommerce.deploy(feeCollector.address);
  await megaCommerce.deployed();
  console.log("MegaCommerce deployed to:", megaCommerce.address);

  const MegaPayments = await hre.ethers.getContractFactory("MegaPayments");
  const megaPayments = await MegaPayments.deploy(feeCollector.address);
  await megaPayments.deployed();
  console.log("MegaPayments deployed to:", megaPayments.address);

  const MegaAttest = await hre.ethers.getContractFactory("MegaAttest");
  const megaAttest = await MegaAttest.deploy(feeCollector.address);
  await megaAttest.deployed();
  console.log("MegaAttest deployed to:", megaAttest.address);

  // Deploy Advanced Contracts
  console.log("\nDeploying Advanced Contracts...");

  const MegaGovernance = await hre.ethers.getContractFactory("MegaGovernance");
  const megaGovernance = await MegaGovernance.deploy(
    governanceToken.address,
    treasury.address, // TimelockController placeholder
    1, // voting delay
    17280, // voting period
    hre.ethers.utils.parseEther("1000") // proposal threshold
  );
  await megaGovernance.deployed();
  console.log("MegaGovernance deployed to:", megaGovernance.deployed());

  const MegaMultiSig = await hre.ethers.getContractFactory("MegaMultiSig");
  const megaMultiSig = await MegaMultiSig.deploy([admin.address, operator.address], 2);
  await megaMultiSig.deployed();
  console.log("MegaMultiSig deployed to:", megaMultiSig.address);

  const MegaAnalytics = await hre.ethers.getContractFactory("MegaAnalytics");
  const megaAnalytics = await MegaAnalytics.deploy(admin.address);
  await megaAnalytics.deployed();
  console.log("MegaAnalytics deployed to:", megaAnalytics.address);

  const MegaSubscriptions = await hre.ethers.getContractFactory("MegaSubscriptions");
  const megaSubscriptions = await MegaSubscriptions.deploy(admin.address, feeCollector.address, treasury.address);
  await megaSubscriptions.deployed();
  console.log("MegaSubscriptions deployed to:", megaSubscriptions.address);

  const MegaBridge = await hre.ethers.getContractFactory("MegaBridge");
  const megaBridge = await MegaBridge.deploy(admin.address, feeCollector.address, treasury.address);
  await megaBridge.deployed();
  console.log("MegaBridge deployed to:", megaBridge.address);

  const MegaSDK = await hre.ethers.getContractFactory("MegaSDK");
  const megaSDK = await MegaSDK.deploy(admin.address, feeCollector.address);
  await megaSDK.deployed();
  console.log("MegaSDK deployed to:", megaSDK.address);

  const MegaMonitor = await hre.ethers.getContractFactory("MegaMonitor");
  const megaMonitor = await MegaMonitor.deploy(admin.address);
  await megaMonitor.deployed();
  console.log("MegaMonitor deployed to:", megaMonitor.address);

  // Setup initial configuration
  console.log("\nSetting up initial configuration...");

  // Grant roles
  await megaPayPro.grantRole(await megaPayPro.OPERATOR_ROLE(), operator.address);
  await megaPayments.authorizeMerchant(admin.address);
  await megaAttest.authorizeAttester(admin.address);

  // Add supported tokens
  await megaCommerce.addSupportedToken(mockToken.address);
  await megaPayments.addSupportedToken(mockToken.address);
  await megaSubscriptions.addSupportedToken(mockToken.address);
  await megaBridge.addSupportedToken(mockToken.address);

  // Configure token settings
  await megaPayPro.setTokenConfig(
    mockToken.address,
    hre.ethers.utils.parseEther("0.001"), // gas price
    0, // min amount
    hre.ethers.utils.parseEther("1000"), // max amount
    hre.ethers.utils.parseEther("10000"), // daily limit
    false, // whitelist only
    100, // fee percent (1%)
    feeCollector.address
  );

  // Add supported chains for bridge
  await megaBridge.addSupportedChain(
    1, // Ethereum
    "Ethereum",
    0, // Ethereum type
    hre.ethers.constants.AddressZero, // Bridge contract placeholder
    hre.ethers.utils.parseEther("0.001"),
    hre.ethers.utils.parseEther("1000"),
    hre.ethers.utils.parseEther("10000")
  );

  await megaBridge.addSupportedChain(
    137, // Polygon
    "Polygon",
    1, // Polygon type
    hre.ethers.constants.AddressZero,
    hre.ethers.utils.parseEther("0.001"),
    hre.ethers.utils.parseEther("1000"),
    hre.ethers.utils.parseEther("10000")
  );

  // Create sample subscription plan
  await megaSubscriptions.createPlan(
    "Premium Plan",
    "Premium subscription with advanced features",
    hre.ethers.utils.parseEther("1"),
    mockToken.address,
    2, // Monthly
    1000
  );

  // Create sample API key
  await megaSDK.createAPIKey(
    "sample-key-1",
    "Sample API Key",
    "API key for testing",
    1000,
    0, // No expiration
    ["read", "write", "admin"]
  );

  // Create deployment summary
  const deploymentInfo = {
    network: hre.network.name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    admin: admin.address,
    operator: operator.address,
    feeCollector: feeCollector.address,
    treasury: treasury.address,
    tokens: {
      MockToken: mockToken.address,
      GovernanceToken: governanceToken.address
    },
    coreContracts: {
      MegaPayPro: megaPayPro.address,
      MegaCommerce: megaCommerce.address,
      MegaPayments: megaPayments.address,
      MegaAttest: megaAttest.address
    },
    advancedContracts: {
      MegaGovernance: megaGovernance.address,
      MegaMultiSig: megaMultiSig.address,
      MegaAnalytics: megaAnalytics.address,
      MegaSubscriptions: megaSubscriptions.address,
      MegaBridge: megaBridge.address,
      MegaSDK: megaSDK.address,
      MegaMonitor: megaMonitor.address
    },
    features: [
      "Multi-currency fee payments with signature verification",
      "Advanced e-commerce with subscriptions",
      "Cross-chain payment bridge",
      "Comprehensive analytics and reporting",
      "Professional SDK and API management",
      "Advanced monitoring and testing",
      "Governance and multi-signature support",
      "Rate limiting and security controls"
    ],
    timestamp: new Date().toISOString()
  };

  console.log("\n=== Professional Deployment Summary ===");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Save deployment info to file
  const fs = require('fs');
  const deploymentFile = `deployments/${hre.network.name}-pro-${Date.now()}.json`;
  fs.mkdirSync('deployments', { recursive: true });
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment info saved to: ${deploymentFile}`);

  console.log("\n✅ All Professional Level contracts deployed successfully!");
  console.log("\n🚀 MegaETH Launch Kit Pro is ready for enterprise use!");
  console.log("\n📊 Features included:");
  console.log("   • Advanced security with role-based access control");
  console.log("   • Multi-signature governance system");
  console.log("   • Cross-chain bridge integration");
  console.log("   • Comprehensive analytics and reporting");
  console.log("   • Subscription and recurring payments");
  console.log("   • Professional SDK and API management");
  console.log("   • Advanced monitoring and testing");
  console.log("   • Rate limiting and security controls");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
