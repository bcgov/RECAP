[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [string]$BudgetName,
    
    [Parameter(Mandatory = $false)]
    [switch]$Validate,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# RECAP Budget Integration Configuration
# Links existing budgets to cost control automation

$ErrorActionPreference = "Stop"

# Environment-specific configuration
$config = @{
    test = @{
        ResourceGroup = "d837ad-test-networking"
        ActionGroupName = "d837ad-test-action-group"
        AutomationAccountName = "d837ad-test-automation-account"
        DefaultBudgetName = "budget-for-d837ad-test-cost-control-automation"
        WebAppName = "d837ad-test-recap-webapp"
        Thresholds = @{
            Warning = 60
            Critical = 80
            Emergency = 90
        }
    }
    prod = @{
        ResourceGroup = "d837ad-prod-networking"
        ActionGroupName = "d837ad-prod-action-group"
        AutomationAccountName = "d837ad-prod-automation-account"
        DefaultBudgetName = "budget-for-d837ad-prod-cost-control-automation"
        WebAppName = "d837ad-prod-recap-webapp"
        Thresholds = @{
            Warning = 70
            Critical = 85
            Emergency = 90
        }
    }
}

$envConfig = $config[$Environment]
if (-not $envConfig) {
    throw "Invalid environment: $Environment"
}

# Use provided budget name or default
$targetBudgetName = if ($BudgetName) { $BudgetName } else { $envConfig.DefaultBudgetName }

Write-Output "=== RECAP Budget Integration Configuration ==="
Write-Output "Environment: $Environment"
Write-Output "Budget Name: $targetBudgetName"
Write-Output "Action Group: $($envConfig.ActionGroupName)"
Write-Output "DryRun Mode: $WhatIf"
Write-Output "Validate Mode: $Validate"
Write-Output ""

try {
    # Verify Azure CLI authentication
    Write-Output "Verifying Azure CLI authentication..."
    $context = az account show --query "{name: name, id: id, user: user}" --output json | ConvertFrom-Json
    if (-not $context) {
        throw "Not authenticated to Azure CLI. Run 'az login' first."
    }
    Write-Output "Authenticated as: $($context.user.name)"
    Write-Output "Authenticated to: $($context.name)"
    Write-Output "Subscription ID: $($context.id)"
    
    # Use authenticated user email for notifications
    $userEmail = if ($context.user.name -match "@") { $context.user.name } else { "<firstname.lastname@gov.bc.ca>" }
    Write-Output "Contact Email: $userEmail"
    Write-Output ""

    # Check if budget exists, create if missing
    Write-Output "Checking budget: $targetBudgetName"
    
    # Use REST API to check budget (more reliable than Azure CLI)
    $subscriptionId = $context.id
    $budgetUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Consumption/budgets/$targetBudgetName" + "?api-version=2023-05-01"
    
    # Check if budget exists (suppress errors)
    $ErrorActionPreference = "SilentlyContinue"
    $budgetCheckResult = az rest --method get --url $budgetUrl --output json 2>$null
    $budgetCheckExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    
    if ($budgetCheckExitCode -eq 0 -and $budgetCheckResult) {
        $budgetInfo = $budgetCheckResult | ConvertFrom-Json
        Write-Output "Budget found:"
        Write-Output "  Amount: $($budgetInfo.properties.amount) CAD"
        Write-Output "  Time Grain: $($budgetInfo.properties.timeGrain)"
        Write-Output "  Current Spend: $($budgetInfo.properties.currentSpend.amount) CAD"
        
        $spendPercentage = [math]::Round(($budgetInfo.properties.currentSpend.amount / $budgetInfo.properties.amount) * 100, 2)
        Write-Output "  Current Usage: $spendPercentage%"
        Write-Output ""
    } else {
        Write-Output "Budget not found, creating via REST API..."
        Write-Output ""
        
        if (-not $WhatIf) {
            # Create budget via REST API (more reliable than Azure CLI)  
            $budgetCreateUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Consumption/budgets/$targetBudgetName" + "?api-version=2023-05-01"
            
            # Calculate start date (current month if 1st, otherwise next month)
            $currentDate = Get-Date
            if ($currentDate.Day -eq 1) {
                $startDate = $currentDate.ToString("yyyy-MM-01T00:00:00Z")
            } else {
                $nextMonth = $currentDate.AddMonths(1)
                $startDate = $nextMonth.ToString("yyyy-MM-01T00:00:00Z")
            }
            $endDate = "2036-12-31T00:00:00Z"  # 10-year maximum
            
            # Create basic budget (alerts will be configured later in this script)
            $budgetBody = @{
                properties = @{
                    category   = "Cost"
                    amount     = 250
                    timeGrain  = "Monthly"
                    timePeriod = @{
                        startDate = $startDate
                        endDate   = $endDate
                    }
                    notifications = @{
                        actual_GreaterThanOrEqualTo_80_Percent = @{
                            enabled = $true
                            operator = "GreaterThanOrEqualTo"
                            threshold = 80
                            contactEmails = @($userEmail)
                            contactGroups = @()
                            notificationLanguage = "en-us"
                        }
                    }
                }
            } | ConvertTo-Json -Depth 10

            $tempFile = "$env:TEMP\budget-create-body.json"
            $budgetBody | Out-File -Encoding utf8 -FilePath $tempFile

            Write-Output "Creating budget via REST API..."
            az rest --method put --url $budgetCreateUrl --headers "Content-Type=application/json" --body "@$tempFile"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Output "  Budget created successfully!"
                Write-Output "  Name: $targetBudgetName"
                Write-Output "  Amount: 250 CAD/month"
                Write-Output "  Period: $startDate to $endDate"
                Write-Output ""
            } else {
                throw "Budget creation failed via REST API"
            }
            
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Check action group exists
    Write-Output "Checking action group: $($envConfig.ActionGroupName)"
    try {
        $actionGroupInfo = az monitor action-group show --name $envConfig.ActionGroupName --resource-group $envConfig.ResourceGroup --query "{name: name, enabled: enabled}" --output json | ConvertFrom-Json
        Write-Output "Action Group found: $($actionGroupInfo.name) (Enabled: $($actionGroupInfo.enabled))"
        Write-Output ""
    } catch {
        throw "Action Group '$($envConfig.ActionGroupName)' not found. Run azure-deploy-cost-control.ps1 first."
    }

    # Check automation account and get webhook URL
    Write-Output "Checking automation infrastructure..."
    try {
        $automationInfo = az automation account show --name $envConfig.AutomationAccountName --resource-group $envConfig.ResourceGroup --query "{name: name, state: state}" --output json | ConvertFrom-Json
        Write-Output "Automation Account: $($automationInfo.name) (State: $($automationInfo.state))"
        
        # Check if webhook exists using PowerShell (more reliable)
        try {
            Import-Module Az.Automation -Force
            $existingWebhook = Get-AzAutomationWebhook -ResourceGroupName $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName -Name "cost-control-webhook" -ErrorAction SilentlyContinue
            
            if ($existingWebhook) {
                Write-Output "Webhook found: $($existingWebhook.Name)"
                Write-Output "Webhook is enabled: $($existingWebhook.IsEnabled)"
                Write-Output "Webhook expires: $($existingWebhook.ExpiryTime.ToString('yyyy-MM-dd'))"
                $webhookUrl = $existingWebhook.Uri
                Write-Output ""
            } else {
                $webhookUrl = $null
            }
        } catch {
            Write-Output "Could not check webhook status: $($_.Exception.Message)"
            $webhookUrl = $null
        }
        
        if (-not $webhookUrl) {
            Write-Output "Creating webhook using PowerShell..."
            if (-not $WhatIf) {
                try {
                    # Import required module
                    Import-Module Az.Automation -Force
                    
                    # Create webhook with 10-year expiry
                    $expiry = (Get-Date).AddYears(10)
                    $webhook = New-AzAutomationWebhook `
                        -ResourceGroupName $envConfig.ResourceGroup `
                        -AutomationAccountName $envConfig.AutomationAccountName `
                        -RunbookName "d837ad-$Environment-cost-control-runbook" `
                        -Name "cost-control-webhook" `
                        -ExpiryTime $expiry -IsEnabled $true -Force `
                        -Parameters @{
                            WebAppName        = $envConfig.WebAppName
                            ResourceGroupName = $envConfig.ResourceGroup
                        }
                    
                    $webhookUrl = $webhook.WebhookURI
                    Write-Output "Webhook created successfully"
                    Write-Output "Webhook URL: $webhookUrl"
                    Write-Output ""
                    
                    # Attach to action group (requires recreating the action group)
                    Write-Output "Attaching webhook to action group..."
                    
                    # Delete existing action group
                    az monitor action-group delete `
                        --resource-group $envConfig.ResourceGroup `
                        --name $envConfig.ActionGroupName
                    
                    # Recreate action group with webhook
                    az monitor action-group create `
                        --resource-group $envConfig.ResourceGroup `
                        --name $envConfig.ActionGroupName `
                        --short-name "CostCtrlGrp" `
                        --action webhook cost-control-webhook $webhookUrl useCommonAlertSchema=true
                    
                    Write-Output "Action group updated with webhook"
                    Write-Output ""
                } catch {
                    Write-Output "[ERROR] Failed to create webhook: $_"
                    Write-Output "Falling back to manual configuration:"
                    Write-Output "1. Navigate to: Automation Account → $($envConfig.AutomationAccountName) → Webhooks"
                    Write-Output "2. Create new webhook for runbook: d837ad-$Environment-cost-control-runbook"
                    Write-Output "3. Set expiry to 10 years (maximum allowed)"
                    Write-Output "4. Parameters: WebAppName=$($envConfig.WebAppName), ResourceGroupName=$($envConfig.ResourceGroup)"
                    Write-Output "5. Copy webhook URL and manually attach to action group"
                    Write-Output ""
                }
            } else {
                Write-Output "[DryRun] Would create webhook and attach to action group"
            }
        }
    } catch {
        throw "Automation Account '$($envConfig.AutomationAccountName)' not found. Run azure-deploy-cost-control.ps1 first."
    }

    # Display current budget notifications
    Write-Output "Current budget alert configuration:"
    try {
        $notifications = az consumption budget show --budget-name $targetBudgetName --query "notifications" --output json | ConvertFrom-Json
        
        if ($notifications) {
            $notificationKeys = $notifications | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            foreach ($key in $notificationKeys) {
                $notification = $notifications.$key
                Write-Output "  Alert: $key"
                Write-Output "    Enabled: $($notification.enabled)"
                Write-Output "    Threshold: $($notification.threshold)%"
                Write-Output "    Contact Groups: $($notification.contactGroups -join ', ')"
                Write-Output ""
            }
        } else {
            Write-Output "  No notifications configured"
            Write-Output ""
        }
    } catch {
        Write-Output "  Unable to retrieve notification configuration"
        Write-Output ""
    }

    if ($Validate) {
        Write-Output "=== VALIDATION RESULTS ==="
        
        # Check if action group is linked to budget
        $actionGroupId = "/subscriptions/$($context.id)/resourcegroups/$($envConfig.ResourceGroup)/providers/microsoft.insights/actiongroups/$($envConfig.ActionGroupName)"
        $isLinked = $false
        
        if ($notifications) {
            foreach ($key in $notificationKeys) {
                $notification = $notifications.$key
                if ($notification.contactGroups -contains $actionGroupId) {
                    $isLinked = $true
                    Write-Output "[SUCCESS] Action group is linked to budget alert: $key"
                }
            }
        }
        
        if (-not $isLinked) {
            Write-Output "[WARNING] Action group is NOT linked to any budget alerts"
            Write-Output "Manual configuration required in Azure Portal"
        }
        
        # Check permissions
        Write-Output ""
        Write-Output "Checking automation account permissions..."
        try {
            $principalId = az automation account show --name $envConfig.AutomationAccountName --resource-group $envConfig.ResourceGroup --query "identity.principalId" --output tsv
            
            if ($principalId) {
                $roleAssignments = az role assignment list --assignee $principalId --query "[].{principalName: principalName, roleDefinitionName: roleDefinitionName}" --output json | ConvertFrom-Json
                
                if ($roleAssignments) {
                    Write-Output "Role assignments found:"
                    foreach ($role in $roleAssignments) {
                        Write-Output "  - $($role.roleDefinitionName)"
                    }
                } else {
                    Write-Output "[WARNING] No role assignments found for automation account"
                }
            } else {
                Write-Output "[WARNING] Automation account does not have managed identity enabled"
            }
        } catch {
            Write-Output "[WARNING] Could not check automation account permissions"
        }
        
        Write-Output ""
    }

    if (-not $WhatIf -and -not $Validate) {
        # Link budget alerts to action group via REST API (more reliable than manual portal steps)
        Write-Output "=== LINKING BUDGET ALERTS TO ACTION GROUP ==="
        Write-Output ""
        
        try {
            # Action group resource ID
            $actionGroupId = "/subscriptions/$($context.id)/resourcegroups/$($envConfig.ResourceGroup)/providers/microsoft.insights/actiongroups/$($envConfig.ActionGroupName)"
            
            # Get existing budget to preserve settings
            $budgetUrl = "https://management.azure.com/subscriptions/$($context.id)/providers/Microsoft.Consumption/budgets/$targetBudgetName" + "?api-version=2023-05-01"
            $budgetJson = az rest --method get --url $budgetUrl --output json
            $budget = $budgetJson | ConvertFrom-Json
            
            Write-Output "Updating budget with action group linkage..."
            
            # Update budget with all thresholds linked to action group
            # NOTE: This REPLACES the entire notifications object to ensure no unwanted thresholds remain
            $budgetBody = @{
                properties = @{
                    category   = $budget.properties.category
                    amount     = $budget.properties.amount
                    timeGrain  = $budget.properties.timeGrain
                    timePeriod = $budget.properties.timePeriod
                    notifications = @{
                        actual_GreaterThanOrEqualTo_30_Percent = @{
                            enabled = $true
                            operator = "GreaterThanOrEqualTo"
                            threshold = 30
                            contactEmails = @($userEmail)
                            contactGroups = @($actionGroupId)
                            notificationLanguage = "en-us"
                        }
                        actual_GreaterThanOrEqualTo_50_Percent = @{
                            enabled = $true
                            operator = "GreaterThanOrEqualTo"
                            threshold = 50
                            contactEmails = @($userEmail)
                            contactGroups = @($actionGroupId)
                            notificationLanguage = "en-us"
                        }
                        forecasted_GreaterThanOrEqualTo_75_Percent = @{
                            enabled = $true
                            operator = "GreaterThanOrEqualTo"
                            threshold = 75
                            contactEmails = @($userEmail)
                            contactGroups = @()
                            notificationLanguage = "en-us"
                        }
                        actual_GreaterThanOrEqualTo_80_Percent = @{
                            enabled = $true
                            operator = "GreaterThanOrEqualTo"
                            threshold = 80
                            contactEmails = @($userEmail)
                            contactGroups = @($actionGroupId)
                            notificationLanguage = "en-us"
                        }
                    }
                }
            } | ConvertTo-Json -Depth 10

            $tempFile = "$env:TEMP\budget-link-body.json"
            $budgetBody | Out-File -Encoding utf8 -FilePath $tempFile

            az rest --method put --url $budgetUrl --headers "Content-Type=application/json" --body "@$tempFile"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Output " Budget alerts successfully linked to action group!"
                Write-Output ""
                Write-Output "Alert configuration:"
                Write-Output "- 30% threshold → Email + Action Group (early warning)"
                Write-Output "- 50% threshold → Email + Action Group (investigate)" 
                Write-Output "- 75% threshold → Email Only (forecasted cost warning)"
                Write-Output "- 80% threshold → Email + Action Group (triggers automation)"
            } else {
                throw "Budget update failed"
            }
            
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            
        } catch {
            Write-Output "[ERROR] Automated linking failed: $_"
            Write-Output ""
            Write-Output "Fallback - Manual Azure Portal Steps:"
            Write-Output "1. Navigate to: Cost Management + Billing → Budgets"
            Write-Output "2. Select budget: $targetBudgetName"
            Write-Output "3. Click 'Manage alerts'"
            Write-Output "4. For thresholds 30%, 50%, 80%, add Action Group: $($envConfig.ActionGroupName)"
            Write-Output "5. For threshold 75% (forecasted), configure Email Only notification"
            Write-Output "6. Save the budget configuration"
        }
        Write-Output ""
    }

    Write-Output "=== CONFIGURATION SUMMARY ==="
    Write-Output "Budget: $targetBudgetName"
    Write-Output "Action Group: $($envConfig.ActionGroupName)"
    Write-Output "Automation: $($envConfig.AutomationAccountName)"
    Write-Output "Target WebApp: $($envConfig.WebAppName)"
    Write-Output "Thresholds: Warning $($envConfig.Thresholds.Warning)%, Critical $($envConfig.Thresholds.Critical)%, Emergency $($envConfig.Thresholds.Emergency)%"
    Write-Output ""
    Write-Output "Next steps:"
    Write-Output "1. Complete manual Azure Portal configuration (above)"
    Write-Output "2. Test the system: .\\azure-verify-cost-control.ps1 -Environment $Environment"
    Write-Output "3. Monitor costs: .\monitor-costs.ps1 -Environment $Environment"

} catch {
    Write-Output ""
    Write-Output "[ERROR] Configuration failed: $_"
    Write-Output ""
    Write-Output "Troubleshooting:"
    Write-Output "1. Verify Azure CLI authentication: az account show"
    Write-Output "2. Check budget exists: az consumption budget show --budget-name '$targetBudgetName'"
    Write-Output "3. Verify action group: az monitor action-group show --name '$($envConfig.ActionGroupName)' --resource-group '$($envConfig.ResourceGroup)'"
    Write-Output "4. Run infrastructure deployment: .\azure-deploy-cost-control.ps1 -Environment $Environment"
    
    exit 1
}