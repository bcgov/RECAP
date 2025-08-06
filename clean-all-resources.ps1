# RECAP Resource Cleanup Script
# WARNING: This script will DELETE ALL RECAP resources in the specified environment
# Use this script to completely clean up before redeployment or for testing

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

Write-Host "=== RECAP COMPLETE RESOURCE CLEANUP ===" -ForegroundColor Red
Write-Host "Environment: $Environment" -ForegroundColor Yellow

# Verify we're connected to the correct Azure subscription
Write-Host "Verifying Azure subscription..." -ForegroundColor Cyan
try {
    $currentSubscriptionName = az account show --query "name" --output tsv 2>$null
    $expectedSubscriptionName = "d837ad-$Environment - RECAP LLM Responsible Evaluation And Consolidated"
    
    if ($currentSubscriptionName -notlike "*d837ad-$Environment*") {
        Write-Host "❌ ERROR: Connected to wrong Azure subscription!" -ForegroundColor Red
        Write-Host "Current subscription: $currentSubscriptionName" -ForegroundColor Yellow
        Write-Host "Expected subscription: $expectedSubscriptionName" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor White
        Write-Host "Running az login to switch subscriptions..." -ForegroundColor Cyan
        
        az login
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Azure login failed. Exiting script." -ForegroundColor Red
            exit 1
        }
        
        # Re-check subscription after login
        $currentSubscriptionName = az account show --query "name" --output tsv 2>$null
        if ($currentSubscriptionName -notlike "*d837ad-$Environment*") {
            Write-Host "❌ Still not connected to correct subscription after login." -ForegroundColor Red
            Write-Host "Please run: az account set --subscription `"d837ad-$Environment`"" -ForegroundColor Cyan
            exit 1
        }
        Write-Host "✅ Now connected to correct subscription: $currentSubscriptionName" -ForegroundColor Green
    } else {
        Write-Host "✅ Connected to correct subscription: $currentSubscriptionName" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Not logged in to Azure. Please run: az login" -ForegroundColor Red
    exit 1
}

Write-Host "" -ForegroundColor White

# Resource names based on environment
$resourceGroup = "d837ad-$Environment-networking"
$openAIName = "d837ad-$Environment-econ-llm-east"
$privateEndpointName = "d837ad-$Environment-econ-llm-east-pe"
$webAppName = "d837ad-$Environment-recap-webapp"
$appServicePlan = "d837ad-$Environment-recap-asp"
$acrName = "d837ad$($Environment)containers"
$vnetName = "d837ad-$Environment-vwan-spoke"
$privateEndpointSubnetName = "d837ad-$Environment-private-endpoint-subnet"
$webAppSubnetName = "d837ad-$Environment-webapp-integration-subnet"
$privateEndpointNsgName = "d837ad-$Environment-pe-nsg"
$webAppNsgName = "d837ad-$Environment-webapp-nsg"

Write-Host "⚠️  WARNING: This will DELETE the following resources:" -ForegroundColor Red
Write-Host "" -ForegroundColor White
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host "  ├── Azure OpenAI Service: $openAIName" -ForegroundColor White
Write-Host "  ├── Private Endpoint: $privateEndpointName" -ForegroundColor White
Write-Host "  ├── Web App: $webAppName" -ForegroundColor White
Write-Host "  ├── App Service Plan: $appServicePlan" -ForegroundColor White
Write-Host "  ├── Container Registry: $acrName" -ForegroundColor White
Write-Host "  ├── VNet Subnets: $privateEndpointSubnetName, $webAppSubnetName" -ForegroundColor White
Write-Host "  └── Network Security Groups: $privateEndpointNsgName, $webAppNsgName" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "Plus any soft-deleted Cognitive Services that will be PURGED permanently!" -ForegroundColor Red
Write-Host "" -ForegroundColor White

# Safety confirmation unless -Force is used
if (-not $Force) {
    $confirmation = Read-Host "Are you absolutely sure you want to DELETE ALL these resources? Type 'DELETE-ALL' to proceed"
    if ($confirmation -ne "DELETE-ALL") {
        Write-Host "❌ Cleanup cancelled. No resources were deleted." -ForegroundColor Green
        exit 0
    }
    
    Write-Host "" -ForegroundColor White
    $finalConfirmation = Read-Host "Last chance! This action CANNOT be undone. Type 'CONFIRMED' to proceed"
    if ($finalConfirmation -ne "CONFIRMED") {
        Write-Host "❌ Cleanup cancelled. No resources were deleted." -ForegroundColor Green
        exit 0
    }
}

Write-Host "" -ForegroundColor White
Write-Host "🗑️  Starting resource cleanup..." -ForegroundColor Red

# Check Azure CLI authentication
Write-Host "Step 1: Checking Azure CLI authentication..." -ForegroundColor Cyan
try {
    $azAccount = az account show --output json | ConvertFrom-Json
    Write-Host "✅ Authenticated as: $($azAccount.user.name)" -ForegroundColor Green
    Write-Host "✅ Subscription: $($azAccount.name)" -ForegroundColor Green
} catch {
    Write-Host "❌ Not logged in to Azure. Please log in first with 'az login'" -ForegroundColor Red
    exit 1
}

# Step 2: Delete Web App and App Service Plan
Write-Host "`nStep 2: Deleting Web App and App Service Plan..." -ForegroundColor Cyan
Write-Host "Deleting Web App: $webAppName" -ForegroundColor Yellow
az webapp delete --name $webAppName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Web App deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Web App not found or already deleted" -ForegroundColor Yellow
}

Write-Host "Deleting App Service Plan: $appServicePlan" -ForegroundColor Yellow
az appservice plan delete --name $appServicePlan --resource-group $resourceGroup --yes 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ App Service Plan deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ App Service Plan not found or already deleted" -ForegroundColor Yellow
}

# Step 3: Delete Container Registry
Write-Host "`nStep 3: Deleting Azure Container Registry..." -ForegroundColor Cyan
Write-Host "Deleting ACR: $acrName" -ForegroundColor Yellow
az acr delete --name $acrName --resource-group $resourceGroup --yes 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Container Registry deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Container Registry not found or already deleted" -ForegroundColor Yellow
}

# Step 4: Delete Private Endpoint
Write-Host "`nStep 4: Deleting Private Endpoint..." -ForegroundColor Cyan
Write-Host "Deleting Private Endpoint: $privateEndpointName" -ForegroundColor Yellow
az network private-endpoint delete --name $privateEndpointName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Private Endpoint deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Private Endpoint not found or already deleted" -ForegroundColor Yellow
}

# Step 5: Delete OpenAI Service
Write-Host "`nStep 5: Deleting Azure OpenAI Service..." -ForegroundColor Cyan
Write-Host "Deleting OpenAI Service: $openAIName" -ForegroundColor Yellow
az cognitiveservices account delete --name $openAIName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ OpenAI Service deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ OpenAI Service not found or already deleted" -ForegroundColor Yellow
}

# Step 6: Purge Soft-Deleted OpenAI Services
Write-Host "`nStep 6: Purging soft-deleted Cognitive Services..." -ForegroundColor Cyan
Write-Host "Checking for soft-deleted services..." -ForegroundColor Yellow
$softDeleted = az cognitiveservices account list-deleted --query "[?contains(name, 'd837ad') && contains(name, 'econ-llm-east')]" --output json | ConvertFrom-Json

if ($softDeleted -and $softDeleted.Count -gt 0) {
    foreach ($service in $softDeleted) {
        Write-Host "Purging soft-deleted service: $($service.name)" -ForegroundColor Yellow
        az cognitiveservices account purge --name $service.name --resource-group $resourceGroup --location $service.location 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Purged: $($service.name)" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Failed to purge: $($service.name)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "✅ No soft-deleted services found" -ForegroundColor Green
}

# Step 7: Delete VNet Subnets
Write-Host "`nStep 7: Deleting VNet Subnets..." -ForegroundColor Cyan
Write-Host "Deleting subnet: $privateEndpointSubnetName" -ForegroundColor Yellow
az network vnet subnet delete --name $privateEndpointSubnetName --vnet-name $vnetName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Private endpoint subnet deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Private endpoint subnet not found or already deleted" -ForegroundColor Yellow
}

Write-Host "Deleting subnet: $webAppSubnetName" -ForegroundColor Yellow
az network vnet subnet delete --name $webAppSubnetName --vnet-name $vnetName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Web app subnet deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Web app subnet not found or already deleted" -ForegroundColor Yellow
}

# Step 8: Delete Network Security Groups
Write-Host "`nStep 8: Deleting Network Security Groups..." -ForegroundColor Cyan
Write-Host "Deleting NSG: $privateEndpointNsgName" -ForegroundColor Yellow
az network nsg delete --name $privateEndpointNsgName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Private endpoint NSG deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Private endpoint NSG not found or already deleted" -ForegroundColor Yellow
}

Write-Host "Deleting NSG: $webAppNsgName" -ForegroundColor Yellow
az network nsg delete --name $webAppNsgName --resource-group $resourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Web app NSG deleted" -ForegroundColor Green
} else {
    Write-Host "⚠️ Web app NSG not found or already deleted" -ForegroundColor Yellow
}

# Step 9: Verification
Write-Host "`nStep 9: Verifying cleanup..." -ForegroundColor Cyan
Write-Host "Checking remaining resources in $resourceGroup..." -ForegroundColor Yellow

$remainingResources = az resource list --resource-group $resourceGroup --query "[].{Name:name, Type:type}" --output json | ConvertFrom-Json

if ($remainingResources -and $remainingResources.Count -gt 0) {
    Write-Host "⚠️ Remaining resources found:" -ForegroundColor Yellow
    foreach ($resource in $remainingResources) {
        Write-Host "  - $($resource.Name) ($($resource.Type))" -ForegroundColor White
    }
} else {
    Write-Host "✅ No RECAP-specific resources remaining in resource group" -ForegroundColor Green
}

# Step 10: Clean local generated files and Docker images
Write-Host "`nStep 10: Cleaning local generated files and Docker images..." -ForegroundColor Cyan

# Clean local files
$localFiles = @(
    "recap-web-proxy\nginx.conf"
)

foreach ($file in $localFiles) {
    if (Test-Path $file) {
        Write-Host "Removing local file: $file" -ForegroundColor Yellow
        Remove-Item $file -Force
        Write-Host "✅ Removed: $file" -ForegroundColor Green
    } else {
        Write-Host "⚠️ File not found (already clean): $file" -ForegroundColor Yellow
    }
}

# Clean Docker images
Write-Host "Cleaning Docker images for environment: $Environment..." -ForegroundColor Yellow
$acrName = "d837ad$($Environment)containers"
$dockerImages = @(
    "$Environment-recap-web-proxy:latest",
    "recap-web-proxy:latest",
    "$acrName.azurecr.io/$Environment-recap-web-proxy:latest"
)

foreach ($image in $dockerImages) {
    $imageExists = docker images --filter "reference=$image" --format "{{.Repository}}:{{.Tag}}" | Select-String "^$image$"
    if ($imageExists) {
        Write-Host "Removing Docker image: $image" -ForegroundColor Yellow
        docker rmi $image --force
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Removed Docker image: $image" -ForegroundColor Green
        } else {
            Write-Host "⚠️ Failed to remove Docker image: $image" -ForegroundColor Yellow
        }
    } else {
        Write-Host "⚠️ Docker image not found (already clean): $image" -ForegroundColor Yellow
    }
}

Write-Host "" -ForegroundColor White
Write-Host "=== CLEANUP COMPLETE ===" -ForegroundColor Green
Write-Host "All RECAP resources, local files, and Docker images have been deleted/purged for environment: $Environment" -ForegroundColor White
Write-Host "" -ForegroundColor White
Write-Host "You can now run a fresh deployment:" -ForegroundColor Cyan
Write-Host "1. .\recap-subnet-nsg\networking-config.ps1 -Environment $Environment" -ForegroundColor White
Write-Host "2. .\recap-subnet-nsg\private-endpoint-deploy.ps1 -Environment $Environment" -ForegroundColor White
Write-Host "3. .\recap-llm\openai-deploy.ps1 -Environment $Environment" -ForegroundColor White
Write-Host "4. .\recap-web-proxy\nginx-generate-config.ps1 -Environment $Environment" -ForegroundColor White
Write-Host "5. .\recap-web-proxy\acr-container-push.ps1 -Environment $Environment" -ForegroundColor White
Write-Host "6. .\recap-web-proxy\webapp-deploy.ps1 -Environment $Environment" -ForegroundColor White