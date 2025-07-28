{
  "metadata": {
    "purpose": "Performance baselines and thresholds for Find-UnknownSID operations",
    "environment": "Testing",
    "lastUpdated": "2024-01-15T10:30:00Z",
    "version": "1.0.0"
  },
  "executionTimeBaselines": {
    "singleSIDLookup": {
      "baseline": "PT0.1S",
      "acceptable": "PT0.5S",
      "warning": "PT1S",
      "critical": "PT2S",
      "unit": "ISO8601 Duration",
      "description": "Time to resolve a single SID via Active Directory"
    },
    "batchSIDLookup": {
      "baseline": "PT5S",
      "acceptable": "PT15S",
      "warning": "PT30S",
      "critical": "PT60S",
      "batchSize": 100,
      "description": "Time to resolve 100 SIDs in a single batch operation"
    },
    "securityDescriptorScan": {
      "small": {
        "objectCount": 1000,
        "baseline": "PT30S",
        "acceptable": "PT60S",
        "warning": "PT120S",
        "critical": "PT300S"
      },
      "medium": {
        "objectCount": 10000,
        "baseline": "PT300S",
        "acceptable": "PT600S",
        "warning": "PT1200S",
        "critical": "PT1800S"
      },
      "large": {
        "objectCount": 100000,
        "baseline": "PT3600S",
        "acceptable": "PT7200S",
        "warning": "PT10800S",
        "critical": "PT14400S"
      }
    },
    "databaseOperations": {
      "insertAuditRecord": {
        "baseline": "PT0.01S",
        "acceptable": "PT0.05S",
        "warning": "PT0.1S",
        "critical": "PT0.5S"
      },
      "queryOrphanedSIDs": {
        "baseline": "PT1S",
        "acceptable": "PT5S",
        "warning": "PT10S",
        "critical": "PT30S"
      },
      "bulkUpdate": {
        "recordCount": 1000,
        "baseline": "PT5S",
        "acceptable": "PT15S",
        "warning": "PT30S",
        "critical": "PT60S"
      }
    }
  },
  "memoryUsageBaselines": {
    "baselineMemory": {
      "startup": "50MB",
      "idle": "75MB",
      "processing": "200MB",
      "maximum": "500MB",
      "critical": "1GB"
    },
    "perObjectMemory": {
      "simpleObject": "1KB",
      "complexObject": "5KB",
      "securityDescriptor": "2KB",
      "largeSecurityDescriptor": "10KB"
    },
    "scalingFactors": {
      "1000Objects": "100MB",
      "10000Objects": "250MB",
      "100000Objects": "500MB",
      "1000000Objects": "1GB"
    },
    "memoryLeakThresholds": {
      "acceptableGrowth": "10MB",
      "warningGrowth": "50MB",
      "criticalGrowth": "100MB",
      "measurementInterval": "PT1H"
    }
  },
  "throughputBaselines": {
    "sidsPerSecond": {
      "singleThreaded": {
        "baseline": 50,
        "acceptable": 30,
        "warning": 20,
        "critical": 10
      },
      "multiThreaded": {
        "threads": 4,
        "baseline": 150,
        "acceptable": 100,
        "warning": 75,
        "critical": 50
      }
    },
    "objectsPerSecond": {
      "securityDescriptorScan": {
        "baseline": 100,
        "acceptable": 50,
        "warning": 25,
        "critical": 10
      },
      "aclAnalysis": {
        "baseline": 200,
        "acceptable": 100,
        "warning": 50,
        "critical": 25
      }
    },
    "networkOperations": {
      "ldapQueries": {
        "baseline": 1000,
        "acceptable": 500,
        "warning": 250,
        "critical": 100,
        "unit": "queries per minute"
      },
      "databaseConnections": {
        "baseline": 100,
        "acceptable": 50,
        "warning": 25,
        "critical": 10,
        "unit": "connections per minute"
      }
    }
  },
  "scalabilityBaselines": {
    "concurrentUsers": {
      "supported": 10,
      "maximum": 25,
      "degradationThreshold": 50,
      "failureThreshold": 100
    },
    "dataVolume": {
      "smallDomain": {
        "objects": 10000,
        "sids": 50000,
        "expectedTime": "PT5M",
        "expectedMemory": "200MB"
      },
      "mediumDomain": {
        "objects": 100000,
        "sids": 500000,
        "expectedTime": "PT30M",
        "expectedMemory": "500MB"
      },
      "largeDomain": {
        "objects": 1000000,
        "sids": 5000000,
        "expectedTime": "PT180M",
        "expectedMemory": "2GB"
      },
      "enterpriseDomain": {
        "objects": 10000000,
        "sids": 50000000,
        "expectedTime": "PT720M",
        "expectedMemory": "8GB"
      }
    }
  },
  "resourceUtilizationBaselines": {
    "cpuUsage": {
      "idle": 5,
      "normal": 25,
      "heavy": 50,
      "maximum": 80,
      "critical": 95,
      "unit": "percentage"
    },
    "diskIO": {
      "reads": {
        "baseline": 100,
        "acceptable": 500,
        "warning": 1000,
        "critical": 2000,
        "unit": "operations per second"
      },
      "writes": {
        "baseline": 50,
        "acceptable": 200,
        "warning": 500,
        "critical": 1000,
        "unit": "operations per second"
      }
    },
    "networkBandwidth": {
      "baseline": "1Mbps",
      "acceptable": "10Mbps",
      "warning": "50Mbps",
      "critical": "100Mbps"
    },
    "databaseConnections": {
      "baseline": 5,
      "acceptable": 20,
      "warning": 50,
      "critical": 100,
      "maximum": 150
    }
  },
  "errorRateBaselines": {
    "acceptableErrorRates": {
      "totalOperations": 0.1,
      "networkOperations": 1.0,
      "databaseOperations": 0.5,
      "fileSystemOperations": 0.2,
      "unit": "percentage"
    },
    "warningThresholds": {
      "totalOperations": 1.0,
      "networkOperations": 5.0,
      "databaseOperations": 2.0,
      "fileSystemOperations": 1.0,
      "unit": "percentage"
    },
    "criticalThresholds": {
      "totalOperations": 5.0,
      "networkOperations": 10.0,
      "databaseOperations": 5.0,
      "fileSystemOperations": 3.0,
      "unit": "percentage"
    }
  },
  "responseTimeBaselines": {
    "userInterface": {
      "commandResponse": {
        "baseline": "PT1S",
        "acceptable": "PT3S",
        "warning": "PT5S",
        "critical": "PT10S"
      },
      "reportGeneration": {
        "baseline": "PT10S",
        "acceptable": "PT30S",
        "warning": "PT60S",
        "critical": "PT180S"
      }
    },
    "apiEndpoints": {
      "healthCheck": {
        "baseline": "PT0.1S",
        "acceptable": "PT0.5S",
        "warning": "PT1S",
        "critical": "PT2S"
      },
      "sidLookup": {
        "baseline": "PT0.5S",
        "acceptable": "PT2S",
        "warning": "PT5S",
        "critical": "PT10S"
      },
      "bulkOperations": {
        "baseline": "PT5S",
        "acceptable": "PT15S",
        "warning": "PT30S",
        "critical": "PT60S"
      }
    }
  },
  "testScenarios": {
    "loadTesting": {
      "lightLoad": {
        "concurrentUsers": 5,
        "operationsPerUser": 100,
        "duration": "PT5M",
        "expectedSuccessRate": 99.9
      },
      "normalLoad": {
        "concurrentUsers": 10,
        "operationsPerUser": 500,
        "duration": "PT15M",
        "expectedSuccessRate": 99.5
      },
      "heavyLoad": {
        "concurrentUsers": 25,
        "operationsPerUser": 1000,
        "duration": "PT30M",
        "expectedSuccessRate": 98.0
      },
      "stressTest": {
        "concurrentUsers": 50,
        "operationsPerUser": 2000,
        "duration": "PT60M",
        "expectedSuccessRate": 95.0
      }
    },
    "enduranceTesting": {
      "shortRun": {
        "duration": "PT2H",
        "acceptablePerformanceDegradation": 5.0
      },
      "mediumRun": {
        "duration": "PT8H",
        "acceptablePerformanceDegradation": 10.0
      },
      "longRun": {
        "duration": "PT24H",
        "acceptablePerformanceDegradation": 15.0
      }
    }
  },
  "benchmarkingGuidelines": {
    "measurementPractices": {
      "warmupIterations": 3,
      "measurementIterations": 5,
      "cooldownPeriod": "PT30S",
      "environmentStabilization": "PT5M"
    },
    "dataCollection": {
      "metrics": [
        "executionTime",
        "memoryUsage",
        "cpuUsage",
        "diskIO",
        "networkIO",
        "errorRate",
        "throughput"
      ],
      "samplingInterval": "PT1S",
      "aggregationMethods": ["mean", "median", "p95", "p99", "max"]
    },
    "baselineUpdate": {
      "frequency": "monthly",
      "triggerConditions": [
        "majorVersionRelease",
        "infrastructureChanges",
        "performanceRegression",
        "optimizationImplemented"
      ],
      "validationRequirements": [
        "multipleEnvironments",
        "varyingLoadConditions",
        "statisticalSignificance"
      ]
    }
  }
}
