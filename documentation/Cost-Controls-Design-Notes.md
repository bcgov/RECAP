# RECAP Cost Control - Folder Structure

Clean, organized cost control system with working PowerShell scripts and comprehensive documentation.

## Folder Contents

```
cost-control/
├── README.md                          # Main overview and quick start guide
├── setup-guide.md                     # Detailed step-by-step setup instructions  
│
├── azure-deploy-cost-control.ps1      # Deploy automation infrastructure
├── azure-configure-budget-integration.ps1  # Link budgets to automation
├── webapp-control.ps1                  # Manual webapp start/stop/restart
├── azure-verify-cost-control.ps1       # System testing and validation
├── azure-delete-cost-control.ps1       # Delete all cost control resources
├── monitor-costs.ps1                   # Real-time cost monitoring dashboard
└── cleanup-cost-control.ps1            # Remove all resources

documentation/
├── az-cli-commands.md                 # Complete Azure CLI command reference
├── Cost-Controls-Design-Notes.md      # This file - folder organization & design notes
└── Cost-Controls-Overview.md          # Executive summary and implementation status
```

## Script Categories

### Deployment Scripts
- **`azure-deploy-cost-control.ps1`** - Creates Azure automation infrastructure
- **`azure-configure-budget-integration.ps1`** - Links existing budgets to automation

### Operations Scripts  
- **`webapp-control.ps1`** - Manual webapp lifecycle management
- **`monitor-costs.ps1`** - Real-time cost and system monitoring

### Testing Scripts
- **`azure-verify-cost-control.ps1`** - Comprehensive system validation
- **`azure-delete-cost-control.ps1`** - Delete all cost control resources

### Cleanup Scripts
- **`cleanup-cost-control.ps1`** - Complete resource removal

### Documentation
- **`README.md`** - Overview, quick start, and daily operations
- **`setup-guide.md`** - Detailed setup with Portal and CLI instructions
- **`documentation/az-cli-commands.md`** - Complete Azure CLI command reference
- **`documentation/Cost-Controls-Design-Notes.md`** - Folder organization and design notes
- **`documentation/Cost-Controls-Overview.md`** - Executive summary and implementation status

## Quick Reference Commands

### Initial Setup (3 commands)
```powershell
.\azure-deploy-cost-control.ps1 -Environment "test"
.\azure-configure-budget-integration.ps1 -Environment "test"  
.\azure-verify-cost-control.ps1 -Environment "test" -DryRun
```

### Daily Operations
```powershell
# Monitor costs
.\monitor-costs.ps1 -Environment "test"

# Control webapp  
.\webapp-control.ps1 -Environment "test" -Action "Status"
.\webapp-control.ps1 -Environment "test" -Action "Start"
.\webapp-control.ps1 -Environment "test" -Action "Stop"

# Test system
.\azure-verify-cost-control.ps1 -Environment "test"
```

### Troubleshooting
```powershell
# Check infrastructure
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure

# Check budget integration
.\azure-verify-cost-control.ps1 -Environment "test" -CheckBudgetIntegration

# Check permissions
.\azure-verify-cost-control.ps1 -Environment "test" -CheckPermissions

# Show logs
.\monitor-costs.ps1 -Environment "test" -ShowLogs
```

### Cleanup
```powershell
# Remove everything
.\cleanup-cost-control.ps1 -Environment "test" -Force

# Preview deletion
.\cleanup-cost-control.ps1 -Environment "test" -WhatIf
```

## Environment Support

All scripts support both **test** and **prod** environments:

### Test Environment
- Resource Group: `d837ad-test-networking`
- WebApp: `d837ad-test-recap-webapp`
- Budget: `budget-for-d837ad-test-cost-control-automation` (owned, CA$250, alerts 30/50/80%)
- Threshold: 80% ($200 of $250 CAD)

### Production Environment  
- Resource Group: `d837ad-prod-networking`
- WebApp: `d837ad-prod-recap-webapp`
- Budget: `budget-for-d837ad-prod-cost-control-automation` (owned, CA$250, alerts 30/50/80%)
- Threshold: 90% ($450 of $250 CAD)

## Azure Resources Created

### Per Environment:
- **Action Group**: `d837ad-{env}-action-group`
- **Automation Account**: `d837ad-{env}-automation-account`
- **Runbook**: `d837ad-{env}-cost-control-runbook`
- **Webhook**: Links budget alerts to runbook
- **Managed Identity**: With minimal required permissions

### Permissions Required:
- **Website Contributor**: For webapp start/stop operations
- **Reader**: For subscription and resource group access

## Script Parameters

### Common Parameters
- **`-Environment`**: `"test"` or `"prod"` (required for all scripts)
- **`-WhatIf`**: Preview mode without making changes
- **`-Force`**: Skip confirmation prompts

### Specialized Parameters
- **`-DryRun`**: Test automation without stopping webapp
- **`-CheckInfrastructure`**: Validate Azure resources exist
- **`-CheckBudgetIntegration`**: Verify budget-automation linkage
- **`-CheckPermissions`**: Validate automation account permissions
- **`-ShowLogs`**: Display recent automation job logs
- **`-Brief`**: Minimal output for monitoring

## File Dependencies

### None! 
Each script is **self-contained** with embedded configuration and error handling.


