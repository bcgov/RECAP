[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowLogs,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowHistory,
    
    [Parameter(Mandatory = $false)]
    [int]$RefreshSeconds = 0,
    
    [Parameter(Mandatory = $false)]
    [switch]$Brief
)

# RECAP Cost Monitoring Dashboard
# Real-time cost monitoring and automation status

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

function Get-BudgetStatus {
    param([string]$BudgetName)
    
    try {
        $budget = az consumption budget show --budget-name $BudgetName --query "{amount: amount, timeGrain: timeGrain, currentSpend: currentSpend}" --output json | ConvertFrom-Json
        
        $percentage = [math]::Round(($budget.currentSpend.amount / $budget.amount) * 100, 2)
        $status = if ($percentage -ge 90) { "CRITICAL" } elseif ($percentage -ge 80) { "WARNING" } elseif ($percentage -ge 60) { "WATCH" } else { "OK" }
        
        return @{
            Amount = $budget.amount
            Spent = $budget.currentSpend.amount
            Percentage = $percentage
            Status = $status
            TimeGrain = $budget.timeGrain
        }
    } catch {
        return @{
            Amount = "Unknown"
            Spent = "Unknown"
            Percentage = 0
            Status = "ERROR"
            TimeGrain = "Unknown"
        }
    }
}

function Get-WebAppStatus {
    param([string]$ResourceGroup, [string]$WebAppName, [string]$HealthUrl)
    
    try {
        $webapp = az webapp show --name $WebAppName --resource-group $ResourceGroup --query "{state: state, availabilityState: availabilityState, lastModifiedTime: lastModifiedTime}" --output json | ConvertFrom-Json
        
        $healthStatus = "Unknown"
        if ($webapp.state -eq "Running") {
            try {
                Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec 10 -ErrorAction Stop | Out-Null
                $healthStatus = "Healthy"
            } catch {
                $healthStatus = "Unhealthy"
            }
        } else {
            $healthStatus = "Stopped"
        }
        
        return @{
            State = $webapp.state
            Availability = $webapp.availabilityState
            Health = $healthStatus
            LastModified = $webapp.lastModifiedTime
        }
    } catch {
        return @{
            State = "Unknown"
            Availability = "Unknown"
            Health = "Error"
            LastModified = "Unknown"
        }
    }
}

function Get-AutomationStatus {
    param([string]$ResourceGroup, [string]$AutomationAccountName)
    
    try {
        # Get recent jobs
        $jobs = az automation job list --resource-group $ResourceGroup --automation-account-name $AutomationAccountName --query "[0:3].{creationTime: creationTime, status: status, jobId: jobId}" --output json | ConvertFrom-Json
        
        $lastJob = if ($jobs) { $jobs[0] } else { $null }
        
        return @{
            LastJobStatus = if ($lastJob) { $lastJob.status } else { "No jobs" }
            LastJobTime = if ($lastJob) { $lastJob.creationTime } else { "Never" }
            TotalJobs = if ($jobs) { $jobs.Count } else { 0 }
        }
    } catch {
        return @{
            LastJobStatus = "Error"
            LastJobTime = "Unknown"
            TotalJobs = 0
        }
    }
}


function Show-Dashboard {
    param($BudgetStatus, $WebAppStatus, $AutomationStatus)
    
    if (-not $Brief) {
        Clear-Host
        Write-Output "==============================================="
        Write-Output "      RECAP Cost Control Dashboard"
        Write-Output "      Environment: $($Environment.ToUpper())"
        Write-Output "      $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
        Write-Output "==============================================="
        Write-Output ""
    }
    
    # Budget Status
    Write-Output "BUDGET STATUS"
    Write-Output "Amount: $($BudgetStatus.Amount) CAD ($($BudgetStatus.TimeGrain))"
    Write-Output "Spent: $($BudgetStatus.Spent) CAD"
    Write-Output "Usage: $($BudgetStatus.Percentage)% [$($BudgetStatus.Status)]"
    
    # Color coding based on status
    $statusColor = switch ($BudgetStatus.Status) {
        "OK" { "Green" }
        "WATCH" { "Yellow" }
        "WARNING" { "Yellow" }
        "CRITICAL" { "Red" }
        default { "White" }
    }
    
    Write-Output ""
    
    # WebApp Status
    Write-Output "WEBAPP STATUS"
    Write-Output "State: $($WebAppStatus.State)"
    Write-Output "Health: $($WebAppStatus.Health)"
    Write-Output "Availability: $($WebAppStatus.Availability)"
    Write-Output "Last Modified: $($WebAppStatus.LastModified)"
    Write-Output ""
    
    # Automation Status
    Write-Output "AUTOMATION STATUS"
    Write-Output "Last Job: $($AutomationStatus.LastJobStatus)"
    Write-Output "Job Time: $($AutomationStatus.LastJobTime)"
    Write-Output "Recent Jobs: $($AutomationStatus.TotalJobs)"
    Write-Output ""
    
    
    # Quick Actions
    if (-not $Brief) {
        Write-Output "QUICK ACTIONS"
        Write-Output "Start WebApp: .\webapp-control.ps1 -Environment $Environment -Action Start"
        Write-Output "Stop WebApp: .\webapp-control.ps1 -Environment $Environment -Action Stop"
        Write-Output "Test System: .\\azure-verify-cost-control.ps1 -Environment $Environment -DryRun"
        Write-Output ""
    }
    
    # Refresh info
    if ($RefreshSeconds -gt 0) {
        Write-Output "Refreshing every $RefreshSeconds seconds... (Press Ctrl+C to stop)"
        Write-Output ""
    }
}

function Show-AutomationLogs {
    param([string]$ResourceGroup, [string]$AutomationAccountName)
    
    try {
        Write-Output "=== RECENT AUTOMATION JOBS ==="
        $jobs = az automation job list --resource-group $ResourceGroup --automation-account-name $AutomationAccountName --query "[0:5]" --output json | ConvertFrom-Json
        
        if ($jobs) {
            foreach ($job in $jobs) {
                Write-Output ""
                Write-Output "Job ID: $($job.jobId)"
                Write-Output "Status: $($job.status)"
                Write-Output "Created: $($job.creationTime)"
                Write-Output "Runbook: $($job.runbook.name)"
                
                if ($job.status -eq "Completed" -or $job.status -eq "Failed") {
                    try {
                        Write-Output "Output:"
                        $output = az automation job show-output --resource-group $ResourceGroup --automation-account-name $AutomationAccountName --job-id $job.jobId
                        Write-Output $output
                    } catch {
                        Write-Output "Could not retrieve job output"
                    }
                }
                Write-Output "---"
            }
        } else {
            Write-Output "No automation jobs found"
        }
    } catch {
        Write-Output "Error retrieving automation logs: $_"
    }
}

function Show-CostHistory {
    param([string]$BudgetName)
    
    try {
        Write-Output "=== COST HISTORY ==="
        
        # Get cost data for last 30 days (this would require additional Azure APIs)
        # For now, show current budget trend
        $budget = az consumption budget show --budget-name $BudgetName --query "{amount: amount, currentSpend: currentSpend, timeGrain: timeGrain}" --output json | ConvertFrom-Json
        
        Write-Output "Budget: $($budget.amount) CAD"
        Write-Output "Current Spend: $($budget.currentSpend.amount) CAD"
        Write-Output "Time Period: $($budget.timeGrain)"
        
        $percentage = [math]::Round(($budget.currentSpend.amount / $budget.amount) * 100, 2)
        Write-Output "Usage: $percentage%"
        
        # Simple trend indicator
        if ($percentage -lt 30) {
            Write-Output "Trend: Low usage - on track"
        } elseif ($percentage -lt 60) {
            Write-Output "Trend: Moderate usage - monitor"
        } elseif ($percentage -lt 80) {
            Write-Output "Trend: High usage - watch closely"
        } else {
            Write-Output "Trend: Critical usage - action required"
        }
        
        Write-Output ""
        Write-Output "Note: Detailed cost history requires Azure Cost Management APIs"
        Write-Output "View full history at: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/costanalysis"
        
    } catch {
        Write-Output "Error retrieving cost history: $_"
    }
}

Write-Output "=== RECAP Cost Monitoring ==="
Write-Output "Environment: $Environment"
Write-Output "Starting monitoring..."
Write-Output ""

try {
    # Verify authentication
    $accountInfo = az account show --query "name" --output tsv
    if (-not $accountInfo) {
        throw "Not authenticated to Azure CLI. Run 'az login' first."
    }

    do {
        # Gather all status information
        $budgetStatus = Get-BudgetStatus -BudgetName $envConfig.BudgetName
        $webappStatus = Get-WebAppStatus -ResourceGroup $envConfig.ResourceGroup -WebAppName $envConfig.WebAppName -HealthUrl $envConfig.HealthCheckUrl
        $automationStatus = Get-AutomationStatus -ResourceGroup $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName
        # Show the dashboard
        Show-Dashboard -BudgetStatus $budgetStatus -WebAppStatus $webappStatus -AutomationStatus $automationStatus
        
        # Show logs if requested
        if ($ShowLogs) {
            Show-AutomationLogs -ResourceGroup $envConfig.ResourceGroup -AutomationAccountName $envConfig.AutomationAccountName
            Write-Output ""
        }
        
        # Show history if requested
        if ($ShowHistory) {
            Show-CostHistory -BudgetName $envConfig.BudgetName
            Write-Output ""
        }
        
        # Wait for refresh if specified
        if ($RefreshSeconds -gt 0) {
            Start-Sleep -Seconds $RefreshSeconds
        }
        
    } while ($RefreshSeconds -gt 0)

} catch {
    Write-Output "[ERROR] Monitoring failed: $_"
    Write-Output ""
    Write-Output "Troubleshooting:"
    Write-Output "1. Verify Azure CLI authentication: az account show"
    Write-Output "2. Check budget exists: az consumption budget show --budget-name '$($envConfig.BudgetName)'"
    Write-Output "3. Verify webapp exists: az webapp show --name '$($envConfig.WebAppName)' --resource-group '$($envConfig.ResourceGroup)'"
    Write-Output "4. Test system: .\\azure-verify-cost-control.ps1 -Environment $Environment"
    
    exit 1
}