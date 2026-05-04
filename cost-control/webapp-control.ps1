[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop", "Restart", "Status")]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# RECAP WebApp Control Script
# Manual start/stop/restart operations for RECAP webapp

$ErrorActionPreference = "Stop"

# Environment-specific configuration
$config = @{
    test = @{
        ResourceGroup = "d837ad-test-networking"
        WebAppName = "d837ad-test-recap-webapp"
        HealthCheckUrl = "https://d837ad-test-recap-webapp.azurewebsites.net/healthz"
    }
    prod = @{
        ResourceGroup = "d837ad-prod-networking"
        WebAppName = "d837ad-prod-recap-webapp"
        HealthCheckUrl = "https://d837ad-prod-recap-webapp.azurewebsites.net/healthz"
    }
}

$envConfig = $config[$Environment]
if (-not $envConfig) {
    throw "Invalid environment: $Environment"
}

function Test-WebAppHealth {
    param([string]$Url, [int]$TimeoutSeconds = 30)
    
    try {
        Write-Output "Testing webapp health: $Url"
        $response = Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        Write-Output "[SUCCESS] Health check passed"
        return $true
    } catch {
        Write-Output "[WARNING] Health check failed: $_"
        return $false
    }
}


Write-Output "=== RECAP WebApp Control ==="
Write-Output "Environment: $Environment"
Write-Output "WebApp: $($envConfig.WebAppName)"
Write-Output "Action: $Action"
Write-Output "Force: $Force"
Write-Output "DryRun: $WhatIf"
Write-Output ""

try {
    # Verify Azure CLI authentication
    Write-Output "Verifying Azure CLI authentication..."
    $accountInfo = az account show --query "name" --output tsv
    if (-not $accountInfo) {
        throw "Not authenticated to Azure CLI. Run 'az login' first."
    }
    Write-Output "Authenticated to: $accountInfo"
    Write-Output ""

    # Get current webapp state
    Write-Output "Checking current webapp state..."
    $webappInfo = az webapp show --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup --query "{state: state, availabilityState: availabilityState, lastModifiedTime: lastModifiedTime}" --output json | ConvertFrom-Json
    
    $currentState = $webappInfo.state
    $availabilityState = $webappInfo.availabilityState
    $lastModified = $webappInfo.lastModifiedTime
    
    Write-Output "Current State: $currentState"
    Write-Output "Availability: $availabilityState"
    Write-Output "Last Modified: $lastModified"
    Write-Output ""

    # Handle each action
    switch ($Action.ToLower()) {
        "status" {
            Write-Output "=== WEBAPP STATUS ==="
            Write-Output "Name: $($envConfig.WebAppName)"
            Write-Output "Resource Group: $($envConfig.ResourceGroup)"
            Write-Output "State: $currentState"
            Write-Output "Availability: $availabilityState"
            Write-Output "Last Modified: $lastModified"
            Write-Output ""
            
            if ($currentState -eq "Running") {
                $healthOk = Test-WebAppHealth -Url $envConfig.HealthCheckUrl
                Write-Output "Health Status: $(if ($healthOk) { 'Healthy' } else { 'Unhealthy' })"
            }
            
            Write-Output ""
        }
        
        "start" {
            if ($currentState -eq "Running" -and -not $Force) {
                Write-Output "[INFO] WebApp is already running"
                $healthOk = Test-WebAppHealth -Url $envConfig.HealthCheckUrl
                if ($healthOk) {
                    Write-Output "[SUCCESS] WebApp is running and healthy"
                } else {
                    Write-Output "[WARNING] WebApp is running but health check failed"
                    if ($Force) {
                        Write-Output "Force flag set - restarting webapp"
                        $Action = "Restart"
                    }
                }
            } else {
                Write-Output "Starting webapp..."
                if ($WhatIf) {
                    Write-Output "DryRun: Would start webapp $($envConfig.WebAppName)"
                } else {
                    az webapp start --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup
                    Write-Output "[SUCCESS] Start command sent"
                    
                    # Wait for startup
                    Write-Output "Waiting for webapp to start..."
                    Start-Sleep -Seconds 30
                    
                    # Verify startup
                    $newState = az webapp show --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup --query "state" --output tsv
                    Write-Output "New state: $newState"
                    
                    if ($newState -eq "Running") {
                        Write-Output "[SUCCESS] WebApp started successfully"
                        
                        # Test health
                        Start-Sleep -Seconds 15
                        $healthOk = Test-WebAppHealth -Url $envConfig.HealthCheckUrl
                        
                        
                    } else {
                        Write-Output "[ERROR] Failed to start webapp. State: $newState"
                    }
                }
            }
        }
        
        "stop" {
            if ($currentState -eq "Stopped" -and -not $Force) {
                Write-Output "[INFO] WebApp is already stopped"
            } else {
                Write-Output "Stopping webapp..."
                if ($WhatIf) {
                    Write-Output "DryRun: Would stop webapp $($envConfig.WebAppName)"
                } else {
                    az webapp stop --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup
                    Write-Output "[SUCCESS] Stop command sent"
                    
                    # Wait and verify
                    Write-Output "Waiting for webapp to stop..."
                    Start-Sleep -Seconds 15
                    
                    $newState = az webapp show --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup --query "state" --output tsv
                    Write-Output "New state: $newState"
                    
                    if ($newState -eq "Stopped") {
                        Write-Output "[SUCCESS] WebApp stopped successfully"
                        
                        
                    } else {
                        Write-Output "[ERROR] Failed to stop webapp. State: $newState"
                    }
                }
            }
        }
        
        "restart" {
            Write-Output "Restarting webapp..."
            if ($WhatIf) {
                Write-Output "DryRun: Would restart webapp $($envConfig.WebAppName)"
            } else {
                az webapp restart --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup
                Write-Output "[SUCCESS] Restart command sent"
                
                # Wait for restart
                Write-Output "Waiting for webapp to restart..."
                Start-Sleep -Seconds 45
                
                # Verify restart
                $newState = az webapp show --name $envConfig.WebAppName --resource-group $envConfig.ResourceGroup --query "state" --output tsv
                Write-Output "New state: $newState"
                
                if ($newState -eq "Running") {
                    Write-Output "[SUCCESS] WebApp restarted successfully"
                    
                    # Test health
                    Start-Sleep -Seconds 15
                    $healthOk = Test-WebAppHealth -Url $envConfig.HealthCheckUrl
                    
                    
                } else {
                    Write-Output "[ERROR] Restart may have failed. State: $newState"
                }
            }
        }
    }

    Write-Output ""
    Write-Output "=== OPERATION COMPLETED ==="
    Write-Output "Action: $Action"
    Write-Output "Target: $($envConfig.WebAppName)"
    Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"

} catch {
    Write-Output ""
    Write-Output "[ERROR] WebApp control operation failed: $_"
    Write-Output ""
    Write-Output "Troubleshooting:"
    Write-Output "1. Verify Azure CLI authentication: az account show"
    Write-Output "2. Check webapp exists: az webapp show --name '$($envConfig.WebAppName)' --resource-group '$($envConfig.ResourceGroup)'"
    Write-Output "3. Check webapp state: az webapp show --name '$($envConfig.WebAppName)' --resource-group '$($envConfig.ResourceGroup)' --query 'state'"
    Write-Output "4. Verify permissions to manage webapp in resource group"
    
    exit 1
}