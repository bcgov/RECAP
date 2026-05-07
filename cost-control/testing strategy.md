# RECAP Cost Control Testing Strategy

## Essential Tests

### 1. Action Group → Webhook Chain Test

**Azure Portal:**
1. Navigate to Monitor → Alerts → Action groups
2. Select `d837ad-test-action-group` or `d837ad-prod-action-group`
3. Click Test action group
4. Sample type: Select Budget
5. Click Test

**Expected:** Webhook triggers → Runbook starts → WebApp stops within 30-60 seconds

### 2. Infrastructure Validation

```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -CheckInfrastructure

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -CheckInfrastructure
```

### 3. Budget Integration Validation

```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -CheckBudgetIntegration

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -CheckBudgetIntegration
```

### 4. Webhook Configuration Test

```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -TestWebhook

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -TestWebhook
```

### 5. Permissions Validation

```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -CheckPermissions

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -CheckPermissions
```

### 6. Runbook Testing

**DRY RUN (Safe):**
```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -TestShutdown -DryRun
.\azure-verify-cost-control.ps1 -Environment test -TestStartUp -DryRun

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -TestShutdown -DryRun
.\azure-verify-cost-control.ps1 -Environment prod -TestStartUp -DryRun
```

**LIVE TEST (Actually stops/starts webapp):**
```powershell
# Test environment only
.\azure-verify-cost-control.ps1 -Environment test -TestShutdown
.\azure-verify-cost-control.ps1 -Environment test -TestStartUp
```

### 7. Manual WebApp Control

```powershell
# Test environment
.\webapp-control.ps1 -Environment test -Action "Status"
.\webapp-control.ps1 -Environment test -Action "Stop"
.\webapp-control.ps1 -Environment test -Action "Start"

# Production environment
.\webapp-control.ps1 -Environment prod -Action "Status"
.\webapp-control.ps1 -Environment prod -Action "Stop"
.\webapp-control.ps1 -Environment prod -Action "Start"
```

## Configuration Validation Commands

```powershell
# Check budget thresholds (test)
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation" --query "notifications.*.[threshold,enabled,contactGroups]" --output table

# Check budget thresholds (prod)
az consumption budget show --budget-name "budget-for-d837ad-prod-cost-control-automation" --query "notifications.*.[threshold,enabled,contactGroups]" --output table

# Verify action group webhook (test)
az monitor action-group show --name "d837ad-test-action-group" --resource-group "d837ad-test-networking" --query "webhookReceivers[].serviceUri" --output table

# Verify action group webhook (prod)
az monitor action-group show --name "d837ad-prod-action-group" --resource-group "d837ad-prod-networking" --query "webhookReceivers[].serviceUri" --output table

# Check automation account status (test)
az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --query "{name: name, state: state, identity: identity.principalId}" --output json

# Check automation account status (prod)
az automation account show --name "d837ad-prod-automation-account" --resource-group "d837ad-prod-networking" --query "{name: name, state: state, identity: identity.principalId}" --output json
```

## Deployment Testing Sequence

### Initial Deployment Verification

```powershell
# 1. Deploy infrastructure
.\azure-deploy-cost-control.ps1 -Environment test
.\azure-deploy-cost-control.ps1 -Environment prod

# 2. Configure budget integration
.\azure-configure-budget-integration.ps1 -Environment test
.\azure-configure-budget-integration.ps1 -Environment prod

# 3. Complete system validation
.\azure-verify-cost-control.ps1 -Environment test
.\azure-verify-cost-control.ps1 -Environment prod
```

### Comprehensive Testing

**Test Environment:**
```powershell
.\azure-verify-cost-control.ps1 -Environment test -CheckInfrastructure -CheckBudgetIntegration -CheckPermissions -TestWebhook -TestShutdown -DryRun
```

**Production Environment:**
```powershell
.\azure-verify-cost-control.ps1 -Environment prod -CheckInfrastructure -CheckBudgetIntegration -CheckPermissions -TestWebhook -TestShutdown -DryRun
```

## Ongoing Monitoring

### Daily Health Check

```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -CheckInfrastructure

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -CheckInfrastructure
```

### Monthly Comprehensive Check

```powershell
# Test environment
.\azure-verify-cost-control.ps1 -Environment test -CheckInfrastructure -CheckBudgetIntegration -CheckPermissions -TestWebhook -DryRun

# Production environment
.\azure-verify-cost-control.ps1 -Environment prod -CheckInfrastructure -CheckBudgetIntegration -CheckPermissions -TestWebhook -DryRun
```

### Cost Monitoring

```powershell
# Test environment
.\monitor-costs.ps1 -Environment test
.\monitor-costs.ps1 -Environment test -ShowLogs

# Production environment
.\monitor-costs.ps1 -Environment prod
.\monitor-costs.ps1 -Environment prod -ShowLogs
```

## Safety Requirements

1. Always use `-DryRun` first for runbook tests
2. Live runbook tests actually stop/start webapp
3. Production testing during maintenance windows only
4. Webhook testing requires `Connect-AzAccount`
5. Action Group test is the definitive end-to-end validation

## Recovery Procedures

**If webapp is stopped by automation:**
```powershell
# Test environment
.\webapp-control.ps1 -Environment test -Action "Start"

# Production environment  
.\webapp-control.ps1 -Environment prod -Action "Start"
```

**If system is misconfigured:**
```powershell
# Redeploy infrastructure
.\azure-deploy-cost-control.ps1 -Environment <env>

# Reconfigure budget integration
.\azure-configure-budget-integration.ps1 -Environment <env>
```