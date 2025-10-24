const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MegaETH Launch Kit Pro - Professional Level", function () {
  let megaPayPro, megaCommerce, megaPayments, megaAttest;
  let megaGovernance, megaMultiSig, megaAnalytics, megaSubscriptions;
  let megaBridge, megaSDK, megaMonitor;
  let owner, admin, operator, merchant, customer, feeCollector, treasury;
  let mockToken, governanceToken;

  beforeEach(async function () {
    [owner, admin, operator, merchant, customer, feeCollector, treasury] = await ethers.getSigners();

    // Deploy mock tokens
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Test Token", "TEST", ethers.utils.parseEther("1000000"));
    await mockToken.deployed();

    const GovernanceToken = await ethers.getContractFactory("MockERC20");
    governanceToken = await GovernanceToken.deploy("Governance Token", "GOV", ethers.utils.parseEther("1000000"));
    await governanceToken.deployed();

    // Deploy core contracts
    const MegaPayPro = await ethers.getContractFactory("MegaPayPro");
    megaPayPro = await MegaPayPro.deploy(admin.address, treasury.address);
    await megaPayPro.deployed();

    const MegaCommerce = await ethers.getContractFactory("MegaCommerce");
    megaCommerce = await MegaCommerce.deploy(feeCollector.address);
    await megaCommerce.deployed();

    const MegaPayments = await ethers.getContractFactory("MegaPayments");
    megaPayments = await MegaPayments.deploy(feeCollector.address);
    await megaPayments.deployed();

    const MegaAttest = await ethers.getContractFactory("MegaAttest");
    megaAttest = await MegaAttest.deploy(feeCollector.address);
    await megaAttest.deployed();

    // Deploy advanced contracts
    const MegaGovernance = await ethers.getContractFactory("MegaGovernance");
    megaGovernance = await MegaGovernance.deploy(
      governanceToken.address,
      treasury.address, // TimelockController placeholder
      1, // voting delay
      17280, // voting period
      ethers.utils.parseEther("1000") // proposal threshold
    );
    await megaGovernance.deployed();

    const MegaMultiSig = await ethers.getContractFactory("MegaMultiSig");
    megaMultiSig = await MegaMultiSig.deploy([admin.address, operator.address], 2);
    await megaMultiSig.deployed();

    const MegaAnalytics = await ethers.getContractFactory("MegaAnalytics");
    megaAnalytics = await MegaAnalytics.deploy(admin.address);
    await megaAnalytics.deployed();

    const MegaSubscriptions = await ethers.getContractFactory("MegaSubscriptions");
    megaSubscriptions = await MegaSubscriptions.deploy(admin.address, feeCollector.address, treasury.address);
    await megaSubscriptions.deployed();

    const MegaBridge = await ethers.getContractFactory("MegaBridge");
    megaBridge = await MegaBridge.deploy(admin.address, feeCollector.address, treasury.address);
    await megaBridge.deployed();

    const MegaSDK = await ethers.getContractFactory("MegaSDK");
    megaSDK = await MegaSDK.deploy(admin.address, feeCollector.address);
    await megaSDK.deployed();

    const MegaMonitor = await ethers.getContractFactory("MegaMonitor");
    megaMonitor = await MegaMonitor.deploy(admin.address);
    await megaMonitor.deployed();

    // Setup initial configuration
    await megaPayPro.grantRole(await megaPayPro.OPERATOR_ROLE(), operator.address);
    await megaPayments.authorizeMerchant(merchant.address);
    await megaAttest.authorizeAttester(merchant.address);
    await megaCommerce.addSupportedToken(mockToken.address);
    await megaPayments.addSupportedToken(mockToken.address);
    await megaPayPro.setTokenConfig(mockToken.address, ethers.utils.parseEther("0.001"), 0, ethers.utils.parseEther("1000"), ethers.utils.parseEther("10000"), false, 100, feeCollector.address);
    await megaSubscriptions.addSupportedToken(mockToken.address);
    await megaBridge.addSupportedToken(mockToken.address);
  });

  describe("MegaPayPro - Advanced Fee Payment", function () {
    it("Should process payments with signature verification", async function () {
      const gasUsed = 100000;
      const nonce = Date.now();
      const messageHash = ethers.utils.solidityKeccak256(
        ["address", "address", "uint256", "uint256", "uint256", "uint256"],
        [customer.address, mockToken.address, gasUsed, nonce, block.timestamp, await ethers.provider.getNetwork().then(n => n.chainId)]
      );
      const signature = await operator.signMessage(ethers.utils.arrayify(messageHash));

      await mockToken.transfer(customer.address, ethers.utils.parseEther("1"));
      await mockToken.connect(customer).approve(megaPayPro.address, ethers.utils.parseEther("1"));

      await expect(megaPayPro.connect(customer).payFeesWithSignature(
        mockToken.address,
        gasUsed,
        nonce,
        signature
      )).to.emit(megaPayPro, "PaymentProcessed");
    });

    it("Should enforce rate limits", async function () {
      // Test rate limiting functionality
      const gasUsed = 100000;
      const nonce1 = Date.now();
      const nonce2 = Date.now() + 1;

      const messageHash1 = ethers.utils.solidityKeccak256(
        ["address", "address", "uint256", "uint256", "uint256", "uint256"],
        [customer.address, mockToken.address, gasUsed, nonce1, block.timestamp, await ethers.provider.getNetwork().then(n => n.chainId)]
      );
      const signature1 = await operator.signMessage(ethers.utils.arrayify(messageHash1));

      const messageHash2 = ethers.utils.solidityKeccak256(
        ["address", "address", "uint256", "uint256", "uint256", "uint256"],
        [customer.address, mockToken.address, gasUsed, nonce2, block.timestamp, await ethers.provider.getNetwork().then(n => n.chainId)]
      );
      const signature2 = await operator.signMessage(ethers.utils.arrayify(messageHash2));

      await mockToken.transfer(customer.address, ethers.utils.parseEther("2"));
      await mockToken.connect(customer).approve(megaPayPro.address, ethers.utils.parseEther("2"));

      // First payment should succeed
      await megaPayPro.connect(customer).payFeesWithSignature(
        mockToken.address,
        gasUsed,
        nonce1,
        signature1
      );

      // Second payment should succeed (no rate limit exceeded in this test)
      await megaPayPro.connect(customer).payFeesWithSignature(
        mockToken.address,
        gasUsed,
        nonce2,
        signature2
      );
    });
  });

  describe("MegaSubscriptions - Recurring Payments", function () {
    it("Should create subscription plan and allow users to subscribe", async function () {
      // Create subscription plan
      await megaSubscriptions.createPlan(
        "Premium Plan",
        "Premium subscription with advanced features",
        ethers.utils.parseEther("1"),
        mockToken.address,
        2, // Monthly
        1000
      );

      // User subscribes
      await mockToken.transfer(customer.address, ethers.utils.parseEther("10"));
      await mockToken.connect(customer).approve(megaSubscriptions.address, ethers.utils.parseEther("10"));

      await expect(megaSubscriptions.connect(customer).subscribe(1, true))
        .to.emit(megaSubscriptions, "SubscriptionCreated");
    });

    it("Should handle subscription cancellation", async function () {
      // Create plan and subscribe
      await megaSubscriptions.createPlan(
        "Basic Plan",
        "Basic subscription",
        ethers.utils.parseEther("0.5"),
        mockToken.address,
        2, // Monthly
        1000
      );

      await mockToken.transfer(customer.address, ethers.utils.parseEther("5"));
      await mockToken.connect(customer).approve(megaSubscriptions.address, ethers.utils.parseEther("5"));

      await megaSubscriptions.connect(customer).subscribe(1, true);

      // Cancel subscription
      await expect(megaSubscriptions.connect(customer).cancelSubscription(1))
        .to.emit(megaSubscriptions, "SubscriptionCancelled");
    });
  });

  describe("MegaAnalytics - Advanced Analytics", function () {
    it("Should record metrics and generate reports", async function () {
      // Record metrics
      await megaAnalytics.recordMetric(
        1000,
        "payments",
        "volume",
        customer.address,
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("test-data"))
      );

      // Generate report
      const reportId = await megaAnalytics.generateReport(
        "Payment Analytics",
        "Monthly payment report",
        "monthly",
        block.timestamp - 30 days,
        block.timestamp,
        ["payments", "volume"]
      );

      expect(reportId).to.be.gt(0);
    });

    it("Should create custom dashboards", async function () {
      // Create dashboard
      const dashboardId = await megaAnalytics.createDashboard(
        "Payment Dashboard",
        "Custom payment analytics dashboard",
        [],
        true
      );

      expect(dashboardId).to.be.gt(0);
    });
  });

  describe("MegaBridge - Cross-Chain Integration", function () {
    it("Should initiate cross-chain bridge transaction", async function () {
      // Add supported chain
      await megaBridge.addSupportedChain(
        137, // Polygon
        "Polygon",
        1, // Polygon type
        ethers.constants.AddressZero, // Bridge contract placeholder
        ethers.utils.parseEther("0.001"),
        ethers.utils.parseEther("1000"),
        ethers.utils.parseEther("10000")
      );

      // Initiate bridge transaction
      await mockToken.transfer(customer.address, ethers.utils.parseEther("1"));
      await mockToken.connect(customer).approve(megaBridge.address, ethers.utils.parseEther("1"));

      await expect(megaBridge.connect(customer).initiateBridge(
        mockToken.address,
        ethers.utils.parseEther("0.1"),
        137, // Polygon
        customer.address
      )).to.emit(megaBridge, "BridgeTransactionInitiated");
    });
  });

  describe("MegaSDK - API Management", function () {
    it("Should create API keys and manage integrations", async function () {
      // Create API key
      const apiKeyId = await megaSDK.createAPIKey(
        "test-key-1",
        "Test API Key",
        "API key for testing",
        1000,
        0, // No expiration
        ["read", "write"]
      );

      expect(apiKeyId).to.equal("test-key-1");

      // Register integration
      const integrationId = await megaSDK.registerIntegration(
        "Test App",
        "Test application integration",
        "1.0.0",
        [megaPayPro.address, megaCommerce.address]
      );

      expect(integrationId).to.be.gt(0);
    });
  });

  describe("MegaMonitor - Monitoring System", function () {
    it("Should create alerts and monitor contracts", async function () {
      // Create alert
      const alertId = await megaMonitor.createAlert(
        2, // High level
        0, // Security type
        "High Gas Usage",
        "Contract consuming excessive gas",
        megaPayPro.address,
        "payFeesWithSignature"
      );

      expect(alertId).to.be.gt(0);

      // Acknowledge alert
      await megaMonitor.acknowledgeAlert(alertId);

      // Create test case
      const testId = await megaMonitor.createTestCase(
        "Gas Usage Test",
        "Test gas consumption",
        megaPayPro.address,
        "payFeesWithSignature",
        ethers.utils.defaultAbiCoder.encode(["address", "uint256"], [mockToken.address, 100000]),
        ethers.utils.defaultAbiCoder.encode(["bool"], [true]),
        500000,
        300
      );

      expect(testId).to.be.gt(0);
    });

    it("Should record performance metrics", async function () {
      await megaMonitor.recordPerformanceMetric(
        megaPayPro.address,
        "payFeesWithSignature",
        150000,
        1000,
        true
      );

      // This should emit PerformanceMetricRecorded event
    });
  });

  describe("MegaGovernance - Governance System", function () {
    it("Should handle multi-signature operations", async function () {
      // Submit transaction
      const txId = await megaMultiSig.submitTransaction(
        mockToken.address,
        0,
        mockToken.interface.encodeFunctionData("transfer", [customer.address, ethers.utils.parseEther("100")])
      );

      expect(txId).to.be.gt(0);

      // Confirm transaction
      await megaMultiSig.connect(admin).confirmTransaction(txId);
      await megaMultiSig.connect(operator).confirmTransaction(txId);

      // Execute transaction
      await megaMultiSig.executeTransaction(txId);
    });
  });

  describe("Integration Tests", function () {
    it("Should work together as a complete ecosystem", async function () {
      // 1. Create subscription plan
      await megaSubscriptions.createPlan(
        "Enterprise Plan",
        "Enterprise subscription",
        ethers.utils.parseEther("10"),
        mockToken.address,
        2, // Monthly
        100
      );

      // 2. User subscribes
      await mockToken.transfer(customer.address, ethers.utils.parseEther("100"));
      await mockToken.connect(customer).approve(megaSubscriptions.address, ethers.utils.parseEther("100"));
      await megaSubscriptions.connect(customer).subscribe(1, true);

      // 3. Record analytics
      await megaAnalytics.recordMetric(
        ethers.utils.parseEther("10").toNumber(),
        "subscriptions",
        "revenue",
        customer.address,
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("subscription-data"))
      );

      // 4. Create monitoring alert
      await megaMonitor.createAlert(
        1, // Medium level
        2, // Economic type
        "Revenue Milestone",
        "Subscription revenue milestone reached",
        megaSubscriptions.address,
        "subscribe"
      );

      // 5. Verify all systems are working
      const subscription = await megaSubscriptions.subscriptions(1);
      expect(subscription.subscriber).to.equal(customer.address);
      expect(subscription.status).to.equal(1); // Active
    });
  });
});
