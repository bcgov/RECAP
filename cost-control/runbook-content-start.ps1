# RECAP WebApp Monthly Startup Runbook - Starts webapp if stopped on first day of month (billing cycle reset)
param(
    [Parameter(Mandatory = $true)]
    [string]$WebAppName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

# --- Connect using the automation account's system-assigned managed identity ---
try {
    Connect-AzAccount -Identity | Out-Null
    Write-Output "SUCCESS: Connected to Azure using Managed Identity"
    
    # Give Azure resources time to initialize
    Start-Sleep -Seconds 10
} catch {
    Write-Error "FAILED to connect to Azure: $_"
    throw
}

$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$currentDate = Get-Date
Write-Output "=== RECAP Monthly Startup Check Started at $timestamp ==="
Write-Output "Current Date: $($currentDate.ToString('yyyy-MM-dd')) (Day $($currentDate.Day))"
Write-Output "WebApp: $WebAppName"
Write-Output "ResourceGroup: $ResourceGroupName"

try {
    $webapp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
    $currentState = $webapp.State
    Write-Output "Current WebApp State: $currentState"

    if ($currentState -eq "Stopped") {
        Write-Output "WebApp is stopped. Starting for new billing cycle..."
        Start-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
        Start-Sleep -Seconds 15

        $webapp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
        $newState = $webapp.State

        if ($newState -eq "Running") {
            Write-Output "SUCCESS: WebApp started for new billing cycle. New state: $newState"
            Write-Output "Monthly reset complete - cost controls are now active"
        } else {
            Write-Error "FAILED: WebApp did not start properly. State: $newState"
        }
    } else {
        Write-Output "INFO: WebApp was already running. Current state: $currentState"
        Write-Output "No action needed - webapp is available"
    }
} catch {
    Write-Error "ERROR during startup process: $_"
    throw
}

Write-Output "=== RECAP Monthly Startup Check Completed ==="