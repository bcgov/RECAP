[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckInfrastructure,
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckBudgetIntegration,
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckPermissions,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestWebhook,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestShutdown,
    
    [Parameter(Mandatory = $false)]
    [switch]$TestStartUp
)

# RECAP Cost Control System Testing
# Comprehensive testing and validation of cost control automation

$ErrorActionPreference = "Stop"

# Environment-specific configuration
$config = @{
    test = @{
        ResourceGroup = "d837ad-test-networking"
        ActionGroupName = "d837ad-test-action-group"
        AutomationAccountName = "d837ad-test-automation-account"
        WebAppName = "d837ad-test-recap-webapp"
        BudgetName = "budget-for-d837ad-test-cost-control-automation"
        HealthCheckUrl = "https://d837ad-test-recap-webapp.azurewebsites.net/healthz"
    }
    prod = @{
        ResourceGroup = "d837ad-prod-networking"
        ActionGroupName = "d837ad-prod-action-group"
        AutomationAccountName = "d837ad-prod-automation-account"
        WebAppName = "d837ad-prod-recap-webapp"
        BudgetName = "budget-for-d837ad-prod-cost-control-automation"
        HealthCheckUrl = "https://d837ad-prod-recap-webapp.azurewebsites.net/healthz"
    }
}

$envConfig = $config[$Environment]
if (-not $envConfig) {
    throw "Invalid environment: $Environment"
}

function Test-AzureResource {
    param(
        [string]$ResourceType,
        [string]$Name,
        [string]$ResourceGroup,
        [string]$TestCommand
    )
    
    Write-Host "Testing $ResourceType : $Name"
    
    try {
        # Temporarily change error action preference for this test
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        
        # Execute Azure CLI command and capture both output and error
        $result = Invoke-Expression "$TestCommand 2>&1" 
        $exitCode = $LASTEXITCODE
        
        # Restore error action preference
        $ErrorActionPreference = $previousErrorAction
        
        if ($exitCode -eq 0 -and $result -and $result -notlike "*not found*" -and $result -notlike "*ResourceNotFound*") {
            Write-Host "[SUCCESS] $ResourceType found and accessible"
            return $true
        } else {
            Write-Host "[FAILED] $ResourceType not found or inaccessible"
            return $false
        }
    } catch {
        Write-Host "[FAILED] $ResourceType not found or inaccessible: $_"
        return $false
    }
}

function Test-BudgetConfiguration {
    param(
        [string]$BudgetName,
        [string]$ActionGroupName,
        [string]$ResourceGroup
    )
    
    try {
        Write-Output "Testing budget configuration: $BudgetName"
        
        # First check if budget exists
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        
        $budgetCheck = az consumption budget show --budget-name $BudgetName --query "name" --output tsv 2>$null
        $budgetExitCode = $LASTEXITCODE
        
        $ErrorActionPreference = $previousErrorAction
        
        if ($budgetExitCode -ne 0 -or -not $budgetCheck) {
            Write-Output "[FAILED] Budget does not exist: $BudgetName"
            Write-Output "Run: .\azure-configure-budget-integration.ps1 -Environment $((Split-Path $ResourceGroup -Leaf) -replace 'd837ad-(.+)-networking','$1')"
            return $false
        }
        
        # Get budget info
        $budgetInfo = az consumption budget show --budget-name $BudgetName --query "{amount: amount, currentSpend: currentSpend, notifications: notifications}" --output json | ConvertFrom-Json
        
        Write-Output "Budget Amount: $($budgetInfo.amount) CAD"
        Write-Output "Current Spend: $($budgetInfo.currentSpend.amount) CAD"
        $percentage = [math]::Round(($budgetInfo.currentSpend.amount / $budgetInfo.amount) * 100, 2)
        Write-Output "Usage Percentage: $percentage%"
        
        # First verify the action group actually exists
        $actionGroupExists = $false
        try {
            $previousErrorAction = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            
            $actionGroupTest = az monitor action-group show --name $ActionGroupName --resource-group $ResourceGroup --query "name" --output tsv 2>$null
            $exitCode = $LASTEXITCODE
            
            $ErrorActionPreference = $previousErrorAction
            
            if ($exitCode -eq 0 -and $actionGroupTest -and $actionGroupTest -eq $ActionGroupName) {
                $actionGroupExists = $true
                Write-Output "Action Group exists: $ActionGroupName"
            } else {
                Write-Output "[FAILED] Action Group does not exist: $ActionGroupName"
            }
        } catch {
            Write-Output "[FAILED] Could not verify Action Group existence: $_"
        }
        
        # Check action group integration
        $actionGroupId = "/subscriptions/$((az account show --query id --output tsv))/resourcegroups/$ResourceGroup/providers/microsoft.insights/actiongroups/$ActionGroupName"
        $isLinked = $false
        
        if ($budgetInfo.notifications) {
            $notifications = $budgetInfo.notifications | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
            foreach ($notification in $notifications) {
                $alert = $budgetInfo.notifications.$notification
                if ($alert.contactGroups -contains $actionGroupId) {
                    if ($actionGroupExists) {
                        $isLinked = $true
                        Write-Output "[SUCCESS] Action group linked to alert: $notification (Threshold: $($alert.threshold)%)"
                    } else {
                        Write-Output "[FAILED] Budget references non-existent action group in alert: $notification"
                    }
                }
            }
        }
        
        if (-not $isLinked) {
            if (-not $actionGroupExists) {
                Write-Output "[FAILED] Action group does not exist and cannot be linked to budget alerts"
                Write-Output "Run: .\azure-deploy-cost-control.ps1 -Environment $((Split-Path $ResourceGroup -Leaf) -replace 'd837ad-(.+)-networking','$1')"
            } else {
                Write-Output "[WARNING] Action group exists but is not linked to any budget alerts"
                Write-Output "Run: .\azure-configure-budget-integration.ps1 -Environment $((Split-Path $ResourceGroup -Leaf) -replace 'd837ad-(.+)-networking','$1')"
            }
        }
        
        # Return true only if action group exists AND is properly linked
        return ($actionGroupExists -and $isLinked)
        
    } catch {
        Write-Output "[FAILED] Budget configuration test failed: $_"
        return $false
    }
}

function Test-RunbookExecution {
    param(
        [string]$ResourceGroup,
        [string]$AutomationAccountName,
        [string]$WebAppName,
        [string]$Environment,
        [bool]$DryRunMode
    )
    
    try {
        Write-Output "Testing runbook execution..."
        
        if ($DryRunMode) {
            Write-Output "[DRY RUN] Would start runbook job with parameters:"
            Write-Output "  WebAppName: $WebAppName"
            Write-Output "  ResourceGroupName: $ResourceGroup"
            Write-Output "[DRY RUN] Runbook would NOT actually stop the webapp"
            return $true
        } else {
            # Start runbook job
            $runbookName = "d837ad-$Environment-cost-control-runbook"
            $jobId = az automation runbook start --resource-group $ResourceGroup --automation-account-name $AutomationAccountName --runbook-name $runbookName --parameters "WebAppName=$WebAppName" "ResourceGroupName=$ResourceGroup" --query "name" --output tsv
            
            if ($jobId) {
                Write-Output "Runbook job started: $jobId"
                Write-Output "Waiting for job completion..."
                
                # Wait for job to complete (max 5 minutes)
                $maxWait = 300
                $elapsed = 0
                $status = "Running"
                
                while ($status -eq "Running" -and $elapsed -lt $maxWait) {
                    Start-Sleep -Seconds 15
                    $elapsed += 15
                    $jobInfo = az automation job show --resource-group $ResourceGroup --automation-account-name $AutomationAccountName --job-name $jobId --query "{status: status}" --output json | ConvertFrom-Json
                    $status = $jobInfo.status
                    Write-Output "Job status: $status (elapsed: $elapsed seconds)"
                }
                
                if ($status -eq "Completed") {
                    Write-Output "[SUCCESS] Runbook completed successfully"
                    
                    # Get job output
                    Write-Output "Runbook output:"
                    $output = az automation job show-output --resource-group $ResourceGroup --automation-account-name $AutomationAccountName --job-name $jobId
                    Write-Output $output
                    
                    return $true
                } else {
                    Write-Output "[FAILED] Runbook did not complete successfully. Final status: $status"
                    return $false
                }
            } else {
                Write-Output "[FAILED] Could not start runbook job"
                return $false
            }
        }
        
    } catch {
        Write-Output "[FAILED] Runbook execution test failed: $_"
        return $false
    }
}

Write-Output "=== RECAP Cost Control System Testing ==="
Write-Output "Environment: $Environment"
Write-Output "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'LIVE TEST' })"
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
Write-Output ""

$testResults = @{}

try {
    # Verify Azure authentication
    Write-Output "=== AUTHENTICATION CHECK ==="
    $accountInfo = az account show --query "{name: name, id: id}" --output json | ConvertFrom-Json
    if (-not $accountInfo) {
        throw "Not authenticated to Azure CLI. Run 'az login' first."
    }
    Write-Output "Authenticated to: $($accountInfo.name)"
    Write-Output "Subscription ID: $($accountInfo.id)"
    Write-Output ""

    # Test infrastructure components
    if ($CheckInfrastructure -or (-not $CheckBudgetIntegration -and -not $CheckPermissions -and -not $TestWebhook -and -not $TestShutdown)) {
        Write-Output "=== INFRASTRUCTURE TESTING ==="
        
        # Test Action Group
        $actionGroupTest = Test-AzureResource -ResourceType "Action Group" -Name $envConfig.ActionGroupName -ResourceGroup $envConfig.ResourceGroup -TestCommand "az monitor action-group show --name '$($envConfig.ActionGroupName)' --resource-group '$($envConfig.ResourceGroup)' --query 'name' --output tsv"
        $testResults["ActionGroup"] = $actionGroupTest
        
        # Test Automation Account
        $automationTest = Test-AzureResource -ResourceType "Automation Account" -Name $envConfig.AutomationAccountName -ResourceGroup $envConfig.ResourceGroup -TestCommand "az automation account show --name '$($envConfig.AutomationAccountName)' --resource-group '$($envConfig.ResourceGroup)' --query 'name' --output tsv"
        $testResults["AutomationAccount"] = $automationTest
        
        # Test Runbook
        if ($automationTest) {
            try {
                $previousErrorAction = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                
                $runbooks = az automation runbook list --resource-group $envConfig.ResourceGroup --automation-account-name $envConfig.AutomationAccountName --query "[].name" --output tsv 2>$null
                $exitCode = $LASTEXITCODE
                
                $ErrorActionPreference = $previousErrorAction
                
                if ($exitCode -eq 0 -and $runbooks) {
                    $expectedRunbookName = "d837ad-$Environment-cost-control-runbook"
                    if ($runbooks -contains $expectedRunbookName) {
                        Write-Output "[SUCCESS] Runbook found: $expectedRunbookName"
                        $testResults["Runbook"] = $true
                    } else {
                        Write-Output "[FAILED] Runbook not found: $expectedRunbookName"
                        $testResults["Runbook"] = $false
                    }
                } else {
                    Write-Output "[FAILED] Could not list runbooks - automation account may not exist"
                    $testResults["Runbook"] = $false
                }
            } catch {
                Write-Output "[FAILED] Could not list runbooks: $_"
                $testResults["Runbook"] = $false
            }
        } else {
            Write-Output "[FAILED] Runbook check skipped - automation account not accessible"
            $testResults["Runbook"] = $false
        }
        
        # Test WebApp
        $webappTest = Test-AzureResource -ResourceType "WebApp" -Name $envConfig.WebAppName -ResourceGroup $envConfig.ResourceGroup -TestCommand "az webapp show --name '$($envConfig.WebAppName)' --resource-group '$($envConfig.ResourceGroup)' --query 'name' --output tsv"
        $testResults["WebApp"] = $webappTest
        
        Write-Output ""
    }

    # Test budget integration
    if ($CheckBudgetIntegration -or (-not $CheckInfrastructure -and -not $CheckPermissions -and -not $TestWebhook -and -not $TestShutdown)) {
        Write-Output "=== BUDGET INTEGRATION TESTING ==="
        Write-Output "Testing budget: $($envConfig.BudgetName)"
        Write-Output "Expected action group: $($envConfig.ActionGroupName)"
        $budgetTest = Test-BudgetConfiguration -BudgetName $envConfig.BudgetName -ActionGroupName $envConfig.ActionGroupName -ResourceGroup $envConfig.ResourceGroup
        # Extract only the boolean result (last line of function output)
        $budgetResult = if ($budgetTest -is [array]) { $budgetTest[-1] } else { $budgetTest }
        Write-Output "Budget test result: $budgetResult"
        $testResults["BudgetIntegration"] = $budgetResult
        Write-Output ""
    }

    # Test permissions
    if ($CheckPermissions -or (-not $CheckInfrastructure -and -not $CheckBudgetIntegration -and -not $TestWebhook -and -not $TestShutdown)) {
        Write-Output "=== PERMISSIONS TESTING ==="
        
        try {
            $principalId = az automation account show --name $envConfig.AutomationAccountName --resource-group $envConfig.ResourceGroup --query "identity.principalId" --output tsv
            
            if ($principalId) {
                Write-Output "Automation Account Managed Identity: $principalId"
                
                # Check role assignments (use --all to surface assignments at every scope; without it, role replication can hide RG-scoped assignments)
                $roleAssignments = az role assignment list --assignee $principalId --all --query "[].{principalName: principalName, roleDefinitionName: roleDefinitionName, scope: scope}" --output json | ConvertFrom-Json
                
                $hasWebsiteContributor = $false
                $hasReader = $false
                
                foreach ($role in $roleAssignments) {
                    Write-Output "Role: $($role.roleDefinitionName) | Scope: $($role.scope)"
                    if ($role.roleDefinitionName -eq "Website Contributor") { $hasWebsiteContributor = $true }
                    if ($role.roleDefinitionName -eq "Reader") { $hasReader = $true }
                }
                
                if ($hasWebsiteContributor -and $hasReader) {
                    Write-Output "[SUCCESS] Required permissions found"
                    $testResults["Permissions"] = $true
                } else {
                    Write-Output "[FAILED] Missing required permissions"
                    if (-not $hasWebsiteContributor) { Write-Output "  Missing: Website Contributor" }
                    if (-not $hasReader) { Write-Output "  Missing: Reader" }
                    $testResults["Permissions"] = $false
                }
            } else {
                Write-Output "[FAILED] Automation Account does not have managed identity"
                $testResults["Permissions"] = $false
            }
        } catch {
            Write-Output "[FAILED] Could not check permissions: $_"
            $testResults["Permissions"] = $false
        }
        Write-Output ""
    }

    # Test webhook (included in infrastructure check if no specific tests specified)
    if ($TestWebhook -or ($CheckInfrastructure -or (-not $CheckBudgetIntegration -and -not $CheckPermissions -and -not $TestShutdown))) {
        Write-Output "=== WEBHOOK TESTING ==="
        
        try {
            # NOTE: 'az automation webhook' does not exist in the current az automation extension.
            # Use Az PowerShell (Az.Automation) for webhook discovery.
            Import-Module Az.Automation -Force -ErrorAction SilentlyContinue
            
            $expectedRunbookName = "d837ad-$Environment-cost-control-runbook"
            $webhooks = Get-AzAutomationWebhook `
                -ResourceGroupName $envConfig.ResourceGroup `
                -AutomationAccountName $envConfig.AutomationAccountName `
                -ErrorAction Stop
            $webhook = $webhooks | Where-Object { $_.Name -like "*cost-control*" -or $_.RunbookName -eq $expectedRunbookName }
            
            if ($webhook) {
                Write-Output "[SUCCESS] Webhook found: $($webhook.Name)"
                Write-Output "Runbook: $($webhook.RunbookName)"
                Write-Output "IsEnabled: $($webhook.IsEnabled)"
                Write-Output "ExpiryTime: $($webhook.ExpiryTime)"
                
                # Check if webhook is expired or expiring soon
                $daysUntilExpiry = ($webhook.ExpiryTime - (Get-Date)).Days
                if ($daysUntilExpiry -le 0) {
                    Write-Output "[WARNING] Webhook has EXPIRED! Budget alerts will not trigger automation."
                    Write-Output "Run: .\azure-configure-budget-integration.ps1 -Environment $Environment"
                } elseif ($daysUntilExpiry -le 30) {
                    Write-Output "[WARNING] Webhook expires in $daysUntilExpiry days"
                }
                
                $testResults["Webhook"] = $true
            } else {
                Write-Output "[FAILED] No webhook found for cost control runbook"
                Write-Output "[ERROR] Webhook missing. Budget alerts will NOT trigger automation."
                Write-Output "Run: .\azure-configure-budget-integration.ps1 -Environment $Environment"
                $testResults["Webhook"] = $false
            }
        } catch {
            Write-Output "[FAILED] Could not check webhooks: $_"
            Write-Output "If this is a NullReferenceException, run Connect-AzAccount first (Az PowerShell auth is separate from az login)."
            Write-Output "[ERROR] Unable to verify webhook status. Budget alerts may not work."
            Write-Output "Run: .\azure-configure-budget-integration.ps1 -Environment $Environment"
            $testResults["Webhook"] = $false
        }
        Write-Output ""
    }

    # Test shutdown capability
    if ($TestShutdown) {
        Write-Output "=== SHUTDOWN TESTING ==="
        
        # Check infrastructure dependencies
        if ($testResults["AutomationAccount"] -eq $false -or $testResults["Runbook"] -eq $false) {
            # Auto-run infrastructure check if not already done
            if (-not $testResults.ContainsKey("AutomationAccount")) {
                Write-Output "Checking required infrastructure for runbook testing..."
                
                # Test Automation Account
                $automationTest = Test-AzureResource -ResourceType "Automation Account" -Name $envConfig.AutomationAccountName -ResourceGroup $envConfig.ResourceGroup -TestCommand "az automation account show --name '$($envConfig.AutomationAccountName)' --resource-group '$($envConfig.ResourceGroup)' --query 'name' --output tsv"
                $testResults["AutomationAccount"] = $automationTest
                
                # Test Runbook
                if ($automationTest) {
                    try {
                        $runbooks = az automation runbook list --resource-group $envConfig.ResourceGroup --automation-account-name $envConfig.AutomationAccountName --query "[].name" --output tsv
                        $expectedRunbookName = "d837ad-$Environment-cost-control-runbook"
                        if ($runbooks -contains $expectedRunbookName) {
                            Write-Output "[SUCCESS] Runbook found: $expectedRunbookName"
                            $testResults["Runbook"] = $true
                        } else {
                            Write-Output "[FAILED] Runbook not found: $expectedRunbookName"
                            $testResults["Runbook"] = $false
                        }
                    } catch {
                        Write-Output "[FAILED] Could not list runbooks: $_"
                        $testResults["Runbook"] = $false
                    }
                } else {
                    $testResults["Runbook"] = $false
                }
            }
        }
        
        if ($testResults["AutomationAccount"] -ne $false -and $testResults["Runbook"] -ne $false) {
            $shutdownTest = Test-RunbookExecution -ResourceGroup $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName -WebAppName $envConfig.WebAppName -Environment $Environment -DryRunMode $DryRun
            $testResults["ShutdownTest"] = $shutdownTest
        } else {
            Write-Output "[SKIPPED] Automation infrastructure not available for testing"
            $testResults["ShutdownTest"] = $false
        }
        Write-Output ""
    }

    # Overall health check
    Write-Output "=== WEBAPP HEALTH CHECK ==="
    try {
        Invoke-RestMethod -Uri $envConfig.HealthCheckUrl -Method Get -TimeoutSec 15 -ErrorAction Stop | Out-Null
        Write-Output "[SUCCESS] WebApp health check passed"
        Write-Output "Health check URL: $($envConfig.HealthCheckUrl)"
        $testResults["HealthCheck"] = $true
    } catch {
        Write-Output "[WARNING] WebApp health check failed: $_"
        $testResults["HealthCheck"] = $false
    }
    Write-Output ""

    # Manual startup runbook test
    if ($TestStartUp) {
        Write-Output "=== STARTUP RUNBOOK TEST ==="
        
        # Check infrastructure dependencies
        if ($testResults["AutomationAccount"] -eq $false -or $testResults["Runbook"] -eq $false) {
            # Auto-run infrastructure check if not already done
            if (-not $testResults.ContainsKey("AutomationAccount")) {
                Write-Output "Checking required infrastructure for runbook testing..."
                
                # Test Automation Account
                $automationTest = Test-AzureResource -ResourceType "Automation Account" -Name $envConfig.AutomationAccountName -ResourceGroup $envConfig.ResourceGroup -TestCommand "az automation account show --name '$($envConfig.AutomationAccountName)' --resource-group '$($envConfig.ResourceGroup)' --query 'name' --output tsv"
                $testResults["AutomationAccount"] = $automationTest
                
                # Test Runbook
                if ($automationTest) {
                    try {
                        $runbooks = az automation runbook list --resource-group $envConfig.ResourceGroup --automation-account-name $envConfig.AutomationAccountName --query "[].name" --output tsv
                        $expectedRunbookName = "d837ad-$Environment-monthly-startup-runbook"
                        if ($runbooks -contains $expectedRunbookName) {
                            Write-Output "[SUCCESS] Startup runbook found: $expectedRunbookName"
                            $testResults["StartupRunbook"] = $true
                        } else {
                            Write-Output "[FAILED] Startup runbook not found: $expectedRunbookName"
                            $testResults["StartupRunbook"] = $false
                        }
                    } catch {
                        Write-Output "[FAILED] Could not list runbooks: $_"
                        $testResults["StartupRunbook"] = $false
                    }
                } else {
                    $testResults["StartupRunbook"] = $false
                }
            }
        }
        
        if ($testResults["AutomationAccount"] -ne $false -and ($testResults["StartupRunbook"] -ne $false -or $testResults["Runbook"] -ne $false)) {
            try {
                Write-Output "Testing monthly startup runbook manually..."
                Write-Output "Runbook: d837ad-$Environment-monthly-startup-runbook"
                Write-Output "Parameters: WebAppName=$($envConfig.WebAppName), ResourceGroupName=$($envConfig.ResourceGroup)"
                
                if (-not $DryRun) {
                    $startupJobResult = Start-AzAutomationRunbook `
                        -ResourceGroupName $envConfig.ResourceGroup `
                        -AutomationAccountName $envConfig.AutomationAccountName `
                        -Name "d837ad-$Environment-monthly-startup-runbook" `
                        -Parameters @{
                            WebAppName = $envConfig.WebAppName
                            ResourceGroupName = $envConfig.ResourceGroup
                        }
                    
                    if ($startupJobResult) {
                        Write-Output "[SUCCESS] Monthly startup runbook job started successfully"
                        Write-Output "Job ID: $($startupJobResult.JobId)"
                        Write-Output "Status: $($startupJobResult.Status)"
                        Write-Output "Creation Time: $($startupJobResult.CreationTime)"
                        $testResults["ManualStartupTest"] = $true
                        
                        Write-Output ""
                        Write-Output "Monitor job completion in Azure Portal or wait 2-3 minutes and check webapp status"
                    } else {
                        Write-Output "[FAILED] Monthly startup runbook job failed to start"
                        $testResults["ManualStartupTest"] = $false
                    }
                } else {
                    Write-Output "[DRY RUN] Would execute: Start-AzAutomationRunbook -Name 'd837ad-$Environment-monthly-startup-runbook'"
                    $testResults["ManualStartupTest"] = $true
                }
                
            } catch {
                Write-Output "[FAILED] Monthly startup runbook test failed: $_"
                Write-Output "Make sure you're connected to Azure PowerShell: Connect-AzAccount"
                $testResults["ManualStartupTest"] = $false
            }
        } else {
            Write-Output "[SKIPPED] Automation infrastructure not available for startup testing"
            $testResults["ManualStartupTest"] = $false
        }
        Write-Output ""
    }

    # Test summary
    Write-Output "=== TEST SUMMARY ==="
    $successCount = 0
    $totalCount = 0
    
    foreach ($test in $testResults.Keys) {
        $result = $testResults[$test]
        $status = if ($result) { "[PASS]" } else { "[FAIL]" }
        Write-Output "$status $test"
        if ($result) { $successCount++ }
        $totalCount++
    }
    
    Write-Output ""
    Write-Output "Overall Result: $successCount/$totalCount tests passed"
    
    if ($successCount -eq $totalCount) {
        Write-Output "[SUCCESS] All tests passed - Cost control system is ready"
        $exitCode = 0
    } elseif ($successCount -ge ($totalCount * 0.7)) {
        Write-Output "[WARNING] Most tests passed - System may work with minor issues"
        $exitCode = 1
    } else {
        Write-Output "[FAILED] Critical tests failed - System requires fixes"
        $exitCode = 2
    }

    if ($exitCode -ne 0) {
        Write-Output ""
        Write-Output "Next steps:"
        if ($testResults["ActionGroup"] -eq $false) {
            Write-Output "1. Run: .\azure-deploy-cost-control.ps1 -Environment $Environment"
        }
        if ($testResults["BudgetIntegration"] -eq $false) {
            Write-Output "2. Run: .\azure-configure-budget-integration.ps1 -Environment $Environment"
        }
        if ($testResults["Webhook"] -eq $false) {
            Write-Output "3. Run: .\azure-configure-budget-integration.ps1 -Environment $Environment"
        }
        if ($testResults["Permissions"] -eq $false) {
            Write-Output "4. Check automation account permissions"
        }
    }
    
    exit $exitCode

} catch {
    Write-Output ""
    Write-Output "[ERROR] Testing failed: $_"
    Write-Output ""
    Write-Output "Troubleshooting:"
    Write-Output "1. Verify Azure CLI authentication: az account show"
    Write-Output "2. Check all resources exist: .\azure-verify-cost-control.ps1 -Environment $Environment -CheckInfrastructure"
    Write-Output "3. Deploy missing components: .\azure-deploy-cost-control.ps1 -Environment $Environment"
    Write-Output "4. Configure integration: .\azure-configure-budget-integration.ps1 -Environment $Environment"
    
    exit 3
}