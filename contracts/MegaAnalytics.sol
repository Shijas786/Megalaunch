// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MegaAnalytics
 * @dev Advanced analytics and reporting system for MegaETH Launch Kit
 */
contract MegaAnalytics is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    bytes32 public constant ANALYST_ROLE = keccak256("ANALYST_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    struct MetricData {
        uint256 timestamp;
        uint256 value;
        string category;
        string subcategory;
        address user;
        bytes32 dataHash;
    }

    struct Report {
        uint256 id;
        string title;
        string description;
        string reportType;
        uint256 startTime;
        uint256 endTime;
        bytes32[] metrics;
        bool generated;
        uint256 createdAt;
    }

    struct Dashboard {
        uint256 id;
        address owner;
        string name;
        string description;
        uint256[] reportIds;
        bool isPublic;
        uint256 createdAt;
    }

    Counters.Counter private _metricIds;
    Counters.Counter private _reportIds;
    Counters.Counter private _dashboardIds;

    mapping(uint256 => MetricData) public metrics;
    mapping(uint256 => Report) public reports;
    mapping(uint256 => Dashboard) public dashboards;
    mapping(address => uint256[]) public userDashboards;
    mapping(string => uint256[]) public categoryMetrics;
    mapping(bytes32 => uint256[]) public hashMetrics;

    // Real-time statistics
    mapping(string => uint256) public categoryTotals;
    mapping(address => uint256) public userActivity;
    mapping(uint256 => uint256) public dailyTotals; // timestamp => total
    mapping(uint256 => uint256) public hourlyTotals; // timestamp => total

    event MetricRecorded(uint256 indexed metricId, string category, uint256 value);
    event ReportGenerated(uint256 indexed reportId, string reportType);
    event DashboardCreated(uint256 indexed dashboardId, address indexed owner);
    event AnalyticsUpdated(string category, uint256 newTotal);

    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ANALYST_ROLE, _admin);
        _grantRole(REPORTER_ROLE, _admin);
    }

    /**
     * @dev Record a metric
     */
    function recordMetric(
        uint256 value,
        string memory category,
        string memory subcategory,
        address user,
        bytes32 dataHash
    ) external onlyRole(ANALYST_ROLE) {
        _metricIds.increment();
        uint256 metricId = _metricIds.current();

        metrics[metricId] = MetricData({
            timestamp: block.timestamp,
            value: value,
            category: category,
            subcategory: subcategory,
            user: user,
            dataHash: dataHash
        });

        categoryMetrics[category].push(metricId);
        hashMetrics[dataHash].push(metricId);
        
        // Update real-time stats
        categoryTotals[category] += value;
        userActivity[user]++;
        _updateTimeSeriesStats(value);

        emit MetricRecorded(metricId, category, value);
    }

    /**
     * @dev Generate a comprehensive report
     */
    function generateReport(
        string memory title,
        string memory description,
        string memory reportType,
        uint256 startTime,
        uint256 endTime,
        string[] memory categories
    ) external onlyRole(REPORTER_ROLE) returns (uint256) {
        _reportIds.increment();
        uint256 reportId = _reportIds.current();

        bytes32[] memory reportMetrics = new bytes32[](categories.length);
        for (uint256 i = 0; i < categories.length; i++) {
            reportMetrics[i] = keccak256(abi.encodePacked(categories[i], startTime, endTime));
        }

        reports[reportId] = Report({
            id: reportId,
            title: title,
            description: description,
            reportType: reportType,
            startTime: startTime,
            endTime: endTime,
            metrics: reportMetrics,
            generated: true,
            createdAt: block.timestamp
        });

        emit ReportGenerated(reportId, reportType);
        return reportId;
    }

    /**
     * @dev Create a custom dashboard
     */
    function createDashboard(
        string memory name,
        string memory description,
        uint256[] memory reportIds,
        bool isPublic
    ) external returns (uint256) {
        _dashboardIds.increment();
        uint256 dashboardId = _dashboardIds.current();

        dashboards[dashboardId] = Dashboard({
            id: dashboardId,
            owner: msg.sender,
            name: name,
            description: description,
            reportIds: reportIds,
            isPublic: isPublic,
            createdAt: block.timestamp
        });

        userDashboards[msg.sender].push(dashboardId);
        emit DashboardCreated(dashboardId, msg.sender);
        return dashboardId;
    }

    /**
     * @dev Get metrics by category with pagination
     */
    function getMetricsByCategory(
        string memory category,
        uint256 offset,
        uint256 limit
    ) external view returns (MetricData[] memory, uint256 total) {
        uint256[] memory metricIds = categoryMetrics[category];
        total = metricIds.length;
        
        uint256 end = offset + limit;
        if (end > total) end = total;
        if (offset >= total) return (new MetricData[](0), total);

        MetricData[] memory result = new MetricData[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = metrics[metricIds[i]];
        }

        return (result, total);
    }

    /**
     * @dev Get user activity summary
     */
    function getUserActivitySummary(address user) external view returns (
        uint256 totalActivity,
        uint256[] memory dashboardIds,
        uint256[] memory recentMetrics
    ) {
        totalActivity = userActivity[user];
        dashboardIds = userDashboards[user];
        
        // Get recent metrics for user (simplified - in production, use proper indexing)
        recentMetrics = new uint256[](0); // Placeholder
    }

    /**
     * @dev Get time series data
     */
    function getTimeSeriesData(
        uint256 startTime,
        uint256 endTime,
        bool isHourly
    ) external view returns (uint256[] memory timestamps, uint256[] memory values) {
        uint256 duration = endTime - startTime;
        uint256 interval = isHourly ? 1 hours : 1 days;
        uint256 dataPoints = duration / interval;
        
        timestamps = new uint256[](dataPoints);
        values = new uint256[](dataPoints);
        
        for (uint256 i = 0; i < dataPoints; i++) {
            uint256 timestamp = startTime + (i * interval);
            timestamps[i] = timestamp;
            values[i] = isHourly ? hourlyTotals[timestamp] : dailyTotals[timestamp];
        }
    }

    /**
     * @dev Get category statistics
     */
    function getCategoryStats(string memory category) external view returns (
        uint256 totalValue,
        uint256 metricCount,
        uint256 avgValue,
        uint256 maxValue,
        uint256 minValue
    ) {
        uint256[] memory metricIds = categoryMetrics[category];
        metricCount = metricIds.length;
        totalValue = categoryTotals[category];
        
        if (metricCount > 0) {
            avgValue = totalValue / metricCount;
            
            maxValue = 0;
            minValue = type(uint256).max;
            
            for (uint256 i = 0; i < metricIds.length; i++) {
                uint256 value = metrics[metricIds[i]].value;
                if (value > maxValue) maxValue = value;
                if (value < minValue) minValue = value;
            }
        }
    }

    /**
     * @dev Export data for external analysis
     */
    function exportData(
        uint256 startTime,
        uint256 endTime,
        string[] memory categories
    ) external view onlyRole(ANALYST_ROLE) returns (
        MetricData[] memory exportedMetrics,
        uint256 totalRecords
    ) {
        // In production, implement efficient data export
        // This is a simplified version
        exportedMetrics = new MetricData[](0);
        totalRecords = 0;
    }

    /**
     * @dev Update time series statistics
     */
    function _updateTimeSeriesStats(uint256 value) internal {
        uint256 dayTimestamp = (block.timestamp / 1 days) * 1 days;
        uint256 hourTimestamp = (block.timestamp / 1 hours) * 1 hours;
        
        dailyTotals[dayTimestamp] += value;
        hourlyTotals[hourTimestamp] += value;
    }

    /**
     * @dev Batch record metrics for efficiency
     */
    function batchRecordMetrics(
        uint256[] memory values,
        string[] memory categories,
        string[] memory subcategories,
        address[] memory users,
        bytes32[] memory dataHashes
    ) external onlyRole(ANALYST_ROLE) {
        require(
            values.length == categories.length &&
            categories.length == subcategories.length &&
            subcategories.length == users.length &&
            users.length == dataHashes.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < values.length; i++) {
            recordMetric(values[i], categories[i], subcategories[i], users[i], dataHashes[i]);
        }
    }

    /**
     * @dev Get dashboard data
     */
    function getDashboardData(uint256 dashboardId) external view returns (
        Dashboard memory dashboard,
        Report[] memory dashboardReports
    ) {
        dashboard = dashboards[dashboardId];
        require(dashboard.owner == msg.sender || dashboard.isPublic, "Access denied");
        
        dashboardReports = new Report[](dashboard.reportIds.length);
        for (uint256 i = 0; i < dashboard.reportIds.length; i++) {
            dashboardReports[i] = reports[dashboard.reportIds[i]];
        }
    }

    /**
     * @dev Update dashboard
     */
    function updateDashboard(
        uint256 dashboardId,
        string memory name,
        string memory description,
        uint256[] memory reportIds,
        bool isPublic
    ) external {
        Dashboard storage dashboard = dashboards[dashboardId];
        require(dashboard.owner == msg.sender, "Not owner");
        
        dashboard.name = name;
        dashboard.description = description;
        dashboard.reportIds = reportIds;
        dashboard.isPublic = isPublic;
    }
}
