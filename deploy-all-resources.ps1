# Complete RECAP Deployment Script
# Runs the full deployment sequence after clean-all-resources.ps1
# Usage: .\deploy-complete.ps1 -Environment "prod" or "test"

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod", "dev")]
    [string]$Environment
)

# Generate timestamp for log file
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$rootDir = $PWD.Path
$logFile = Join-Path $rootDir "deploy-$Environment-$timestamp.log"

Write-Output "RECAP Complete Deployment Script"
Write-Output "Environment: $Environment"
Write-Output "Log file: $logFile"
Write-Output ""

# Function to run command with logging and error handling
function Invoke-StepWithLogging {
    param(
        [string]$StepName,
        [int]$StepNumber,
        [scriptblock]$Command,
        [string]$LogFile
    )
    
    Write-Output "=== Step $StepNumber`: $StepName ==="
    $stepStart = Get-Date
    
    try {
        # Execute command and capture output
        $output = & $Command 2>&1
        $output | Tee-Object -FilePath $LogFile -Append
        
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            $stepEnd = Get-Date
            $duration = ($stepEnd - $stepStart).TotalSeconds
            Write-Output "✅ Step $StepNumber completed successfully ($([math]::Round($duration, 1))s)" | Tee-Object -FilePath $LogFile -Append
            return $true
        } else {
            Write-Output "❌ Step $StepNumber failed with exit code: $LASTEXITCODE" | Tee-Object -FilePath $LogFile -Append
            return $false
        }
    }
    catch {
        Write-Output "❌ Step $StepNumber failed with error: $($_.Exception.Message)" | Tee-Object -FilePath $LogFile -Append
        return $false
    }
}

# Start deployment
$deploymentStart = Get-Date
Write-Output "Started at: $deploymentStart" | Tee-Object -FilePath $logFile
Write-Output "" | Tee-Object -FilePath $logFile

# Verify subscription
Write-Output "Verifying Azure subscription..." | Tee-Object -FilePath $logFile
$subscription = az account show --query "name" --output tsv 2>&1 | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Write-Output "❌ Not logged into Azure. Please run 'az login' first." | Tee-Object -FilePath $logFile -Append
    exit 1
}
Write-Output "✅ Subscription: $subscription" | Tee-Object -FilePath $logFile -Append

# Verify Docker Desktop is running
Write-Output "Verifying Docker Desktop is running..." | Tee-Object -FilePath $logFile -Append
$dockerRunning = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Output "❌ Docker Desktop is not running. Please start Docker Desktop and try again." | Tee-Object -FilePath $logFile -Append
    Write-Output "   - Start Docker Desktop application" | Tee-Object -FilePath $logFile -Append
    Write-Output "   - Wait for Docker to fully initialize" | Tee-Object -FilePath $logFile -Append
    Write-Output "   - Run this script again" | Tee-Object -FilePath $logFile -Append
    exit 1
}
Write-Output "✅ Docker Desktop is running" | Tee-Object -FilePath $logFile -Append
Write-Output "" | Tee-Object -FilePath $logFile -Append

$steps = @()
$failedSteps = @()

# Step 1: Deploy networking infrastructure
$success = Invoke-StepWithLogging -StepName "Deploy networking infrastructure" -StepNumber 1 -LogFile $logFile -Command {
    .\recap-subnet-nsg\networking-config.ps1 -Environment $Environment
}
$steps += @{Number=1; Name="Deploy networking infrastructure"; Success=$success}
if (-not $success) { $failedSteps += 1 }

# Step 2: Deploy OpenAI service with both models
if ($success) {
    $success = Invoke-StepWithLogging -StepName "Deploy OpenAI service with both models" -StepNumber 2 -LogFile $logFile -Command {
        .\recap-llm\openai-deploy.ps1 -Environment $Environment
    }
    $steps += @{Number=2; Name="Deploy OpenAI service with both models"; Success=$success}
    if (-not $success) { $failedSteps += 2 }
}

# Step 3: Create private endpoint
if ($success) {
    $success = Invoke-StepWithLogging -StepName "Create private endpoint" -StepNumber 3 -LogFile $logFile -Command {
        .\recap-subnet-nsg\private-endpoint-deploy.ps1 -Environment $Environment
    }
    $steps += @{Number=3; Name="Create private endpoint"; Success=$success}
    if (-not $success) { $failedSteps += 3 }
}

# Step 4: Generate nginx config
if ($success) {
    $success = Invoke-StepWithLogging -StepName "Generate nginx config" -StepNumber 4 -LogFile $logFile -Command {
        .\recap-web-proxy\nginx-generate-config.ps1 -Environment $Environment
    }
    $steps += @{Number=4; Name="Generate nginx config"; Success=$success}
    if (-not $success) { $failedSteps += 4 }
}

# Step 5: Build and push container
if ($success) {
    $success = Invoke-StepWithLogging -StepName "Build and push container" -StepNumber 5 -LogFile $logFile -Command {
        Set-Location recap-web-proxy; .\acr-container-push.ps1 -Environment $Environment; Set-Location ..
    }
    $steps += @{Number=5; Name="Build and push container"; Success=$success}
    if (-not $success) { $failedSteps += 5 }
}

# Step 6: Deploy web app
if ($success) {
    $success = Invoke-StepWithLogging -StepName "Deploy web app" -StepNumber 6 -LogFile $logFile -Command {
        .\recap-web-proxy\webapp-deploy.ps1 -Environment $Environment
    }
    $steps += @{Number=6; Name="Deploy web app"; Success=$success}
    if (-not $success) { $failedSteps += 6 }
}


# Step 7: Test end-to-end deployment
if ($success) {
    Write-Output "=== Step 7: Test end-to-end deployment ===" | Tee-Object -FilePath $logFile -Append
    
    try {
        Write-Output "Getting API key..." | Tee-Object -FilePath $logFile -Append
        $apiKey = az cognitiveservices account keys list --name "d837ad-$Environment-econ-llm-east" --resource-group "d837ad-$Environment-networking" --query key1 --output tsv 2>&1
        
        if ($LASTEXITCODE -eq 0 -and $apiKey) {
            Write-Output "Running end-to-end tests..." | Tee-Object -FilePath $logFile -Append
            $testOutput = .\recap-web-proxy\proxy-llm-basic-test.ps1 -ApiKey $apiKey -Environment $Environment -Model "both" 2>&1 | Tee-Object -FilePath $logFile -Append
            
            if ($LASTEXITCODE -eq 0) {
                Write-Output "✅ Step 7 completed successfully" | Tee-Object -FilePath $logFile -Append
                $steps += @{Number=7; Name="Test end-to-end deployment"; Success=$true}
            } else {
                Write-Output "❌ Step 7 failed: Tests did not pass" | Tee-Object -FilePath $logFile -Append
                $steps += @{Number=7; Name="Test end-to-end deployment"; Success=$false}
                $failedSteps += 7
                $success = $false
            }
        } else {
            Write-Output "❌ Step 7 failed: Could not retrieve API key" | Tee-Object -FilePath $logFile -Append
            $steps += @{Number=7; Name="Test end-to-end deployment"; Success=$false}
            $failedSteps += 7
            $success = $false
        }
    }
    catch {
        Write-Output "❌ Step 7 failed with error: $($_.Exception.Message)" | Tee-Object -FilePath $logFile -Append
        $steps += @{Number=7; Name="Test end-to-end deployment"; Success=$false}
        $failedSteps += 7
        $success = $false
    }
}

# Final summary
$deploymentEnd = Get-Date
$totalDuration = ($deploymentEnd - $deploymentStart).TotalMinutes

Write-Output "" | Tee-Object -FilePath $logFile -Append
Write-Output "=== DEPLOYMENT SUMMARY ===" | Tee-Object -FilePath $logFile -Append
Write-Output "Environment: $Environment" | Tee-Object -FilePath $logFile -Append
Write-Output "Total Duration: $([math]::Round($totalDuration, 1)) minutes" | Tee-Object -FilePath $logFile -Append
Write-Output "Log File: $logFile" | Tee-Object -FilePath $logFile -Append
Write-Output "" | Tee-Object -FilePath $logFile -Append

foreach ($step in $steps) {
    $status = if ($step.Success) { "✅" } else { "❌" }
    $color = if ($step.Success) { "Green" } else { "Red" }
    Write-Output "$status Step $($step.Number): $($step.Name)" | Tee-Object -FilePath $logFile -Append
}

if ($success) {
    Write-Output "" | Tee-Object -FilePath $logFile -Append
    Write-Output "🎯 Expected Final Result:" | Tee-Object -FilePath $logFile -Append
    Write-Output "- 🎉 All models working correctly!" | Tee-Object -FilePath $logFile -Append
    Write-Output "- ✅ Success rate: 100%" | Tee-Object -FilePath $logFile -Append
    Write-Output "" | Tee-Object -FilePath $logFile -Append    
    exit 0
} else {
    Write-Output "" | Tee-Object -FilePath $logFile -Append
    Write-Output "❌ DEPLOYMENT FAILED" | Tee-Object -FilePath $logFile -Append
    Write-Output "Failed steps: $($failedSteps -join ', ')" | Tee-Object -FilePath $logFile -Append
    Write-Output "Check the log file for detailed error information: $logFile" | Tee-Object -FilePath $logFile -Append
    exit 1
}