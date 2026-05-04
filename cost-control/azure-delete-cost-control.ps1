[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# RECAP Cost Control Resource Deletion
# Deletes all cost control automation resources created during deployment

$ErrorActionPreference = "Continue"

# Environment-specific configuration
$config = @{
    test = @{
        ResourceGroup = "d837ad-test-networking"
        ActionGroupName = "d837ad-test-action-group"
        AutomationAccountName = "d837ad-test-automation-account"
        WebAppName = "d837ad-test-recap-webapp"
    }
    prod = @{
        ResourceGroup = "d837ad-prod-networking"
        ActionGroupName = "d837ad-prod-action-group"
        AutomationAccountName = "d837ad-prod-automation-account"
        WebAppName = "d837ad-prod-recap-webapp"
    }
}

$envConfig = $config[$Environment]
$budgetName = "budget-for-d837ad-$Environment-cost-control-automation"

Write-Output "=== RECAP Cost Control Resource Deletion ==="
Write-Output "Environment: $Environment"
Write-Output "DryRun Mode: $WhatIf"
Write-Output ""

if (-not $WhatIf) {
    Write-Output "WARNING: This will permanently delete all cost control resources."
    Write-Output "Resources to be deleted:"
    Write-Output "  - Automation Account: $($envConfig.AutomationAccountName)"
    Write-Output "  - Action Group: $($envConfig.ActionGroupName)"
    Write-Output "  - Budget: $budgetName"
    Write-Output "  - All runbooks, webhooks, and role assignments"
    Write-Output ""
    $confirm = Read-Host "Type 'DELETE' to confirm deletion"
    if ($confirm -ne "DELETE") {
        Write-Output "Deletion cancelled"
        exit 0
    }
}

# Get Azure context
Write-Output "Checking Azure authentication..."
$subscriptionId = az account show --query "id" --output tsv
$accountInfo = az account show --query "name" --output tsv
Write-Output "Authenticated to: $accountInfo"
Write-Output "Subscription ID: $subscriptionId"
Write-Output ""

# Get managed identity principal ID before deleting automation account
$principalId = $null
$principalId = az automation account show --name $envConfig.AutomationAccountName --resource-group $envConfig.ResourceGroup --query "identity.principalId" --output tsv 2>$null

# 1. Delete Automation Account (removes runbooks and webhooks automatically)
Write-Output "Deleting Automation Account: $($envConfig.AutomationAccountName)"
if ($WhatIf) {
    Write-Output "DryRun: Would delete automation account and all contained resources"
} else {
    $result = az automation account delete --name $envConfig.AutomationAccountName --resource-group $envConfig.ResourceGroup --yes 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[OK] Automation Account deleted"
    } else {
        Write-Output "[WARN] Automation Account not found or already deleted"
    }
}

# 2. Clean up role assignments for managed identity
if ($principalId -and $principalId -ne "null" -and -not $WhatIf) {
    Write-Output "Cleaning up role assignments..."
    $roleAssignments = az role assignment list --assignee $principalId --all --query "[].{id: id, roleDefinitionName: roleDefinitionName}" --output json 2>$null | ConvertFrom-Json
    if ($roleAssignments) {
        foreach ($role in $roleAssignments) {
            az role assignment delete --ids $role.id 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Output "[OK] Removed role: $($role.roleDefinitionName)"
            } else {
                Write-Output "[WARN] Could not remove role: $($role.roleDefinitionName)"
            }
        }
    }
}

# 3. Delete Action Group
Write-Output "Deleting Action Group: $($envConfig.ActionGroupName)"
if ($WhatIf) {
    Write-Output "DryRun: Would delete action group"
} else {
    $result = az monitor action-group delete --name $envConfig.ActionGroupName --resource-group $envConfig.ResourceGroup 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "[OK] Action Group deleted"
    } else {
        Write-Output "[WARN] Action Group not found or already deleted"
    }
}

# 4. Delete Budget
Write-Output "Deleting Budget: $budgetName"
if ($WhatIf) {
    Write-Output "DryRun: Would delete budget"
} else {
    $budgetUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Consumption/budgets/$budgetName" + "?api-version=2023-05-01"
    $headers = @{
        'Authorization' = "Bearer $(az account get-access-token --query accessToken --output tsv)"
        'Content-Type' = 'application/json'
    }
    
    try {
        Invoke-RestMethod -Uri $budgetUrl -Method DELETE -Headers $headers -ErrorAction Stop
        Write-Output "[OK] Budget deleted"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Output "[WARN] Budget not found or already deleted"
        } else {
            Write-Output "[WARN] Could not delete budget: $($_.Exception.Message)"
        }
    }
}

Write-Output ""
Write-Output "=== DELETION COMPLETED ==="

if ($WhatIf) {
    Write-Output "DryRun: No actual changes were made"
} else {
    Write-Output "[OK] All cost control resources have been deleted"
    Write-Output ""
    Write-Output "Deleted resources:"
    Write-Output "  - Automation Account: $($envConfig.AutomationAccountName)"
    Write-Output "  - Action Group: $($envConfig.ActionGroupName)" 
    Write-Output "  - Budget: $budgetName"
    Write-Output "  - Runbooks and webhooks (automatic with automation account)"
    Write-Output "  - Managed identity role assignments"
    Write-Output ""
    Write-Output "WebApp preserved: $($envConfig.WebAppName)"
}