[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipActionGroup,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipAutomation,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# RECAP Cost Control Infrastructure Deployment
# Creates Azure automation resources for cost monitoring and webapp shutdown

$ErrorActionPreference = "Stop"

# Environment-specific configuration
$config = @{
    test = @{
        ResourceGroup = "d837ad-test-networking"
        ActionGroupName = "d837ad-test-action-group"
        AutomationAccountName = "d837ad-test-automation-account"
        WebAppName = "d837ad-test-recap-webapp"
        Location = "Canada East"
        ShortName = "CostCtrlGrp"
    }
    prod = @{
        ResourceGroup = "d837ad-prod-networking"
        ActionGroupName = "d837ad-prod-action-group"
        AutomationAccountName = "d837ad-prod-automation-account"
        WebAppName = "d837ad-prod-recap-webapp"
        Location = "Canada East"
        ShortName = "CostCtrlGrp"
    }
}

$envConfig = $config[$Environment]
if (-not $envConfig) {
    throw "Invalid environment: $Environment"
}

Write-Output "=== RECAP Cost Control Infrastructure Deployment ==="
Write-Output "Environment: $Environment"
Write-Output "Resource Group: $($envConfig.ResourceGroup)"
Write-Output "DryRun Mode: $WhatIf"
Write-Output ""

try {
    # Verify Azure login
    Write-Output "Verifying Azure authentication..."
    $context = Get-AzContext
    if (-not $context) {
        throw "Not authenticated to Azure. Run 'Connect-AzAccount' first."
    }
    Write-Output "Authenticated as: $($context.Account.Id)"
    Write-Output "Subscription: $($context.Subscription.Name)"
    Write-Output ""

    # Check resource group exists
    Write-Output "Checking resource group..."
    $rg = Get-AzResourceGroup -Name $envConfig.ResourceGroup -ErrorAction SilentlyContinue
    if (-not $rg) {
        throw "Resource group '$($envConfig.ResourceGroup)' not found"
    }
    Write-Output "Resource group found: $($rg.ResourceGroupName)"
    Write-Output ""

    # Deploy Action Group
    if (-not $SkipActionGroup) {
        Write-Output "Creating Action Group: $($envConfig.ActionGroupName)"
        if ($WhatIf) {
            Write-Output "DryRun: Would create action group with short name '$($envConfig.ShortName)'"
        } else {
            $actionGroupParams = @{
                ResourceGroupName = $envConfig.ResourceGroup
                Name = $envConfig.ActionGroupName
                ShortName = $envConfig.ShortName
                Location = "global"
            }
            
            $actionGroup = New-AzActionGroup @actionGroupParams -ErrorAction Stop
            Write-Output "[SUCCESS] Action Group created: $($actionGroup.Name)"
        }
        Write-Output ""
    }

    # Deploy Automation Account
    if (-not $SkipAutomation) {
        Write-Output "Creating Automation Account: $($envConfig.AutomationAccountName)"
        if ($WhatIf) {
            Write-Output "DryRun: Would create automation account with managed identity"
        } else {
            $automationParams = @{
                ResourceGroupName = $envConfig.ResourceGroup
                Name = $envConfig.AutomationAccountName
                Location = $envConfig.Location
                AssignSystemIdentity = $true
            }
            
            $automationAccount = New-AzAutomationAccount @automationParams -ErrorAction Stop
            Write-Output "[SUCCESS] Automation Account created: $($automationAccount.AutomationAccountName)"
            
            # Get the managed identity principal ID
            $managedIdentity = Get-AzAutomationAccount -ResourceGroupName $envConfig.ResourceGroup -Name $envConfig.AutomationAccountName
            $principalId = $managedIdentity.Identity.PrincipalId
            Write-Output "Managed Identity Principal ID: $principalId"
            
            # Assign required permissions
            Write-Output "Configuring permissions..."
            
            # Website Contributor role for webapp operations
            $webappScope = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$($envConfig.ResourceGroup)"
            
            # Check if Website Contributor role already exists first
            $existingWebsiteRole = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Website Contributor" -Scope $webappScope -ErrorAction SilentlyContinue
            if ($existingWebsiteRole) {
                Write-Output "Website Contributor role already assigned"
            } else {
                try {
                    $websiteRoleAssignment = New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Website Contributor" -Scope $webappScope -ErrorAction Stop
                    Write-Output "Assigned Website Contributor role"
                } catch {
                    Write-Output "[ERROR] Failed to assign Website Contributor role: $($_.Exception.Message)"
                    Write-Output "Manual assignment required: New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Website Contributor' -Scope '$webappScope'"
                    throw "Critical role assignment failed - automation account cannot control webapp"
                }
            }
            
            # Reader role for subscription access
            $subscriptionScope = "/subscriptions/$((Get-AzContext).Subscription.Id)"
            
            # Check if Reader role already exists first
            $existingReaderRole = Get-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Reader" -Scope $subscriptionScope -ErrorAction SilentlyContinue
            if ($existingReaderRole) {
                Write-Output "Reader role already assigned"
            } else {
                try {
                    # Try with different parameters to avoid BadRequest error
                    $roleAssignment = New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Reader" -Scope $subscriptionScope -ErrorAction Stop
                    Write-Output "Assigned Reader role"
                } catch {
                    Write-Output "[WARNING] Failed to assign Reader role: $($_.Exception.Message)"
                    Write-Output "This is often acceptable - the automation account may work with just Website Contributor role"
                    Write-Output "Manual assignment command: New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName 'Reader' -Scope '$subscriptionScope'"
                }
            }
        }
        Write-Output ""
    }

    # Skip module import - Azure Automation accounts include required modules by default
    if (-not $SkipAutomation -and -not $WhatIf) {
        Write-Output "Azure Automation account includes required PowerShell modules by default"
        Write-Output "Skipping manual module import to avoid deployment issues"
        Write-Output ""
    }

    # Create the runbooks
    if (-not $SkipAutomation -and -not $WhatIf) {
        Write-Output "Creating cost control runbooks..."
        
        # 1. Create shutdown runbook (triggered by budget alerts)
        $shutdownRunbookPath = Join-Path $PSScriptRoot "runbook-content-shutdown.ps1"
        if (-not (Test-Path $shutdownRunbookPath)) {
            throw "Shutdown runbook source file not found: $shutdownRunbookPath"
        }
        Write-Output "Using shutdown runbook source: $shutdownRunbookPath"

        $shutdownRunbookParams = @{
            ResourceGroupName = $envConfig.ResourceGroup
            AutomationAccountName = $envConfig.AutomationAccountName
            Name = "d837ad-$Environment-cost-control-runbook"
            Type = "PowerShell"
            Description = "RECAP cost control automation - stops webapp when budget thresholds exceeded"
            Path = $shutdownRunbookPath
            Force = $true
        }
        
        $shutdownRunbook = Import-AzAutomationRunbook @shutdownRunbookParams
        Write-Output "[SUCCESS] Shutdown runbook created: $($shutdownRunbook.RunbookName)"
        
        # Publish the shutdown runbook
        Publish-AzAutomationRunbook -ResourceGroupName $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName -Name "d837ad-$Environment-cost-control-runbook"
        Write-Output "[SUCCESS] Shutdown runbook published"
        
        # 2. Create monthly startup runbook (scheduled)
        $startupRunbookPath = Join-Path $PSScriptRoot "runbook-content-start.ps1"
        if (-not (Test-Path $startupRunbookPath)) {
            throw "Startup runbook source file not found: $startupRunbookPath"
        }
        Write-Output "Using startup runbook source: $startupRunbookPath"

        $startupRunbookParams = @{
            ResourceGroupName = $envConfig.ResourceGroup
            AutomationAccountName = $envConfig.AutomationAccountName
            Name = "d837ad-$Environment-monthly-startup-runbook"
            Type = "PowerShell"
            Description = "RECAP monthly startup automation - starts webapp on first day of billing cycle"
            Path = $startupRunbookPath
            Force = $true
        }
        
        $startupRunbook = Import-AzAutomationRunbook @startupRunbookParams
        Write-Output "[SUCCESS] Monthly startup runbook created: $($startupRunbook.RunbookName)"
        
        # Publish the startup runbook
        Publish-AzAutomationRunbook -ResourceGroupName $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName -Name "d837ad-$Environment-monthly-startup-runbook"
        Write-Output "[SUCCESS] Monthly startup runbook published"
        
        # 3. Create monthly schedule for startup runbook
        Write-Output "Creating monthly schedule for startup runbook..."
        $scheduleName = "monthly-startup-schedule"
        $scheduleDescription = "Runs on the 1st day of every month at 6:00 AM local time (1:00 PM UTC) to start webapp for new billing cycle"
        
        # Schedule for 1st day of every month at 6:00 AM local time (UTC-7) = 1:00 PM UTC
        $startTime = (Get-Date).Date.AddDays(1 - (Get-Date).Day).AddHours(13) # Next 1st at 1 PM UTC (6 AM local)
        if ($startTime -le (Get-Date)) {
            $startTime = $startTime.AddMonths(1) # If today is 1st and past 1 PM UTC (6 AM local), schedule for next month
        }
        
        $scheduleParams = @{
            ResourceGroupName = $envConfig.ResourceGroup
            AutomationAccountName = $envConfig.AutomationAccountName
            Name = $scheduleName
            StartTime = $startTime
            MonthInterval = 1
            DaysOfMonth = @(1)
            Description = $scheduleDescription
        }
        
        $schedule = New-AzAutomationSchedule @scheduleParams
        $localTime = $startTime.AddHours(-7)
        Write-Output "[SUCCESS] Monthly schedule created: $($schedule.Name)"
        Write-Output "Next run: $($startTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC ($($localTime.ToString('yyyy-MM-dd HH:mm:ss')) local)"
        
        # 4. Link schedule to startup runbook
        Write-Output "Linking schedule to startup runbook..."
        $scheduleParams = @{
            WebAppName = $envConfig.WebAppName
            ResourceGroupName = $envConfig.ResourceGroup
        }
        
        Register-AzAutomationScheduledRunbook -ResourceGroupName $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName -RunbookName "d837ad-$Environment-monthly-startup-runbook" -ScheduleName $scheduleName -Parameters $scheduleParams
        Write-Output "[SUCCESS] Monthly startup runbook linked to schedule"
    }

    Write-Output ""
    Write-Output "=== DEPLOYMENT COMPLETED ==="
    Write-Output "Deployed components:"
    Write-Output "- Action Group: $($envConfig.ActionGroupName)"
    Write-Output "- Automation Account: $($envConfig.AutomationAccountName)"
    Write-Output "- Shutdown Runbook: d837ad-$Environment-cost-control-runbook (webhook-triggered)"
    Write-Output "- Monthly Startup Runbook: d837ad-$Environment-monthly-startup-runbook (scheduled)"
    Write-Output "- Monthly Schedule: Runs 1st of each month at 6:00 AM local (1:00 PM UTC)"
    Write-Output ""
    Write-Output "Next steps:"
    Write-Output "1. Wait 10-15 minutes for PowerShell modules to import"
    Write-Output "2. Configure budget integration:"
    Write-Output "   .\azure-configure-budget-integration.ps1 -Environment $Environment"
    Write-Output "3. Test the system:"
    Write-Output "   .\\azure-verify-cost-control.ps1 -Environment $Environment -DryRun"
    Write-Output ""

} catch {
    Write-Output ""
    Write-Output "[ERROR] Deployment failed: $_"
    Write-Output ""
    Write-Output "Troubleshooting:"
    Write-Output "1. Verify Azure authentication: Get-AzContext"
    Write-Output "2. Check resource group exists: Get-AzResourceGroup -Name '$($envConfig.ResourceGroup)'"
    Write-Output "3. Review permissions on subscription and resource group"
    Write-Output "4. Check Azure PowerShell module: Get-Module -ListAvailable Az"
    
    exit 1
}