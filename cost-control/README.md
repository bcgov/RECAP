# RECAP Cost Control System

Azure cost monitoring and automated webapp shutdown system for RECAP environments.

## Overview

This system provides automated cost control by monitoring Azure budgets and automatically stopping the RECAP webapp when budget thresholds are exceeded.

## Quick Start

### 1. Deploy Cost Control Infrastructure

```powershell
# Deploy automation infrastructure (Action Group, Automation Account, Runbook)
.\azure-deploy-cost-control.ps1 -Environment "test"
```

### 2. Configure Budget and Integration (Automated)

```powershell
# Creates budget via REST API, webhook, and links all alerts to action group
.\azure-configure-budget-integration.ps1 -Environment "test"
```

### 3. Test the System

```powershell
# Test automation without actually stopping webapp
.\azure-verify-cost-control.ps1 -Environment "test" -DryRun
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure -TestShutdown -DryRun

# Test runbook-triggered shutdown (will actually stop webapp, use with caution)
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure -TestShutdown 

# Test manual webapp control
.\webapp-control.ps1 -Environment "test" -Action "Stop"
.\webapp-control.ps1 -Environment "test" -Action "Start"
```

### Additional Validation Commands

```powershell
# Check all resources exist
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure

# Validate budget integration
.\azure-verify-cost-control.ps1 -Environment "test" -CheckBudgetIntegration

# Test webhook connectivity
.\azure-verify-cost-control.ps1 -Environment "test" -TestWebhook
```

## Core Scripts

| Script | Purpose | Usage |
| -------- | --------- | -------- |
| `azure-deploy-cost-control.ps1` | Creates automation infrastructure | Deploy initial setup |
| `azure-configure-budget-integration.ps1` | Links budgets to automation | One-time configuration |
| `webapp-control.ps1` | Manual webapp start/stop | Operations & testing |
| `azure-verify-cost-control.ps1` | Validates entire system | Testing & verification |
| `azure-delete-cost-control.ps1` | Deletes all cost control resources | Cleanup & removal |
| `cleanup-cost-control.ps1` | Removes all resources | Environment cleanup |
| `monitor-costs.ps1` | Real-time cost monitoring | Cost tracking |

## Azure Resources Created

### Test Environment (`d837ad-test`)

- **Action Group**: `d837ad-test-action-group`
- **Automation Account**: `d837ad-test-automation-account`
- **Runbook**: `d837ad-{env}-cost-control-runbook`
- **Webhook**: Links budget alerts to automation
- **Target WebApp**: `d837ad-test-recap-webapp`

### Production Environment (`d837ad-prod`)

- **Action Group**: `d837ad-prod-action-group`
- **Automation Account**: `d837ad-prod-automation-account`
- **Runbook**: `d837ad-{env}-cost-control-runbook`
- **Webhook**: Links budget alerts to automation
- **Target WebApp**: `d837ad-prod-recap-webapp`

## Budget Integration

### Owned Cost-Control Budgets (Canonical)

- **Test**: `budget-for-d837ad-test-cost-control-automation` ($250 CAD)
- **Production**: `budget-for-d837ad-prod-cost-control-automation` ($250 CAD)

Project team owns these budgets so the action-group binding is not overwritten by the platform's reconciliation of the product-registry budgets.

### Alert Thresholds (per environment)

- **80%**: Automatic webapp shutdown (via runbook webhook on the action group)
- **50%**: Investigate notification
- **30%**: Early warning notification

## Security & Permissions

The automation uses Azure Managed Identity with minimal required permissions:

- **Website Contributor**: Start/stop webapp operations
- **Reader**: Access to subscription and resource group information

## Cost Optimization

### Current Costs (Daily)

- **Automation Account**: ~$0.01/day
- **Action Group**: Free (within limits)
- **Webhook Storage**: Free
- **Total**: ~$0.01/day per environment

## Support

For issues with cost control system:

1. Check logs: `.\monitor-costs.ps1 -Environment "test" -ShowLogs`
2. Validate setup: `.\azure-verify-cost-control.ps1 -Environment "test"`
3. Review Azure Portal: Automation Account → Job History
4. Manual recovery: `.\webapp-control.ps1 -Environment "test" -Action "Start"`
