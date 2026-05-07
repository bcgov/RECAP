# RECAP WebApp Cost Control Runbook triggered by the cost-control-webhook attached to d837ad-{env}-action-group.
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
Write-Output "=== RECAP Cost Control Shutdown Started at $timestamp ==="
Write-Output "WebApp: $WebAppName"
Write-Output "ResourceGroup: $ResourceGroupName"

try {
    $webapp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
    $currentState = $webapp.State
    Write-Output "Current WebApp State: $currentState"

    if ($currentState -eq "Running") {
        Write-Output "Stopping WebApp..."
        Stop-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
        Start-Sleep -Seconds 10

        $webapp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
        $newState = $webapp.State

        if ($newState -eq "Stopped") {
            Write-Output "SUCCESS: WebApp stopped. New state: $newState"
        } else {
            Write-Error "FAILED: WebApp did not stop properly. State: $newState"
        }
    } else {
        Write-Output "INFO: WebApp was already stopped. Current state: $currentState"
    }
} catch {
    Write-Error "ERROR during shutdown process: $_"
    throw
}

Write-Output "=== RECAP Cost Control Shutdown Completed ==="
