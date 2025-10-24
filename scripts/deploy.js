const hre = require("hardhat");

async function main() {
  console.log("Deploying MegaETH Launch Kit contracts...");

  // Get the deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy MegaPay
  console.log("\nDeploying MegaPay...");
  const MegaPay = await hre.ethers.getContractFactory("MegaPay");
  const megaPay = await MegaPay.deploy(deployer.address); // Use deployer as fee collector initially
  await megaPay.deployed();
  console.log("MegaPay deployed to:", megaPay.address);

  // Deploy MegaCommerce
  console.log("\nDeploying MegaCommerce...");
  const MegaCommerce = await hre.ethers.getContractFactory("MegaCommerce");
  const megaCommerce = await MegaCommerce.deploy(deployer.address);
  await megaCommerce.deployed();
  console.log("MegaCommerce deployed to:", megaCommerce.address);

  // Deploy MegaPayments
  console.log("\nDeploying MegaPayments...");
  const MegaPayments = await hre.ethers.getContractFactory("MegaPayments");
  const megaPayments = await MegaPayments.deploy(deployer.address);
  await megaPayments.deployed();
  console.log("MegaPayments deployed to:", megaPayments.address);

  // Deploy MegaAttest
  console.log("\nDeploying MegaAttest...");
  const MegaAttest = await hre.ethers.getContractFactory("MegaAttest");
  const megaAttest = await MegaAttest.deploy(deployer.address);
  await megaAttest.deployed();
  console.log("MegaAttest deployed to:", megaAttest.address);

  // Setup initial configuration
  console.log("\nSetting up initial configuration...");

  // Add deployer as authorized merchant for MegaPayments
  await megaPayments.authorizeMerchant(deployer.address);
  console.log("Deployer authorized as merchant");

  // Add deployer as authorized attester for MegaAttest
  await megaAttest.authorizeAttester(deployer.address);
  console.log("Deployer authorized as attester");

  // Create deployment summary
  const deploymentInfo = {
    network: hre.network.name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      MegaPay: megaPay.address,
      MegaCommerce: megaCommerce.address,
      MegaPayments: megaPayments.address,
      MegaAttest: megaAttest.address
    },
    timestamp: new Date().toISOString()
  };

  console.log("\n=== Deployment Summary ===");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  // Save deployment info to file
  const fs = require('fs');
  const deploymentFile = `deployments/${hre.network.name}-${Date.now()}.json`;
  fs.mkdirSync('deployments', { recursive: true });
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment info saved to: ${deploymentFile}`);

  console.log("\n✅ All contracts deployed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
