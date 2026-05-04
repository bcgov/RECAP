# RECAP Cost Control - CLI Commands Reference

Complete Azure CLI command reference for cost control operations.

## Authentication

```bash
# Login to Azure
az login

# Set subscription context
az account set --subscription "d837ad-test"
az account set --subscription "d837ad-prod"

# Verify current context
az account show --query "{name: name, id: id}" --output table
```

## Budget Management

### View Budget Information

> Canonical (owned) budget for automation: `budget-for-d837ad-{env}-cost-control-automation`.
> The product-registry budget (`budget-for-d837ad-{env}-from-product-registry`) is **read-only reference** — do not wire automation to it (reconciled by upstream platform job).

```bash
# Show owned cost-control budget details
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation"

# Show current spend and amount
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation" --query "{amount: amount, currentSpend: currentSpend}" --output json

# Show all budgets in scope
az consumption budget list --output table

# Show owned budget notifications/alerts
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation" --query "notifications" --output json

# (Reference only) Inspect the platform-managed registry budget
az consumption budget show --budget-name "budget-for-d837ad-test-from-product-registry" --query "{amount:amount,currentSpend:currentSpend}" --output json
```

### Budget Alert Configuration

```bash
# Get action group resource ID for budget integration
ACTION_GROUP_ID="/subscriptions/$(az account show --query id --output tsv)/resourcegroups/d837ad-test-networking/providers/microsoft.insights/actiongroups/d837ad-test-action-group"

# Update budget with action group (80% threshold)
az consumption budget update \
  --budget-name "budget-for-d837ad-test-cost-control-automation" \
  --notifications actual_GreaterThanOrEqualTo_80_Percent='{
    "enabled": true,
    "operator": "GreaterThanOrEqualTo", 
    "threshold": 80,
    "contactEmails": ["admin@example.com"],
    "contactGroups": ["'$ACTION_GROUP_ID'"]
  }'

# Create custom budget (if needed)
az consumption budget create \
  --budget-name "recap-custom-budget-test" \
  --amount 100 \
  --time-grain "Monthly" \
  --time-period start-date="2026-05-01" end-date="2027-04-30" \
  --resource-group "d837ad-test-networking"
```

## Action Group Operations

### View Action Groups

```bash
# List all action groups in resource group
az monitor action-group list --resource-group "d837ad-test-networking" --output table

# Show specific action group details
az monitor action-group show --name "d837ad-test-action-group" --resource-group "d837ad-test-networking"

# Show action group webhooks and automation runbook receivers
az monitor action-group show --name "d837ad-test-action-group" --resource-group "d837ad-test-networking" --query "{webhookReceivers: webhookReceivers, automationRunbookReceivers: automationRunbookReceivers}" --output json
```

### Create/Update Action Groups

```bash
# Create basic action group
az monitor action-group create \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-action-group" \
  --short-name "CostCtrlGrp"

# Add webhook to action group (requires webhook URL from automation account)
az monitor action-group update \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-action-group" \
  --add-webhook "cost-control-webhook" "https://webhook-url-here" "true"

# Add email receiver
az monitor action-group update \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-action-group" \
  --add-email-receivers "admin" "admin@example.com" "true"
```

### Delete Action Groups

```bash
# Delete action group
az monitor action-group delete \
  --name "d837ad-test-action-group" \
  --resource-group "d837ad-test-networking"
```

## Automation Account Operations

### View Automation Accounts

```bash
# List automation accounts
az automation account list --resource-group "d837ad-test-networking" --output table

# Show automation account details
az automation account show \
  --name "d837ad-test-automation-account" \
  --resource-group "d837ad-test-networking"

# Show managed identity information
az automation account show \
  --name "d837ad-test-automation-account" \
  --resource-group "d837ad-test-networking" \
  --query "identity" --output json
```

### Create Automation Accounts

```bash
# Create automation account with managed identity
az automation account create \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-automation-account" \
  --location "Canada East" \
  --sku "Free" \
  --assign-identity

```

### Automation Modules

```bash
# List installed modules
az automation module list \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --output table

# Import specific module
az automation module import \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "Az.Accounts"

# Check module import status
az automation module show \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "Az.Accounts" \
  --query "{name: name, importState: importState}" --output json
```

### Runbook Operations

```bash
# List runbooks
az automation runbook list \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --output table

# Show runbook details
az automation runbook show \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "d837ad-{env}-cost-control-runbook"

# Import runbook from file
az automation runbook import \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "d837ad-{env}-cost-control-runbook" \
  --type "PowerShell" \
  --source-path "./runbook-content-shutdown.ps1"

# Publish runbook
az automation runbook publish \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "d837ad-{env}-cost-control-runbook"

# Start runbook job
az automation runbook start \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --runbook-name "d837ad-{env}-cost-control-runbook" \
  --parameters WebAppName="d837ad-test-recap-webapp" ResourceGroupName="d837ad-test-networking" Environment="test"
```

### Job Management

```bash
# List recent jobs
az automation job list \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --output table

# Show job details
az automation job show \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --job-id "JOB-ID-HERE"

# Get job output
az automation job show-output \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --job-id "JOB-ID-HERE"

# Get job streams (verbose output)
az automation job stream list \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --job-id "JOB-ID-HERE" \
  --output table
```

### Webhook Operations

```bash
# List webhooks
az automation webhook list \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --output table

# Show webhook details (Note: URL is not returned for security)
az automation webhook show \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "cost-control-webhook"

# Delete webhook
az automation webhook delete \
  --resource-group "d837ad-test-networking" \
  --automation-account-name "d837ad-test-automation-account" \
  --name "cost-control-webhook"
```

### Delete Automation Account

```bash
# Delete automation account (removes all runbooks, webhooks, etc.)
az automation account delete \
  --name "d837ad-test-automation-account" \
  --resource-group "d837ad-test-networking" \
  --yes
```

## WebApp Operations

### View WebApp Status

```bash
# Show webapp details
az webapp show \
  --name "d837ad-test-recap-webapp" \
  --resource-group "d837ad-test-networking" \
  --query "{state: state, availabilityState: availabilityState, lastModifiedTime: lastModifiedTime}" --output json

# Check webapp configuration
az webapp config show \
  --name "d837ad-test-recap-webapp" \
  --resource-group "d837ad-test-networking"

```

### WebApp Control

```bash
# Start webapp
az webapp start \
  --name "d837ad-test-recap-webapp" \
  --resource-group "d837ad-test-networking"

# Stop webapp
az webapp stop \
  --name "d837ad-test-recap-webapp" \
  --resource-group "d837ad-test-networking"

# Restart webapp
az webapp restart \
  --name "d837ad-test-recap-webapp" \
  --resource-group "d837ad-test-networking"
```

## Permission Management

### View Role Assignments

```bash
# Get automation account managed identity principal ID
PRINCIPAL_ID=$(az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --query "identity.principalId" --output tsv)

# List role assignments for managed identity
az role assignment list --assignee $PRINCIPAL_ID --query "[].{principalName: principalName, roleDefinitionName: roleDefinitionName, scope: scope}" --output table

# List all role assignments for resource group
az role assignment list --resource-group "d837ad-test-networking" --output table
```

### Create Role Assignments

```bash
# Assign Website Contributor role to automation account managed identity
PRINCIPAL_ID=$(az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --query "identity.principalId" --output tsv)

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Website Contributor" \
  --scope "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/d837ad-test-networking"

# Assign Reader role at subscription level
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Reader" \
  --scope "/subscriptions/$(az account show --query id --output tsv)"
```

### Delete Role Assignments

```bash
# Remove specific role assignment
az role assignment delete \
  --assignee $PRINCIPAL_ID \
  --role "Website Contributor" \
  --scope "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/d837ad-test-networking"

# Remove all role assignments for managed identity
az role assignment list --assignee $PRINCIPAL_ID --query "[].id" --output tsv | xargs -I {} az role assignment delete --ids {}
```

## Resource Group Operations

```bash
# List all resources in resource group
az resource list --resource-group "d837ad-test-networking" --output table

# Show resource group details
az group show --name "d837ad-test-networking"

# List resources by type
az resource list --resource-group "d837ad-test-networking" --resource-type "Microsoft.Automation/automationAccounts" --output table
az resource list --resource-group "d837ad-test-networking" --resource-type "Microsoft.Insights/actionGroups" --output table
az resource list --resource-group "d837ad-test-networking" --resource-type "Microsoft.Web/sites" --output table
```

## Testing and Validation

### Health Checks

```bash
# Test webapp health endpoint
curl -I https://d837ad-test-recap-webapp.azurewebsites.net/healthz

# Test with timeout
curl -I https://d837ad-test-recap-webapp.azurewebsites.net/healthz --max-time 10

# Test multiple times
for i in {1..5}; do echo "Test $i:"; curl -I https://d837ad-test-recap-webapp.azurewebsites.net/healthz --max-time 5; echo; done
```

### Resource Validation

```bash
# Validate all required resources exist
echo "Checking Action Group..."
az monitor action-group show --name "d837ad-test-action-group" --resource-group "d837ad-test-networking" --query "name" --output tsv

echo "Checking Automation Account..."
az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --query "name" --output tsv

echo "Checking Runbook..."
az automation runbook show --name "d837ad-{env}-cost-control-runbook" --resource-group "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" --query "name" --output tsv

echo "Checking WebApp..."
az webapp show --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking" --query "name" --output tsv

echo "Checking Budget..."
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation" --query "name" --output tsv
```

## Environment Variables for Scripts

```bash
# Set environment variables for reuse
export RECAP_ENV="test"
export RECAP_RG="d837ad-test-networking"
export RECAP_AUTOMATION="d837ad-test-automation-account"
export RECAP_ACTION_GROUP="d837ad-test-action-group"
export RECAP_WEBAPP="d837ad-test-recap-webapp"
export RECAP_BUDGET="budget-for-d837ad-test-cost-control-automation"

# Use in commands
az webapp show --name $RECAP_WEBAPP --resource-group $RECAP_RG --query "state" --output tsv
az automation job list --resource-group $RECAP_RG --automation-account-name $RECAP_AUTOMATION --output table
```

## Cleanup Commands

```bash
# Complete cleanup (in order)
echo "Deleting Automation Account..."
az automation account delete --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --yes

echo "Cleaning up role assignments..."
# (Role assignments are automatically cleaned up when automation account is deleted)

echo "Deleting Action Group..."
az monitor action-group delete --name "d837ad-test-action-group" --resource-group "d837ad-test-networking"

echo "Webapp resources preserved..."
```

## Troubleshooting Commands

```bash
# Check Azure CLI version and authentication
az --version
az account show

# Test connectivity to Azure APIs
az rest --method GET --url "https://management.azure.com/subscriptions/$(az account show --query id --output tsv)/resourceGroups/d837ad-test-networking?api-version=2021-04-01"

# Debug automation account permissions
az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --query "identity" --output json

# Check recent Azure activity
az monitor activity-log list --resource-group "d837ad-test-networking" --max-events 10 --output table

# Verbose output for debugging
az automation job show --resource-group "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" --job-id "JOB-ID" --debug
```
