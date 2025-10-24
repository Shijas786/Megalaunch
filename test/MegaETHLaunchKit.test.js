const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MegaETH Launch Kit", function () {
  let megaPay, megaCommerce, megaPayments, megaAttest;
  let owner, merchant, customer, feeCollector;
  let mockToken;

  beforeEach(async function () {
    [owner, merchant, customer, feeCollector] = await ethers.getSigners();

    // Deploy mock ERC20 token for testing
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Test Token", "TEST", ethers.utils.parseEther("1000000"));
    await mockToken.deployed();

    // Deploy contracts
    const MegaPay = await ethers.getContractFactory("MegaPay");
    megaPay = await MegaPay.deploy(feeCollector.address);
    await megaPay.deployed();

    const MegaCommerce = await ethers.getContractFactory("MegaCommerce");
    megaCommerce = await MegaCommerce.deploy(feeCollector.address);
    await megaCommerce.deployed();

    const MegaPayments = await ethers.getContractFactory("MegaPayments");
    megaPayments = await MegaPayments.deploy(feeCollector.address);
    await megaPayments.deployed();

    const MegaAttest = await ethers.getContractFactory("MegaAttest");
    megaAttest = await MegaAttest.deploy(feeCollector.address);
    await megaAttest.deployed();

    // Setup initial configuration
    await megaPayments.authorizeMerchant(merchant.address);
    await megaAttest.authorizeAttester(merchant.address);
    await megaCommerce.addSupportedToken(mockToken.address);
    await megaPayments.addSupportedToken(mockToken.address);
    await megaPay.addSupportedToken(mockToken.address, ethers.utils.parseEther("0.001")); // 0.001 token per gas
  });

  describe("MegaPay", function () {
    it("Should allow users to pay fees with supported tokens", async function () {
      const gasUsed = 100000;
      const feeAmount = await megaPay.calculateFeeAmount(mockToken.address, gasUsed);
      
      await mockToken.transfer(customer.address, feeAmount);
      await mockToken.connect(customer).approve(megaPay.address, feeAmount);
      
      await expect(megaPay.connect(customer).payFeesWithToken(mockToken.address, gasUsed))
        .to.emit(megaPay, "FeePaid")
        .withArgs(customer.address, mockToken.address, feeAmount, gasUsed);
    });

    it("Should reject payments with unsupported tokens", async function () {
      await expect(megaPay.connect(customer).payFeesWithToken(mockToken.address, 100000))
        .to.be.revertedWith("Token not supported");
    });
  });

  describe("MegaCommerce", function () {
    it("Should allow merchants to create stores and products", async function () {
      // Create store
      await megaCommerce.connect(merchant).createStore("Test Store", "A test store", "https://example.com/logo.png");
      
      // Create product
      await megaCommerce.connect(merchant).createProduct(
        "Test Product",
        "A test product",
        ethers.utils.parseEther("1"),
        ethers.constants.AddressZero, // ETH
        10,
        "https://example.com/product.png"
      );

      const storeId = await megaCommerce.userStore(merchant.address);
      expect(storeId).to.be.gt(0);
    });

    it("Should allow customers to place orders", async function () {
      // Setup store and product
      await megaCommerce.connect(merchant).createStore("Test Store", "A test store", "");
      await megaCommerce.connect(merchant).createProduct(
        "Test Product",
        "A test product",
        ethers.utils.parseEther("1"),
        ethers.constants.AddressZero,
        10,
        ""
      );

      // Place order
      await expect(megaCommerce.connect(customer).createOrder(1, 2, "123 Main St", { value: ethers.utils.parseEther("2") }))
        .to.emit(megaCommerce, "OrderCreated");
    });
  });

  describe("MegaPayments", function () {
    it("Should allow merchants to create payment requests", async function () {
      const requestId = await megaPayments.connect(merchant).callStatic.createPaymentRequest(
        customer.address,
        ethers.utils.parseEther("1"),
        ethers.constants.AddressZero,
        "Test payment",
        "",
        0
      );

      await megaPayments.connect(merchant).createPaymentRequest(
        customer.address,
        ethers.utils.parseEther("1"),
        ethers.constants.AddressZero,
        "Test payment",
        "",
        0
      );

      expect(requestId).to.be.gt(0);
    });

    it("Should allow customers to fulfill payment requests", async function () {
      // Create payment request
      await megaPayments.connect(merchant).createPaymentRequest(
        customer.address,
        ethers.utils.parseEther("1"),
        ethers.constants.AddressZero,
        "Test payment",
        "",
        0
      );

      // Fulfill payment request
      await expect(megaPayments.connect(customer).fulfillPaymentRequestETH(1, { value: ethers.utils.parseEther("1") }))
        .to.emit(megaPayments, "PaymentCompleted");
    });
  });

  describe("MegaAttest", function () {
    it("Should allow attesters to create attestations", async function () {
      const dataHash = "0x" + "a".repeat(64);
      
      await expect(megaAttest.connect(merchant).createAttestation(
        customer.address,
        0, // KYC
        dataHash,
        "https://example.com/data.json",
        0,
        true
      )).to.emit(megaAttest, "AttestationCreated");
    });

    it("Should allow checking if subject has valid attestation", async function () {
      const dataHash = "0x" + "a".repeat(64);
      
      // Create attestation
      await megaAttest.connect(merchant).createAttestation(
        customer.address,
        0, // KYC
        dataHash,
        "https://example.com/data.json",
        0,
        true
      );

      // Approve attestation
      await megaAttest.connect(merchant).updateAttestationStatus(1, 1); // Approved

      // Check if customer has valid KYC attestation
      const hasValidAttestation = await megaAttest.hasValidAttestation(customer.address, 0);
      expect(hasValidAttestation).to.be.true;
    });
  });
});
