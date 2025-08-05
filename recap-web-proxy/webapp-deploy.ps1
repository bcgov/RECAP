# Environment-aware Azure Web App deployment script
# This script handles ONLY web app deployment operations
# Container images should be built and pushed to registry separately

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod", "dev")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$ImageRegistry = "d837ad{env}containers.azurecr.io",
    
    [Parameter(Mandatory=$false)]
    [string]$Repository = "{env}-recap-web-proxy",
    
    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest"
)

Write-Host "=== Azure Web App Deployment ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow

# Replace {env} placeholder in registry name and repository
$resolvedRegistry = $ImageRegistry -replace "\{env\}", $Environment
$resolvedRepository = $Repository -replace "\{env\}", $Environment
$fullImage = "$resolvedRegistry/$resolvedRepository`:$Tag"

Write-Host "Container Image: $fullImage" -ForegroundColor Yellow

# Check if logged in to Azure
$azAccount = az account show 2>$null
if (-not $azAccount) {
    Write-Host "You are not logged in to Azure. Please log in..." -ForegroundColor Red
    az login
    if ($?) {
        Write-Host "Azure login successful." -ForegroundColor Green
    } else {
        Write-Host "Azure login failed. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Already logged in to Azure." -ForegroundColor Green
}

# Resource configuration
$resourceGroup = "d837ad-$Environment-networking"
$webAppName = "d837ad-$Environment-recap-webapp"
$appServicePlan = "d837ad-$Environment-recap-asp"
$acrName = "d837ad$($Environment)containers"
$location = "canadacentral"

# VNet integration settings
$vnetName = "d837ad-$Environment-vwan-spoke"
$webAppSubnetName = "d837ad-$Environment-webapp-integration-subnet"

Write-Host "Resource Group: $resourceGroup" -ForegroundColor Yellow
Write-Host "Web App: $webAppName" -ForegroundColor Yellow
Write-Host "App Service Plan: $appServicePlan" -ForegroundColor Yellow

# Check if App Service Plan exists, create if not
Write-Host "Checking App Service Plan $appServicePlan..." -ForegroundColor Yellow
$aspCheck = az appservice plan show --name $appServicePlan --resource-group $resourceGroup 2>$null
if (-not $aspCheck) {
    Write-Host "Creating App Service Plan $appServicePlan..." -ForegroundColor Yellow
    az appservice plan create `
        --name $appServicePlan `
        --resource-group $resourceGroup `
        --location $location `
        --is-linux `
        --sku B1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "App Service Plan created successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to create App Service Plan. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "App Service Plan $appServicePlan already exists." -ForegroundColor Green
}

# Check if Web App exists, create if not
Write-Host "Checking Web App $webAppName..." -ForegroundColor Yellow
$webAppCheck = az webapp show --name $webAppName --resource-group $resourceGroup 2>$null
if (-not $webAppCheck) {
    Write-Host "Creating Web App $webAppName..." -ForegroundColor Yellow
    az webapp create `
        --name $webAppName `
        --resource-group $resourceGroup `
        --plan $appServicePlan `
        --deployment-container-image-name $fullImage `
        --https-only true
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Web App created successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to create Web App. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Web App $webAppName already exists." -ForegroundColor Green
}

# Add VNet Integration for private endpoint connectivity
Write-Host "Configuring VNet integration for private endpoint access..." -ForegroundColor Yellow
$vnetIntegrationCheck = az webapp vnet-integration list --name $webAppName --resource-group $resourceGroup --query "[0].id" --output tsv 2>$null
if (-not $vnetIntegrationCheck -or $vnetIntegrationCheck -eq "") {
    Write-Host "Adding VNet integration to subnet: $webAppSubnetName" -ForegroundColor Yellow
    az webapp vnet-integration add `
        --name $webAppName `
        --resource-group $resourceGroup `
        --vnet $vnetName `
        --subnet $webAppSubnetName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ VNet integration added successfully" -ForegroundColor Green
    } else {
        Write-Host "⚠️ VNet integration failed - web app may not reach private endpoint" -ForegroundColor Yellow
    }
} else {
    Write-Host "✅ VNet integration already configured" -ForegroundColor Green
}

Write-Host "" -ForegroundColor White
Write-Host "=== Web App Deployment Complete ===" -ForegroundColor Green
Write-Host "Web App URL: https://$webAppName.azurewebsites.net" -ForegroundColor Green
Write-Host "Container Image: $fullImage" -ForegroundColor Green
Write-Host "" -ForegroundColor White
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Test the deployment: https://$webAppName.azurewebsites.net/api/test" -ForegroundColor White
Write-Host "2. Run basic-test.ps1 to verify AI model connectivity" -ForegroundColor White
Write-Host "3. Configure your GitOps pipeline to update the container image" -ForegroundColor White