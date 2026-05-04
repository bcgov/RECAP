# RECAP Cost Control Setup Guide

Complete step-by-step setup guide for Azure cost monitoring and automated webapp shutdown.

## Prerequisites

- **Azure CLI** installed and authenticated (`az login`)
- **PowerShell 5.1+** or **PowerShell Core 7+**
- **Azure PowerShell modules** (will be installed during setup):
  - `Az.Resources` (for role assignments)
  - `Az.Automation` (for automation account operations)
  - `Az.Monitor` (for action group creation)
  - `Az.Websites` (for webapp operations)
- **Azure subscription** access with permissions to:
  - Create Automation Accounts
  - Create Action Groups
  - Manage Web Apps
  - View Budget information
  - Assign IAM roles

**Important**: Use full subscription IDs, not short names:

- **Test**: `<test-subscription-id>` (d837ad-test - RECAP LLM Responsible...)
- **Production**: `<prod-subscription-id>` (d837ad-prod - RECAP LLM Responsible...)

## Quick Setup (3 Commands)

```powershell
# 1. Deploy infrastructure
.\azure-deploy-cost-control.ps1 -Environment "test"

# 2. Create budget and configure integration (creates budget via REST API, webhook, and links alerts)
.\azure-configure-budget-integration.ps1 -Environment "test"

# 3. Test the system
.\azure-verify-cost-control.ps1 -Environment "test" -DryRun
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure -TestShutdown -DryRun
```

## Quick Setup (3 Commands)

```powershell
# 1. Deploy infrastructure
.\azure-deploy-cost-control.ps1 -Environment "prod"

# 2. Create budget and configure integration (creates budget via REST API, webhook, and links alerts)
.\azure-configure-budget-integration.ps1 -Environment "prod"

# 3. Test the system
.\azure-verify-cost-control.ps1 -Environment "prod" -DryRun
.\azure-verify-cost-control.ps1 -Environment "prod" -CheckInfrastructure -TestShutdown -DryRun
```

## End-to-End Install Runbook

This runbook is organized **by resource**, not by tool. Each step shows the same outcome achieved three ways: **Azure Portal**, **Az CLI**, **PowerShell**. Pick the column that matches the validation pass you are running:

- **Pass A (Portal)** — use the *Azure Portal* sub-step throughout.
- **Pass B (Az CLI)** — use the *Az CLI* sub-step throughout.
- **Pass C (PowerShell scripts)** — use the *PowerShell* sub-step throughout.

Run `test` end-to-end first, then promote to `prod`. Skip any step you have already verified.

### Step 0 — Prerequisites (one-time)

> **Important: Az CLI and Az PowerShell are separate auth stores.** Running `az login` does **not** sign you in to Az PowerShell, and `Connect-AzAccount` does **not** sign you in to the CLI. If a PowerShell cmdlet throws `NullReferenceException` it almost always means `Get-AzContext` is empty — run `Connect-AzAccount` and re-run.

**Azure Portal**

1. Sign in at <https://portal.azure.com>.
2. Confirm the directory and subscription selector shows the `d837ad-test - RECAP LLM Responsible Evaluation And Consolidated` subscription.

**Az CLI**

```powershell
az login
# Select the test environment subscription during az login

# Or use: az account set --subscription "<test-subscription-id>"
az account show --query "{name:name, id:id}" -o table
az extension add --name automation --upgrade
```

**PowerShell**

```powershell
Connect-AzAccount
# Select the test environment subscription during Connect-AzAccount

# Or use: Select-AzSubscription -Subscription "<test-subscription-id>"
Get-AzContext | Select-Object Account, Subscription

# Check if required modules are installed; install if missing. Import modules to session.
Get-InstalledModule -Name Az.Resources, Az.Automation -ErrorAction SilentlyContinue
# Install required modules if not present
Install-Module Az.Resources -Scope CurrentUser -Force
Install-Module Az.Automation -Scope CurrentUser -Force
Import-Module Az.Resources
Import-Module Az.Automation
```

> Canonical owned budget per environment:
>
> | Environment | Budget name | Amount | Alert thresholds |
> | --- | --- | --- | --- |
> | test | `budget-for-d837ad-test-cost-control-automation` | CA$250 / month | 30%, 50%, 80% |
> | prod | `budget-for-d837ad-prod-cost-control-automation` | CA$250 / month | 30%, 50%, 80% |
>
> Do **not** wire automation to `budget-for-d837ad-{env}-from-product-registry` — it is reconciled by an upstream platform job and bindings are silently overwritten.

### Step 1 — Create Action Group

**Azure Portal**

**Test Environment:**

1. Portal → **Monitor** → **Alerts** → **Action groups** → **+ Create**.
2. **Subscription**: `d837ad-test - RECAP LLM Responsible Evaluation And Consolidated`.
3. **Resource group**: `d837ad-test-networking`.
4. **Action group name**: `d837ad-test-action-group`.
5. **Display name**: `CostCtrlGrp`.
6. **Notifications / Actions**: leave empty for now (webhook is added in Step 5).
7. **Review + create** → **Create**.

**Production Environment:**

1. Portal → **Monitor** → **Alerts** → **Action groups** → **+ Create**.
2. **Subscription**: `d837ad-prod - RECAP LLM Responsible Evaluation And Consolidated`.
3. **Resource group**: `d837ad-prod-networking`.
4. **Action group name**: `d837ad-prod-action-group`.
5. **Display name**: `CostCtrlGrp`.
6. **Notifications / Actions**: leave empty for now (webhook is added in Step 5).
7. **Review + create** → **Create**.

**Azure CLI**

**Test Environment:**

```bash
az monitor action-group create \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-action-group" \
  --short-name "CostCtrlGrp"
```

**Production Environment:**

```bash  
az monitor action-group create \
  --resource-group "d837ad-prod-networking" \
  --name "d837ad-prod-action-group" \
  --short-name "CostCtrlGrp"
```

**PowerShell**

**Test Environment:**

```powershell
New-AzActionGroup `
  -ResourceGroupName "d837ad-test-networking" `
  -Name "d837ad-test-action-group" `
  -ShortName "CostCtrlGrp"
```

**Production Environment:**

```powershell
New-AzActionGroup `
  -ResourceGroupName "d837ad-prod-networking" `
  -Name "d837ad-prod-action-group" `
  -ShortName "CostCtrlGrp"
```

### Step 2 — Create Automation Account (with system-assigned managed identity)

**Azure Portal**

**Test Environment:**

1. Portal → **Create a resource** → search **Automation Account** → **Create**.
2. **Resource group**: `d837ad-test-networking`.
3. **Name**: `d837ad-test-automation-account`.
4. **Region**: `Canada East`.
5. **Advanced** tab → **Managed identities** → enable **System-assigned**.
6. **Review + create** → **Create**.

**Production Environment:**

1. Portal → **Create a resource** → search **Automation Account** → **Create**.
2. **Resource group**: `d837ad-prod-networking`.
3. **Name**: `d837ad-prod-automation-account`.
4. **Region**: `Canada East`.
5. **Advanced** tab → **Managed identities** → enable **System-assigned**.
6. **Review + create** → **Create**.

**Azure CLI**

**Test Environment:**

```bash
az automation account create \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-automation-account" \
  --location "Canada East" \
  --sku "Free"

# Enable system-assigned managed identity (az automation extension limitation)
az resource update \
  --resource-group "d837ad-test-networking" \
  --name "d837ad-test-automation-account" \
  --resource-type "Microsoft.Automation/automationAccounts" \
  --set "identity.type=SystemAssigned"
```

**Production Environment:**

```bash
az automation account create \
  --resource-group "d837ad-prod-networking" \
  --name "d837ad-prod-automation-account" \
  --location "Canada East" \
  --sku "Free"

# Enable system-assigned managed identity (az automation extension limitation)
az resource update \
  --resource-group "d837ad-prod-networking" \
  --name "d837ad-prod-automation-account" \
  --resource-type "Microsoft.Automation/automationAccounts" \
  --set "identity.type=SystemAssigned"
```

**PowerShell**

> Requires `Az.Automation`. Install once with `Install-Module Az.Automation -Scope CurrentUser -Force`.

**Test Environment:**

```powershell
New-AzAutomationAccount `
  -ResourceGroupName "d837ad-test-networking" `
  -Name "d837ad-test-automation-account" `
  -Location "Canada East" `
  -AssignSystemIdentity
```

**Production Environment:**

```powershell
New-AzAutomationAccount `
  -ResourceGroupName "d837ad-prod-networking" `
  -Name "d837ad-prod-automation-account" `
  -Location "Canada East" `
  -AssignSystemIdentity
```

### Step 3 — Create + publish the Runbook

The runbook source is in this repo: [cost-control/runbook-content-shutdown.ps1](runbook-content-shutdown.ps1).

**Azure Portal**

1. Automation Account → `d837ad-test-automation-account` → **Process Automation** → **Runbooks** → **+ Create a runbook**.
2. **Name**: `d837ad-test-cost-control-runbook`. **Type**: PowerShell. **Runtime**: 5.1 (or 7.2).
3. Paste the runbook content → **Save** → **Publish**.

**Az CLI** *Pass B finding (2026-04-29): the experimental `az automation runbook create` command returns `NotFound` for the automation account even when `az automation account show` returns `Ok`. Use the **Portal** or **PowerShell** sub-step instead until the extension is stabilised.*

```powershell
# Source file with the runbook PowerShell content
$runbookSource = ".\\runbook-content-shutdown.ps1"

az automation runbook create `
  --resource-group "d837ad-test-networking" `
  --automation-account-name "d837ad-test-automation-account" `
  --name "d837ad-test-cost-control-runbook" `
  --type "PowerShell"

az automation runbook replace-content `
  --resource-group "d837ad-test-networking" `
  --automation-account-name "d837ad-test-automation-account" `
  --name "d837ad-test-cost-control-runbook" `
  --content "@$runbookSource"

az automation runbook publish `
  --resource-group "d837ad-test-networking" `
  --automation-account-name "d837ad-test-automation-account" `
  --name "d837ad-test-cost-control-runbook"
```

**PowerShell** *Pass C verified working (2026-04-29). Requires `Connect-AzAccount` first — see Step 0.*

```powershell
Import-AzAutomationRunbook `
  -ResourceGroupName "d837ad-test-networking" `
  -AutomationAccountName "d837ad-test-automation-account" `
  -Name "d837ad-test-cost-control-runbook" `
  -Path ".\\runbook-content-shutdown.ps1" `
  -Type PowerShell -Published -Force
```

### Step 4 — Assign RBAC roles to the Automation Account managed identity

Grant `Website Contributor` on the resource group (start/stop the webapp) and `Reader` on the subscription (subscription context).

**Azure Portal**

1. Resource Group `d837ad-test-networking` → **Access control (IAM)** → **+ Add → Add role assignment**.
2. Role: **Website Contributor**. Members: **Managed identity** → select the `d837ad-test-automation-account` system-assigned identity. Save.
3. Subscription `d837ad-test` → **Access control (IAM)** → **+ Add → Add role assignment**.
4. Role: **Reader**. Members: same managed identity. Save.

**Az CLI**

```powershell
$principalId = az automation account show `
  --resource-group "d837ad-test-networking" `
  --name "d837ad-test-automation-account" `
  --query "identity.principalId" -o tsv

$subId = az account show --query id -o tsv

az role assignment create `
  --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
  --role "Website Contributor" `
  --scope "/subscriptions/$subId/resourceGroups/d837ad-test-networking"

az role assignment create `
  --assignee-object-id $principalId --assignee-principal-type ServicePrincipal `
  --role "Reader" `
  --scope "/subscriptions/$subId"
```

**PowerShell**

```powershell
$aa = Get-AzAutomationAccount -ResourceGroupName "d837ad-test-networking" -Name "d837ad-test-automation-account"
$principalId = $aa.Identity.PrincipalId
$subId = (Get-AzContext).Subscription.Id

New-AzRoleAssignment -ObjectId $principalId `
  -RoleDefinitionName "Website Contributor" `
  -Scope "/subscriptions/$subId/resourceGroups/d837ad-test-networking"

New-AzRoleAssignment -ObjectId $principalId `
  -RoleDefinitionName "Reader" `
  -Scope "/subscriptions/$subId"
```

### Step 5 — Create Webhook and Action Group Integration (AUTOMATED)

**This step is now automated by `.\azure-configure-budget-integration.ps1`** which handles webhook creation and action group configuration automatically.

**Azure Portal**

1. Runbook `d837ad-test-cost-control-runbook` → **Webhooks** → **+ Add webhook** → **Create new webhook**.
2. **Name**: `cost-control-webhook`. **Enabled**: Yes. **Expires**: +10 years.
3. **Parameters**:
   - `WebAppName` = `d837ad-test-recap-webapp`
   - `ResourceGroupName` = `d837ad-test-networking`
4. Copy the webhook URL.
5. Action Group `d837ad-test-action-group` → **Actions** → **+ Add action** → **Webhook**.
6. **Name**: `cost-control-webhook`. **URI**: paste the URL. **Enable common alert schema**: Yes. Save.

**Az CLI** \u26a0\ufe0f *Pass B finding (2026-04-29): the Az CLI `automation` extension does **not** expose a `webhook` subgroup, and `az monitor action-group update --add-action` rejects the webhook syntax (`list type value expected, got 'webhook'`). Use the **PowerShell** sub-step below (it is the recommended CLI-adjacent path), or the Portal sub-step.*

```powershell
# DOES NOT WORK in current az automation extension:
#   az automation webhook create ...    -> "'webhook' is misspelled or not recognized"
#   az monitor action-group update --add-action webhook ...
#                                       -> "list type value expected, got 'webhook'"
#
# Working CLI-only fallback: create the webhook in PowerShell or Portal,
# then *recreate* the action group via `az monitor action-group create --action webhook`
# (action-group `update` cannot add webhook actions; `create` can):
#
# az monitor action-group delete -g "d837ad-test-networking" -n "d837ad-test-action-group"
# az monitor action-group create `
#   --resource-group "d837ad-test-networking" `
#   --name "d837ad-test-action-group" `
#   --short-name "CostCtrlGrp" `
#   --action webhook cost-control-webhook $webhookUrl useCommonAlertSchema=true
```

**PowerShell** \u2705 *Pass C verified working (2026-04-29). The action-group attach step still uses `az monitor action-group create` because there is no native Az PowerShell cmdlet for adding a webhook receiver to an existing action group.*

```powershell
$expiry = (Get-Date).AddYears(10)
$webhook = New-AzAutomationWebhook `
  -ResourceGroupName "d837ad-test-networking" `
  -AutomationAccountName "d837ad-test-automation-account" `
  -RunbookName "d837ad-test-cost-control-runbook" `
  -Name "cost-control-webhook" `
  -ExpiryTime $expiry -IsEnabled $true -Force `
  -Parameters @{
    WebAppName        = "d837ad-test-recap-webapp"
    ResourceGroupName = "d837ad-test-networking"
  }

# $webhook.WebhookURI is shown only at creation - capture it now
$webhookUrl = $webhook.WebhookURI
$webhookUrl

# Attach to the action group. `update --add-action` does NOT work; recreate the AG with the webhook:
az monitor action-group delete `
  --resource-group "d837ad-test-networking" `
  --name "d837ad-test-action-group"

az monitor action-group create `
  --resource-group "d837ad-test-networking" `
  --name "d837ad-test-action-group" `
  --short-name "CostCtrlGrp" `
  --action webhook cost-control-webhook $webhookUrl useCommonAlertSchema=true
```

> Alternative (Portal) for the action-group attach: Action Group \u2192 **Actions** \u2192 **+ Add action** \u2192 **Webhook** \u2192 paste `$webhookUrl`, enable common alert schema, Save.

### Step 6 — Create owned Budget (Manual Portal Alternative)

**Azure Portal** (Alternative to automated script approach)

**Test Environment:**

1. **Cost Management + Billing** → **Budgets** → **+ Add**.
2. **Scope**: Subscription `d837ad-test - RECAP LLM Responsible Evaluation And Consolidated`
3. **Budget details**:
   - **Name**: `budget-for-d837ad-test-cost-control-automation`
   - **Reset period**: Monthly
   - **Amount**: `250` CAD
   - **Start date**: Current month (or next month if mid-month)
   - **Expiration date**: December 2036 (10-year maximum)
4. **Alert conditions** — Add three alerts:
   - **30% Alert**: Type=Actual, Threshold=30%, Recipients=<firstname.lastname@gov.bc.ca>
   - **50% Alert**: Type=Actual, Threshold=50%, Recipients=<firstname.lastname@gov.bc.ca>  
   - **80% Alert**: Type=Actual, Threshold=80%, Recipients=<firstname.lastname@gov.bc.ca>
5. For each alert, **Action groups** → **Add** → Select `d837ad-test-action-group`
6. **Review + create** → **Create**

**Production Environment:**

1. **Cost Management + Billing** → **Budgets** → **+ Add**.
2. **Scope**: Subscription `d837ad-prod - RECAP LLM Responsible Evaluation And Consolidated`
3. **Budget details**:
   - **Name**: `budget-for-d837ad-prod-cost-control-automation`
   - **Reset period**: Monthly
   - **Amount**: `250` CAD
   - **Start date**: Current month (or next month if mid-month)
   - **Expiration date**: December 2036 (10-year maximum)
4. **Alert conditions** — Add three alerts:
   - **30% Alert**: Type=Actual, Threshold=30%, Recipients=<firstname.lastname@gov.bc.ca>
   - **50% Alert**: Type=Actual, Threshold=50%, Recipients=<firstname.lastname@gov.bc.ca>
   - **80% Alert**: Type=Actual, Threshold=80%, Recipients=<firstname.lastname@gov.bc.ca>
5. For each alert, **Action groups** → **Add** → Select `d837ad-prod-action-group`
6. **Review + create** → **Create**

**Note**: The automated script approach (`.\azure-configure-budget-integration.ps1`) handles this via REST API and is recommended for consistency.

**Az CLI** \u274c *Pass B finding (2026-04-29): `az consumption budget create --notifications` is **not usable** for multi-threshold budgets from this client. Inline JSON collides with PowerShell\u2019s format-string parser (`{0}` braces \u2192 `Error formatting a string`), and the documented `@file` workaround also fails (`unrecognized arguments` \u2014 the CLI does not honour `@file` expansion for this argument). **Use the Portal sub-step.** The CLI is reliable for budget **inspection** (`az consumption budget show`) but not creation with action-group bindings.*

```powershell
# DOES NOT WORK \u2014 left here only to document the failed attempts:
#   az consumption budget create ... --notifications actual_GreaterThanOrEqualTo_30_Percent='{...}'
#
# Reliable verification (read-only) after Portal create:
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation" `
  --query "notifications" -o json
```

**PowerShell** \u274c *Pass C finding (2026-04-29): the current `Az.Billing` module (2.2.0) is **not capable** of creating a multi-threshold budget. `New-AzConsumptionBudgetNotification` does not exist, and `New-AzConsumptionBudget` only accepts a **single** notification per call (`-NotificationKey` / `-NotificationEnabled` / `-NotificationThreshold` \u2014 all singular). It also requires a non-empty `-ContactEmail` even when `-ContactGroup` is supplied (cmdlet prompts and then rejects null). Use the **Portal** sub-step. PowerShell is fine for the initial single-threshold create (e.g. 80%); add 30% and 50% via the Portal.*

```powershell
# Single-threshold creation (works, but does not satisfy the 30/50/80% requirement):
Install-Module -Name Az.Billing -Scope CurrentUser -Force -AllowClobber
Import-Module Az.Billing

$subId = (Get-AzContext).Subscription.Id
$agId  = "/subscriptions/$subId/resourceGroups/d837ad-test-networking/providers/microsoft.insights/actionGroups/d837ad-test-action-group"

New-AzConsumptionBudget `
  -Name "budget-for-d837ad-test-cost-control-automation" `
  -Amount 250 -Category Cost -TimeGrain Monthly `
  -StartDate (Get-Date -Day 1) -EndDate (Get-Date "2036-12-31") `
  -NotificationKey "actual_GreaterThanOrEqualTo_80_Percent" `
  -NotificationEnabled `
  -NotificationThreshold 80 `
  -ContactEmail "owner@example.com" `
  -ContactGroup $agId
# Notes:
# - EndDate maximum is 10 years from StartDate. Use 2036-12-31 (or later StartDate + 10 yrs), NOT 2030.
# - To add the 30% and 50% alerts, fall back to Portal, or (preferred) use the
#   `az rest --method put` recipe in Step 6b — a second `Set-AzConsumptionBudget`
#   call with -NotificationKey overwrites, it does not append.
```

**REST API** *Recommended approach - used by automated scripts*

**Test Environment:**

```powershell
# Set environment variables
$subscriptionId = "5445292b-8313-4272-96aa-f30efd1e1654"  # d837ad-test subscription
$budgetName = "budget-for-d837ad-test-cost-control-automation"
$actionGroupId = "/subscriptions/$subscriptionId/resourcegroups/d837ad-test-networking/providers/microsoft.insights/actiongroups/d837ad-test-action-group"
$contactEmail = "<firstname.lastname@gov.bc.ca>"

# Calculate start date (current month if 1st, otherwise next month)
$currentDate = Get-Date
if ($currentDate.Day -eq 1) {
    $startDate = $currentDate.ToString("yyyy-MM-01T00:00:00Z")
} else {
    $nextMonth = $currentDate.AddMonths(1)
    $startDate = $nextMonth.ToString("yyyy-MM-01T00:00:00Z")
}

# Create budget via REST API
$budgetUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Consumption/budgets/$budgetName" + "?api-version=2023-05-01"

$budgetBody = @{
    properties = @{
        category   = "Cost"
        amount     = 250
        timeGrain  = "Monthly"
        timePeriod = @{
            startDate = $startDate
            endDate   = "2036-12-31T00:00:00Z"
        }
        notifications = @{
            actual_GreaterThanOrEqualTo_30_Percent = @{
                enabled = $true; operator = "GreaterThanOrEqualTo"; threshold = 30
                contactEmails = @($contactEmail); contactGroups = @($actionGroupId)
                notificationLanguage = "en-us"
            }
            actual_GreaterThanOrEqualTo_50_Percent = @{
                enabled = $true; operator = "GreaterThanOrEqualTo"; threshold = 50
                contactEmails = @($contactEmail); contactGroups = @($actionGroupId)
                notificationLanguage = "en-us"
            }
            actual_GreaterThanOrEqualTo_80_Percent = @{
                enabled = $true; operator = "GreaterThanOrEqualTo"; threshold = 80
                contactEmails = @($contactEmail); contactGroups = @($actionGroupId)
                notificationLanguage = "en-us"
            }
        }
    }
} | ConvertTo-Json -Depth 10

$tempFile = "$env:TEMP\budget-test-body.json"
$budgetBody | Out-File -Encoding utf8 -FilePath $tempFile

az rest --method put --url $budgetUrl --headers "Content-Type=application/json" --body "@$tempFile"
Remove-Item $tempFile -Force
```

**Production Environment:**

```powershell
# Set environment variables (update subscription ID for prod)
$subscriptionId = "<prod-subscription-id>"  # d837ad-prod subscription
$budgetName = "budget-for-d837ad-prod-cost-control-automation"  
$actionGroupId = "/subscriptions/$subscriptionId/resourcegroups/d837ad-prod-networking/providers/microsoft.insights/actiongroups/d837ad-prod-action-group"
$contactEmail = "<firstname.lastname@gov.bc.ca>"

# (Use same REST API code as test environment with updated variables)
```

### Step 6b — Edit budget notifications / extend end date (REST PUT)

✅ *Pass C verified working (2026-04-29). This is the **only** reliable way to (a) add/remove individual notification thresholds on an existing budget once the Portal locks them as read-only, and (b) bump the budget end date.*

The Portal often refuses to delete an existing notification threshold once a budget has been edited from multiple tools (the alert row shows but **Delete** is greyed out). The Az CLI / Az PowerShell budget cmdlets cannot express a multi-threshold notifications block in a single call. The Consumption REST API can. Use `az rest --method put` to overwrite the budget definition idempotently.

```powershell
$sub = (Get-AzContext).Subscription.Id
$rg  = "d837ad-test-networking"
$ag  = "/subscriptions/$sub/resourceGroups/$rg/providers/microsoft.insights/actionGroups/d837ad-test-action-group"
$budgetName   = "budget-for-d837ad-test-cost-control-automation"
$contactEmail = "<firstname.lastname@gov.bc.ca>"

# IMPORTANT: startDate for Monthly budgets must be the first day of a month (YYYY-MM-01).
# Pull the existing one first so you don't shift the period:
$startDate = az consumption budget show --budget-name $budgetName --query "timePeriod.startDate" -o tsv

$body = @{
  properties = @{
    category   = "Cost"
    amount     = 250
    timeGrain  = "Monthly"
    timePeriod = @{
      startDate = $startDate         # keep existing start
      endDate   = "2036-12-31T00:00:00Z"   # 10-year max
    }
    notifications = @{
      actual_GreaterThanOrEqualTo_30_Percent = @{
        enabled = $true; operator = "GreaterThanOrEqualTo"; threshold = 30
        contactEmails = @($contactEmail); contactGroups = @($ag); notificationLanguage = "en-us"
      }
      actual_GreaterThanOrEqualTo_50_Percent = @{
        enabled = $true; operator = "GreaterThanOrEqualTo"; threshold = 50
        contactEmails = @($contactEmail); contactGroups = @($ag); notificationLanguage = "en-us"
      }
      actual_GreaterThanOrEqualTo_80_Percent = @{
        enabled = $true; operator = "GreaterThanOrEqualTo"; threshold = 80
        contactEmails = @($contactEmail); contactGroups = @($ag); notificationLanguage = "en-us"
      }
    }
  }
} | ConvertTo-Json -Depth 10

$body | Out-File -Encoding utf8 -FilePath "$env:TEMP\budget-body.json"

az rest --method put `
  --url "https://management.azure.com/subscriptions/$sub/providers/Microsoft.Consumption/budgets/${budgetName}?api-version=2023-05-01" `
  --headers "Content-Type=application/json" `
  --body "@$env:TEMP\budget-body.json"

# Verify
az consumption budget show --budget-name $budgetName `
  --query "{amount:amount, end:timePeriod.endDate, thresholds: notifications.* | [].threshold}" -o json
# Expected: { "amount": 250.0, "end": "2036-12-31T00:00:00Z", "thresholds": [30, 50, 80] }
```

> The PUT body fully replaces the `notifications` map. Any threshold not listed in the body (e.g. a stray 20% alert from earlier testing) is dropped — this is what makes it the canonical "delete a stuck notification" recipe. Existing period-to-date actuals are preserved server-side.

### Step 7 — Validate

Run all three regardless of which path you used to build — they read state, they don't care who wrote it.

**Azure Portal**

- Action Group has a `cost-control-webhook` action.
- Automation Account → **Identity** shows a system-assigned principal ID.
- Subscription → **IAM** shows that principal with **Reader**; resource group → **IAM** shows it with **Website Contributor**.
- Runbook status is **Published**.
- Budget shows three alerts at 30/50/80% all bound to the action group.

**Az CLI**

```powershell
# Action group + webhook actions
az monitor action-group show -g "d837ad-test-networking" -n "d837ad-test-action-group" --query "webhookReceivers"

# Automation account managed identity
az automation account show -g "d837ad-test-networking" -n "d837ad-test-automation-account" --query "identity"

# Role assignments for the MI
$pid = az automation account show -g "d837ad-test-networking" -n "d837ad-test-automation-account" --query "identity.principalId" -o tsv
az role assignment list --assignee $pid --query "[].{role:roleDefinitionName,scope:scope}" -o table

# Runbook published
az automation runbook show -g "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" -n "d837ad-test-cost-control-runbook" --query "{state:state}"

# Webhook exists on the runbook
az automation webhook list -g "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" --query "[].{name:name,enabled:isEnabled,expiry:expiryTime}" -o table

# Budget + notifications
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation" --query "{amount:amount,notifications:notifications}"
```

**PowerShell** *Pass C verified working (2026-04-29) after two `azure-verify-cost-control.ps1` bug fixes:*

- *`-CheckPermissions` now uses `az role assignment list --assignee <id> --all`. Without `--all`, RG-scoped assignments may be hidden by replication/cache and produce a false-negative "Missing: Website Contributor".*
- *`-TestWebhook` now uses `Get-AzAutomationWebhook` (Az.Automation). The Az CLI subgroup `az automation webhook` does not exist (`'webhook' is misspelled or not recognized`).*

```powershell
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure
.\azure-verify-cost-control.ps1 -Environment "test" -CheckPermissions
.\azure-verify-cost-control.ps1 -Environment "test" -CheckBudgetIntegration
.\azure-verify-cost-control.ps1 -Environment "test" -TestWebhook
.\azure-verify-cost-control.ps1 -Environment "test" -DryRun
```

### Step 7b — End-to-end trigger

`azure-verify-cost-control.ps1` only validates **wiring** (resources exist, roles are present, webhook is registered). It does **not** prove that an Action Group budget alert will actually invoke the webhook → runbook → webapp-stop chain. Do this once per environment after Step 7 passes, and again whenever the runbook content, webhook URL, or AG receivers change.

**Option 1 — Portal "Test action group" (recommended; exercises the full chain)** *Pass C verified working (2026-04-29).*

1. Portal → **Monitor** → **Alerts** → **Action groups** → `d837ad-test-action-group` → **Test action group**.
2. **Sample type**: `Budget`. Click **Test**.
3. Within ~30 seconds the AG calls the webhook, which starts a runbook job.

**Option 2 — Start the runbook directly (bypasses AG/webhook hop)**

Use this only if Option 1 fails and you need to isolate runbook vs webhook:

```powershell
Start-AzAutomationRunbook `
  -ResourceGroupName "d837ad-test-networking" `
  -AutomationAccountName "d837ad-test-automation-account" `
  -Name "d837ad-test-cost-control-runbook" `
  -Parameters @{
    WebAppName        = "d837ad-test-recap-webapp"
    ResourceGroupName = "d837ad-test-networking"
  }
```

**Verify (either option)**

```powershell
# 1. Most recent runbook job + transcript
$job = Get-AzAutomationJob `
  -ResourceGroupName "d837ad-test-networking" `
  -AutomationAccountName "d837ad-test-automation-account" `
  -RunbookName "d837ad-test-cost-control-runbook" |
  Sort-Object CreationTime -Descending | Select-Object -First 1
"Job $($job.JobId)  status=$($job.Status)"

Get-AzAutomationJobOutput `
  -ResourceGroupName "d837ad-test-networking" `
  -AutomationAccountName "d837ad-test-automation-account" `
  -Id $job.JobId -Stream Any |
  ForEach-Object { "{0,-10} {1}" -f $_.Type, $_.Summary }

# 2. WebApp is actually stopped
.\webapp-control.ps1 -Environment "test" -Action "Status"

# 3. Restart the webapp (test only - leaves prod alone in the real procedure)
.\webapp-control.ps1 -Environment "test" -Action "Start"

SUCCESS: Connected to Azure using Managed Identity
Current WebApp State: Running
SUCCESS: WebApp stopped. New state: Stopped
SUCCESS: WebApp stopped successfully
=== RECAP Cost Control Shutdown Completed ===
```

> ⚠️ **Az.Websites version drift.** The first emitted `Warning: You're using Az.Websites version 3.1.2. The latest version of Az.Websites is 3.4.2.` It is cosmetic but indicates the Automation Account is pinned to an older module than your local Az PowerShell. Pin the AA to a known version before running E2E in **prod**:
>
> ```powershell
> Import-AzAutomationModule `
>   -ResourceGroupName "d837ad-test-networking" `
>   -AutomationAccountName "d837ad-test-automation-account" `
>   -Name "Az.Websites" `
>   -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/Az.Websites/3.4.2"
>
> # Wait until ProvisioningState = Succeeded (5-10 min)
> Get-AzAutomationModule `
>   -ResourceGroupName "d837ad-test-networking" `
>   -AutomationAccountName "d837ad-test-automation-account" `
>   -Name "Az.Websites" |
>   Select-Object Name, Version, ProvisioningState
> ```

### Step 8 — Shutdown

**Az CLI / PowerShell**

```powershell
.\webapp-control.ps1 -Environment "test" -Action "Status"
.\azure-verify-cost-control.ps1 -Environment "test" -TestShutdown   # actually stops the webapp
.\webapp-control.ps1 -Environment "test" -Action "Start"
```

### Step 9 — Promote to production

Repeat Steps 1 → 7 → **7b** with `-Environment "prod"` / replace `test` → `prod` everywhere. Specifics for prod, learned from Pass A/B/C in `d837ad-test`:

- **Use Portal + PowerShell only.** Skip the Az CLI sub-steps for Step 3 (runbook), Step 5 (webhook), and Step 6 (budget) — all confirmed broken in the current Az CLI `automation` extension and `az consumption` provider. The Portal and PowerShell sub-steps are the verified-working paths.
- **Step 6 budget**: create with PowerShell single-threshold (80%), then immediately run **Step 6b** (REST PUT) to set 30/50/80% and EndDate `2036-12-31T00:00:00Z`. Do **not** rely on the Portal "Edit alerts" UI — once a budget has been touched by multiple tools the Portal can refuse to delete individual notifications.
- **Pin Az.Websites in the prod Automation Account before the first E2E** (see Step 7b "Az.Websites version drift" callout). Use the same pinned version that test was validated on.
- **Run Step 7b in prod** using the AG **Test action group** button (sample type = Budget). This is safe — it triggers the runbook which stops the prod webapp; restart immediately with `.\webapp-control.ps1 -Environment "prod" -Action "Start"`. Capture the runbook job output as part of the change record.
- **Do not** run Step 8 (`-TestShutdown`) against prod — Step 7b already proves the chain works without bypassing the AG/webhook hop.

### Step 10 — Day-2 operations

```powershell
.\monitor-costs.ps1 -Environment "test"            # dashboard
.\monitor-costs.ps1 -Environment "prod" -Brief
.\monitor-costs.ps1 -Environment "prod" -ShowLogs  # runbook job history

.\webapp-control.ps1 -Environment "prod" -Action "Start"   # recovery after auto-shutdown
```

## Detailed Setup Process

### Step 1: Deploy Infrastructure

Deploy the automation infrastructure (Action Group, Automation Account, Runbook):

```powershell
# Test environment
.\azure-deploy-cost-control.ps1 -Environment "test"

# Production environment  
.\azure-deploy-cost-control.ps1 -Environment "prod"
```

**What this creates:**

- **Action Group**: `d837ad-{env}-action-group`
- **Automation Account**: `d837ad-{env}-automation-account`  
- **PowerShell Runbook**: `d837ad-{env}-cost-control-runbook`
- **Managed Identity**: With required permissions
- **PowerShell Modules**: Az.Accounts, Az.Profile, Az.Resources, Az.Websites

**Expected output:**

```Powershell
=== RECAP Cost Control Infrastructure Deployment ===
Environment: test
Resource Group: d837ad-test-networking

Action Group created: d837ad-test-action-group
Automation Account created: d837ad-test-automation-account  
Managed Identity Principal ID: abc123def456...
Assigned Website Contributor role
Assigned Reader role
PowerShell modules imported (async)
Runbook created and published: d837ad-{env}-cost-control-runbook

Next steps:
1. Wait 10-15 minutes for PowerShell modules to import
2. Configure budget integration: .\azure-configure-budget-integration.ps1 -Environment test  
3. Test the system: .\azure-verify-cost-control.ps1 -Environment test -DryRun
```

### Step 2: Wait for Module Import

PowerShell modules import asynchronously. **This is a common timing issue with Azure CLI automation**.

```powershell
# Monitor module import status
az automation module list --resource-group "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" --query "[].{name: name, importState: importState}" --output table
```

Wait until all modules show `ImportState: "ContentDownloaded"` or `"Available"`. **This can take 15-20 minutes and is why manual Portal approach is more reliable**.

### Step 3: Configure Budget Integration

#### Option A: PowerShell Script (Provides Instructions)

```powershell
.\azure-azure-configure-budget-integration.ps1 -Environment "test"
```

This script will guide you through the manual Azure Portal configuration.

#### Option B: Manual Azure Portal Configuration

**3.1 Create Webhook (Azure Portal)**

1. Navigate to: **Azure Portal → Automation Accounts → d837ad-test-automation-account**
2. Click: **Webhooks** (left menu)
3. Click: **Add Webhook**
4. **Name**: `cost-control-webhook`
5. **Enabled**: Yes
6. **Expires**: Set to 10 years from now (maximum allowed)
7. **Runbook**: Select `d837ad-{env}-cost-control-runbook`
8. **Parameters**:
   - `WebAppName`: `d837ad-test-recap-webapp`
   - `ResourceGroupName`: `d837ad-test-networking`
9. **Copy the webhook URL** (save it securely!)
10. Click: **Create**

**3.2 Create Owned Budget and Link Action Group (Azure Portal)**

1. Navigate to: **Cost Management + Billing → Budgets → + Add**
2. **Name**: `budget-for-d837ad-test-cost-control-automation`
3. **Reset period**: Monthly, **Amount**: `250` CAD, **Scope**: Subscription `d837ad-test`
4. **Filters**: None
5. **Alert conditions** — add three alerts, all wired to action group `d837ad-test-action-group`:
   - 30% (early warning)
   - 50% (investigate)
   - 80% (triggers webapp shutdown)
6. **Alert recipients**: Add team email addresses as needed
7. Click: **Save**

> Do not attach automation to `budget-for-d837ad-{env}-from-product-registry` — that budget is reconciled by an upstream platform job and any action-group binding may be silently removed.

#### Azure CLI Alternative (Budget Integration)

```bash
# Get action group resource ID
ACTION_GROUP_ID="/subscriptions/$(az account show --query id --output tsv)/resourcegroups/d837ad-test-networking/providers/microsoft.insights/actiongroups/d837ad-test-action-group"

# Update owned cost-control budget with action group (80% threshold)
az consumption budget update \
  --budget-name "budget-for-d837ad-test-cost-control-automation" \
  --notifications actual_GreaterThanOrEqualTo_80_Percent='{
    "enabled": true,
    "operator": "GreaterThanOrEqualTo", 
    "threshold": 80,
    "contactEmails": [],
    "contactGroups": ["'$ACTION_GROUP_ID'"]
  }'
```

### Step 4: Test the System

**4.1 Validate Infrastructure**

```powershell
# Test all components exist and have correct permissions
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure
```

**4.2 Test Budget Integration**

```powershell
# Verify budget alerts are linked to action group
.\azure-verify-cost-control.ps1 -Environment "test" -CheckBudgetIntegration
```

**4.3 Test Automation (Dry Run)**

```powershell
# Test runbook execution without stopping webapp
.\azure-verify-cost-control.ps1 -Environment "test" -DryRun
```

**4.4 Test Shutdown Capability** (Use with caution!)

```powershell
# Test actual runbook execution (will stop webapp if running)
.\azure-verify-cost-control.ps1 -Environment "test" -TestShutdown
```

### Step 5: Production Deployment

Repeat steps 1-4 for production environment:

```powershell
# Deploy production infrastructure
.\azure-deploy-cost-control.ps1 -Environment "prod"

# Wait for modules to import (10-15 minutes)

# Configure production budget integration
.\azure-configure-budget-integration.ps1 -Environment "prod"

# Test production system (DRY RUN ONLY!)
.\azure-verify-cost-control.ps1 -Environment "prod" -DryRun
```

## Environment-Specific Configuration

### Test Environment

- **Budget**: `budget-for-d837ad-test-cost-control-automation` ($250 CAD, owned)
- **Alert Thresholds**: 30%, 50%, 80% (shutdown at 80% = $200 CAD)
- **WebApp**: `d837ad-test-recap-webapp`
- **Action**: Stop webapp when 80% threshold exceeded

### Production Environment  

- **Budget**: `budget-for-d837ad-prod-cost-control-automation` ($250 CAD, owned)
- **Alert Thresholds**: 30%, 50%, 80% (shutdown at 80% = $200 CAD)
- **WebApp**: `d837ad-prod-recap-webapp`
- **Action**: Stop webapp when 80% threshold exceeded

## Ongoing Operations

### Monitor Costs

```powershell
# Real-time cost monitoring dashboard
.\monitor-costs.ps1 -Environment "test"

# Brief status check
.\monitor-costs.ps1 -Environment "test" -Brief

# Show automation logs  
.\monitor-costs.ps1 -Environment "test" -ShowLogs
```

### Manual WebApp Control

```powershell
# Check webapp status
.\webapp-control.ps1 -Environment "test" -Action "Status"

# Start webapp
.\webapp-control.ps1 -Environment "test" -Action "Start"

# Stop webapp  
.\webapp-control.ps1 -Environment "test" -Action "Stop"

# Restart webapp
.\webapp-control.ps1 -Environment "test" -Action "Restart"
```

### System Testing

```powershell
# Full system test
.\azure-verify-cost-control.ps1 -Environment "test"

# Test specific components
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure
.\azure-verify-cost-control.ps1 -Environment "test" -CheckPermissions
.\azure-verify-cost-control.ps1 -Environment "test" -CheckBudgetIntegration
```

## Troubleshooting

### Common Issues

**Issue**: "Runbook execution fails with authentication error"
**Solution**:

```powershell
# Check managed identity permissions
.\azure-verify-cost-control.ps1 -Environment "test" -CheckPermissions

# Verify automation account has system-assigned managed identity enabled
az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking" --query "identity"
```

**Issue**: "Budget alerts not triggering automation"
**Solution**:

```powershell
# Verify budget-action group linkage
.\azure-configure-budget-integration.ps1 -Environment "test" -Validate

# Check action group configuration in Azure Portal
az monitor action-group show --name "d837ad-test-action-group" --resource-group "d837ad-test-networking"
```

**Issue**: "PowerShell modules not available in runbook"
**Solution**:

```powershell
# Check module import status
az automation module list --resource-group "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" --output table

# Reimport modules if needed
az automation module import --resource-group "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account" --name "Az.Accounts"
```

**Issue**: "Webhook not found"
**Solution**:

1. Create webhook manually in Azure Portal (see Step 3.1 above)
2. Or use Azure CLI/REST API to create webhook programmatically

### Validation Commands

```powershell
# Check all Azure resources exist
az monitor action-group show --name "d837ad-test-action-group" --resource-group "d837ad-test-networking"
az automation account show --name "d837ad-test-automation-account" --resource-group "d837ad-test-networking"  
az automation runbook show --name "d837ad-{env}-cost-control-runbook" --resource-group "d837ad-test-networking" --automation-account-name "d837ad-test-automation-account"

# Check budget and current spend (owned cost-control budget)
az consumption budget show --budget-name "budget-for-d837ad-test-cost-control-automation"

# Check webapp status
az webapp show --name "d837ad-test-recap-webapp" --resource-group "d837ad-test-networking" --query "{state: state, availabilityState: availabilityState}"

# Test webapp health
curl -I https://d837ad-test-recap-webapp.azurewebsites.net/healthz
```

## Cleanup

To remove all cost control resources:

```powershell
# Remove everything (including action group)
.\cleanup-cost-control.ps1 -Environment "test" -Force

# Remove automation but keep action group
.\cleanup-cost-control.ps1 -Environment "test" -KeepActionGroup -Force

# Preview what would be deleted
.\cleanup-cost-control.ps1 -Environment "test" -WhatIf
```

## Key Learnings from Production Experience

*Consolidated 2026-04-29 from Pass A (Portal), Pass B (Az CLI), Pass C (PowerShell + REST) on `d837ad-test`. Each row is empirically verified.*

### Default Budgets

- **Test (owned, canonical)**: `budget-for-d837ad-test-cost-control-automation` (CA$250, monthly, alerts 30/50/80%)
- **Production (owned, canonical)**: `budget-for-d837ad-prod-cost-control-automation` (CA$250, monthly, alerts 30/50/80%)
- **Platform (read-only reference)**: `budget-for-d837ad-{env}-from-product-registry` — do **not** wire automation here; reconciled by an upstream platform job and any action-group binding can be silently overwritten.
- **Budget end date max is 10 years from start date.** `2030-12-31` is wrong; use `2036-12-31T00:00:00Z` (or `<startDate> + 10y`).

### Tool Capability Matrix

| Step | Resource | Portal | Az CLI | Az PowerShell | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 | Action Group (create) | ✅ | ✅ | ✅ | All three work; short name ≤12 chars |
| 2 | Automation Account + System MI | ✅ | ⚠️ 2-step | ✅ | Az CLI: `account create` then `az resource update --set identity.type=SystemAssigned`; `--assign-identity` flag is not honoured by the experimental extension |
| 3 | Runbook (create + publish) | ✅ | ❌ | ✅ | `az automation runbook create` returns `NotFound` even on a healthy account. Use `Import-AzAutomationRunbook -Published -Force` |
| 4 | RBAC role assignment | ✅ | ✅ | ✅ | All three work |
| 5 | Webhook on runbook | ✅ | ❌ | ✅ | `az automation webhook` subgroup does not exist. Use `New-AzAutomationWebhook`. **URI is shown only at creation — capture it immediately** |
| 5 | Attach webhook to Action Group | ✅ | ⚠️ recreate | ❌ no cmdlet | `az monitor action-group update --add-action webhook` rejects with `list type value expected, got 'webhook'`. Workaround: `delete` + `create --action webhook ...`. Az PowerShell has no native cmdlet for this |
| 6 | Budget create (multi-threshold) | ✅ | ❌ | ❌ single only | `az consumption budget create --notifications` cannot ingest multi-threshold JSON (PowerShell `{0}` format-parser collision; `@file` returns "unrecognized arguments"). `New-AzConsumptionBudget` only accepts one notification per call and requires non-empty `-ContactEmail` |
| 6b | Budget edit (add/remove threshold, extend EndDate) | ⚠️ | ✅ via REST | — | Portal Delete on a notification is often greyed out once a budget has been touched by multiple tools. Use `az rest --method put` against `Microsoft.Consumption/budgets` (api 2023-05-01). Idempotent; preserves period-to-date actuals |
| 6 | Budget inspect | ✅ | ✅ | ✅ | All three work; use `az consumption budget show` for scripting |
| 7 | Validate (read-only) | ✅ | ✅ | ✅ | `azure-verify-cost-control.ps1` works after the two Pass C fixes: `--all` on `az role assignment list`, and `Get-AzAutomationWebhook` instead of the nonexistent CLI subgroup |
| 7b | E2E | ✅ | — | ✅ | AG **Test action group** button (sample type = Budget) is the canonical proof. `Start-AzAutomationRunbook` is the bypass for isolating runbook vs webhook |

### Auth & Module Gotchas

- **`az login` and `Connect-AzAccount` are separate auth stores.** Az PowerShell cmdlets throwing `NullReferenceException` almost always means `Get-AzContext` is empty — run `Connect-AzAccount` and re-run.
- **`Az.Automation` is not installed by default** with `Az.Accounts`. Run `Install-Module Az.Automation -Scope CurrentUser -Force` once before Step 3.
- **`Az.Billing` 2.2.0** lacks `New-AzConsumptionBudgetNotification`; `New-AzConsumptionBudget` is single-threshold only.
- **Automation Account modules drift.** First runbook job on a fresh AA will warn `Az.Websites version 3.1.2 ... latest is 3.4.2`. Pin the AA via `Import-AzAutomationModule -ContentLinkUri https://www.powershellgallery.com/api/v2/package/Az.Websites/3.4.2` before E2E in prod (5–10 min, watch `ProvisioningState`).

### Recommended Approach (Updated for Automation)

**Automated Script Approach (Recommended):**

```powershell
# Complete automation - no manual steps required
.\azure-deploy-cost-control.ps1 -Environment "test"                                    # Infrastructure
.\azure-configure-budget-integration.ps1 -Environment "test"                           # Budget + Integration  
.\azure-verify-cost-control.ps1 -Environment "test" -CheckInfrastructure -TestShutdown -DryRun  # Validation
```

**Manual Approach Alternatives:**

| Component | Azure Portal | Azure CLI | PowerShell | REST API |
| ----------- | -------------- | ----------- | ------------ | ---------- |
| **Action Group** | ✅ Reliable | ✅ Reliable | ✅ Reliable | ✅ Reliable |
| **Automation Account** | ✅ Reliable | ⚠️ 2-step process | ✅ Reliable | ✅ Reliable |
| **Runbook Deployment** | ✅ Manual copy/paste | ❌ Extension issues | ✅ Reliable | N/A |
| **RBAC Assignments** | ✅ Manual clicking | ✅ Reliable | ✅ Reliable | ✅ Reliable |
| **Webhook Creation** | ✅ Manual setup | ❌ No CLI support | ✅ Reliable | N/A |
| **Budget Creation** | ✅ Reliable | ❌ Preview/broken | ❌ Single threshold only | ✅ Reliable |
| **Budget Alert Linking** | ⚠️ Portal locks alerts | ❌ JSON parsing issues | ❌ Limited | ✅ Reliable |

**What's Automated in Scripts:**

- Action Group and Automation Account creation
- PowerShell runbook deployment with proper parameters
- Webhook creation and action group integration  
- Budget creation via REST API with proper date handling
- Budget alert configuration (30%, 50%, 80% thresholds linked to action group)
- RBAC role assignments (Website Contributor + Reader)
- Comprehensive validation and error handling

**Manual Alternatives Available For:**

- All components can be created manually via Azure Portal
- Troubleshooting when automation fails
- Understanding the underlying Azure resources and configuration
- Custom modifications beyond standard setup

**Tool Reliability Summary:**

- **REST API**: Most reliable for budget operations
- **PowerShell Az modules**: Most reliable for automation account operations  
- **Azure CLI**: Good for action groups and validation, avoid for budgets/webhooks
- **Azure Portal**: Most reliable for manual operations, but time-consuming

## Support

For issues:

1. Run diagnostics: `.\azure-verify-cost-control.ps1 -Environment "test"`
2. Check logs: `.\monitor-costs.ps1 -Environment "test" -ShowLogs`  
3. Review Azure Portal: Automation Account → Jobs
4. Manual recovery: `.\webapp-control.ps1 -Environment "test" -Action "Start"`
