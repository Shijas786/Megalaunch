// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MegaMonitor
 * @dev Advanced monitoring and testing system for MegaETH Launch Kit
 */
contract MegaMonitor is AccessControl, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;

    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    bytes32 public constant TESTER_ROLE = keccak256("TESTER_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    enum AlertLevel { Low, Medium, High, Critical }
    enum AlertType { Security, Performance, Economic, Governance }
    enum TestStatus { Pending, Running, Passed, Failed, Skipped }

    struct Alert {
        uint256 id;
        AlertLevel level;
        AlertType alertType;
        string title;
        string description;
        address contractAddress;
        string functionName;
        uint256 timestamp;
        bool acknowledged;
        address acknowledgedBy;
        uint256 acknowledgedAt;
    }

    struct TestCase {
        uint256 id;
        string name;
        string description;
        string contractAddress;
        string functionName;
        bytes parameters;
        bytes expectedResult;
        TestStatus status;
        uint256 gasLimit;
        uint256 timeout;
        uint256 createdAt;
        uint256 lastRun;
        string errorMessage;
    }

    struct PerformanceMetric {
        uint256 timestamp;
        uint256 gasUsed;
        uint256 executionTime;
        uint256 blockNumber;
        address contractAddress;
        string functionName;
        bool success;
    }

    struct SecurityCheck {
        uint256 id;
        string checkName;
        string description;
        address contractAddress;
        bool passed;
        string details;
        uint256 timestamp;
        address checkedBy;
    }

    Counters.Counter private _alertIds;
    Counters.Counter private _testIds;
    Counters.Counter private _securityCheckIds;

    mapping(uint256 => Alert) public alerts;
    mapping(uint256 => TestCase) public testCases;
    mapping(uint256 => SecurityCheck) public securityChecks;
    mapping(address => uint256[]) public contractAlerts;
    mapping(address => uint256[]) public contractTests;
    mapping(address => PerformanceMetric[]) public performanceMetrics;
    mapping(string => uint256[]) public testSuites;

    uint256 public maxAlertsPerContract = 1000;
    uint256 public maxTestsPerContract = 500;
    uint256 public alertRetentionPeriod = 30 days;
    uint256 public testRetentionPeriod = 90 days;

    event AlertCreated(uint256 indexed alertId, AlertLevel level, AlertType alertType);
    event AlertAcknowledged(uint256 indexed alertId, address indexed acknowledgedBy);
    event TestCaseCreated(uint256 indexed testId, string name);
    event TestExecuted(uint256 indexed testId, TestStatus status);
    event SecurityCheckPerformed(uint256 indexed checkId, bool passed);
    event PerformanceMetricRecorded(address indexed contractAddress, uint256 gasUsed);

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MONITOR_ROLE, _admin);
        _grantRole(TESTER_ROLE, _admin);
        _grantRole(AUDITOR_ROLE, _admin);
    }

    /**
     * @dev Create an alert
     */
    function createAlert(
        AlertLevel level,
        AlertType alertType,
        string memory title,
        string memory description,
        address contractAddress,
        string memory functionName
    ) external onlyRole(MONITOR_ROLE) returns (uint256) {
        require(bytes(title).length > 0, "Title required");
        require(contractAddress != address(0), "Invalid contract address");

        _alertIds.increment();
        uint256 alertId = _alertIds.current();

        alerts[alertId] = Alert({
            id: alertId,
            level: level,
            alertType: alertType,
            title: title,
            description: description,
            contractAddress: contractAddress,
            functionName: functionName,
            timestamp: block.timestamp,
            acknowledged: false,
            acknowledgedBy: address(0),
            acknowledgedAt: 0
        });

        contractAlerts[contractAddress].push(alertId);

        emit AlertCreated(alertId, level, alertType);
        return alertId;
    }

    /**
     * @dev Acknowledge an alert
     */
    function acknowledgeAlert(uint256 alertId) external onlyRole(MONITOR_ROLE) {
        Alert storage alert = alerts[alertId];
        require(!alert.acknowledged, "Already acknowledged");

        alert.acknowledged = true;
        alert.acknowledgedBy = msg.sender;
        alert.acknowledgedAt = block.timestamp;

        emit AlertAcknowledged(alertId, msg.sender);
    }

    /**
     * @dev Create a test case
     */
    function createTestCase(
        string memory name,
        string memory description,
        string memory contractAddress,
        string memory functionName,
        bytes memory parameters,
        bytes memory expectedResult,
        uint256 gasLimit,
        uint256 timeout
    ) external onlyRole(TESTER_ROLE) returns (uint256) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(contractAddress).length > 0, "Contract address required");

        _testIds.increment();
        uint256 testId = _testIds.current();

        testCases[testId] = TestCase({
            id: testId,
            name: name,
            description: description,
            contractAddress: contractAddress,
            functionName: functionName,
            parameters: parameters,
            expectedResult: expectedResult,
            status: TestStatus.Pending,
            gasLimit: gasLimit,
            timeout: timeout,
            createdAt: block.timestamp,
            lastRun: 0,
            errorMessage: ""
        });

        contractTests[address(bytes20(bytes(contractAddress)))].push(testId);

        emit TestCaseCreated(testId, name);
        return testId;
    }

    /**
     * @dev Execute a test case
     */
    function executeTest(uint256 testId) external onlyRole(TESTER_ROLE) returns (bool success) {
        TestCase storage test = testCases[testId];
        require(test.status == TestStatus.Pending || test.status == TestStatus.Failed, "Test not executable");

        test.status = TestStatus.Running;
        test.lastRun = block.timestamp;

        // In production, implement actual test execution
        // This is a simplified version
        try this._executeTestFunction(test.contractAddress, test.functionName, test.parameters) returns (bytes memory result) {
            if (keccak256(result) == keccak256(test.expectedResult)) {
                test.status = TestStatus.Passed;
                success = true;
            } else {
                test.status = TestStatus.Failed;
                test.errorMessage = "Result mismatch";
                success = false;
            }
        } catch Error(string memory reason) {
            test.status = TestStatus.Failed;
            test.errorMessage = reason;
            success = false;
        }

        emit TestExecuted(testId, test.status);
        return success;
    }

    /**
     * @dev Internal test function execution
     */
    function _executeTestFunction(
        string memory contractAddress,
        string memory functionName,
        bytes memory parameters
    ) external view returns (bytes memory) {
        // In production, implement proper contract interaction
        // This is a placeholder
        return abi.encode("test result");
    }

    /**
     * @dev Record performance metric
     */
    function recordPerformanceMetric(
        address contractAddress,
        string memory functionName,
        uint256 gasUsed,
        uint256 executionTime,
        bool success
    ) external onlyRole(MONITOR_ROLE) {
        PerformanceMetric memory metric = PerformanceMetric({
            timestamp: block.timestamp,
            gasUsed: gasUsed,
            executionTime: executionTime,
            blockNumber: block.number,
            contractAddress: contractAddress,
            functionName: functionName,
            success: success
        });

        performanceMetrics[contractAddress].push(metric);

        emit PerformanceMetricRecorded(contractAddress, gasUsed);
    }

    /**
     * @dev Perform security check
     */
    function performSecurityCheck(
        string memory checkName,
        string memory description,
        address contractAddress,
        bool passed,
        string memory details
    ) external onlyRole(AUDITOR_ROLE) returns (uint256) {
        _securityCheckIds.increment();
        uint256 checkId = _securityCheckIds.current();

        securityChecks[checkId] = SecurityCheck({
            id: checkId,
            checkName: checkName,
            description: description,
            contractAddress: contractAddress,
            passed: passed,
            details: details,
            timestamp: block.timestamp,
            checkedBy: msg.sender
        });

        emit SecurityCheckPerformed(checkId, passed);
        return checkId;
    }

    /**
     * @dev Get contract alerts
     */
    function getContractAlerts(
        address contractAddress,
        uint256 offset,
        uint256 limit
    ) external view returns (Alert[] memory, uint256 total) {
        uint256[] memory alertIds = contractAlerts[contractAddress];
        total = alertIds.length;
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        if (offset >= total) return (new Alert[](0), total);

        Alert[] memory result = new Alert[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = alerts[alertIds[i]];
        }

        return (result, total);
    }

    /**
     * @dev Get contract tests
     */
    function getContractTests(
        address contractAddress,
        uint256 offset,
        uint256 limit
    ) external view returns (TestCase[] memory, uint256 total) {
        uint256[] memory testIds = contractTests[contractAddress];
        total = testIds.length;
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        if (offset >= total) return (new TestCase[](0), total);

        TestCase[] memory result = new TestCase[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = testCases[testIds[i]];
        }

        return (result, total);
    }

    /**
     * @dev Get performance metrics
     */
    function getPerformanceMetrics(
        address contractAddress,
        uint256 offset,
        uint256 limit
    ) external view returns (PerformanceMetric[] memory, uint256 total) {
        PerformanceMetric[] memory metrics = performanceMetrics[contractAddress];
        total = metrics.length;
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        if (offset >= total) return (new PerformanceMetric[](0), total);

        PerformanceMetric[] memory result = new PerformanceMetric[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = metrics[i];
        }

        return (result, total);
    }

    /**
     * @dev Get security check summary
     */
    function getSecurityCheckSummary(address contractAddress) external view returns (
        uint256 totalChecks,
        uint256 passedChecks,
        uint256 failedChecks,
        uint256 lastCheckTime
    ) {
        // In production, implement proper indexing for efficiency
        totalChecks = 0;
        passedChecks = 0;
        failedChecks = 0;
        lastCheckTime = 0;
    }

    /**
     * @dev Get test suite results
     */
    function getTestSuiteResults(string memory suiteName) external view returns (
        uint256 totalTests,
        uint256 passedTests,
        uint256 failedTests,
        uint256 skippedTests
    ) {
        uint256[] memory testIds = testSuites[suiteName];
        totalTests = testIds.length;
        passedTests = 0;
        failedTests = 0;
        skippedTests = 0;

        for (uint256 i = 0; i < testIds.length; i++) {
            TestStatus status = testCases[testIds[i]].status;
            if (status == TestStatus.Passed) passedTests++;
            else if (status == TestStatus.Failed) failedTests++;
            else if (status == TestStatus.Skipped) skippedTests++;
        }
    }

    /**
     * @dev Clean up old data
     */
    function cleanupOldData() external onlyRole(MONITOR_ROLE) {
        uint256 currentTime = block.timestamp;
        
        // Clean up old alerts
        for (uint256 i = 1; i <= _alertIds.current(); i++) {
            if (alerts[i].timestamp < currentTime - alertRetentionPeriod) {
                delete alerts[i];
            }
        }

        // Clean up old tests
        for (uint256 i = 1; i <= _testIds.current(); i++) {
            if (testCases[i].createdAt < currentTime - testRetentionPeriod) {
                delete testCases[i];
            }
        }
    }

    /**
     * @dev Update settings
     */
    function updateSettings(
        uint256 newMaxAlertsPerContract,
        uint256 newMaxTestsPerContract,
        uint256 newAlertRetentionPeriod,
        uint256 newTestRetentionPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxAlertsPerContract = newMaxAlertsPerContract;
        maxTestsPerContract = newMaxTestsPerContract;
        alertRetentionPeriod = newAlertRetentionPeriod;
        testRetentionPeriod = newTestRetentionPeriod;
    }

    /**
     * @dev Emergency pause
     */
    function emergencyPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function emergencyUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
