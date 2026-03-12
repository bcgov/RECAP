# Environment-aware Azure Web App deployment script
# This script handles ONLY web app deployment operations
# Container images should be built and pushed to registry separately

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod")]
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
        Write-Host "[SUCCESS] VNet integration added successfully" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] VNet integration failed - web app may not reach private endpoint" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SUCCESS] VNet integration already configured" -ForegroundColor Green
}

# Configure IP access restrictions for BC Gov compliance and testing
Write-Host "Configuring IP access restrictions for $Environment environment..." -ForegroundColor Yellow

# Define SPANBC networks for BC Government access (required for both environments)
# Using actual production ranges: 142.22.0.0/15,142.24.0.0/13,142.32.0.0/14,142.36.0.0/16
$spanbcNetworks = @(
    "142.22.0.0/15",
    "142.24.0.0/13", 
    "142.32.0.0/14",
    "142.36.0.0/16"
)

# Define Telus IP ranges for testing access
$telusIpRanges = @(
    "75.155.0.0/16",
    "75.157.0.0/16", 
    "99.199.0.0/16",
    "108.180.0.0/16",
    "142.35.213.64/27",
    "142.32.85.64/27",
    "38.23.0.0/16"
)

# Environment-specific access rules based on actual deployed configurations
if ($Environment -eq "test") {
    # Test environment: Actual rules from d837ad-test-recap-webapp
    Write-Host "Applying test environment access rules (actual deployed rules)" -ForegroundColor Cyan
    
    # Rogers ISP ranges (actual test environment rule)
    $rogersIpRanges = @(
        "24.69.0.0/16",
        "70.67.0.0/16"
    )
    
    # UVic network ranges (actual test environment rule)  
    $uvicIpRanges = @(
        "206.87.0.0/16"
    )
    
    $accessRules = @(
        @{Name="Allow-SPANBC-To-WebApp"; IPs=$spanbcNetworks; Priority=1000; Description="Allow SPANBC IP range to access web app"},
        @{Name="Allow Telus IPs for testing"; IPs=$telusIpRanges; Priority=2000; Description="Allow Telus ISP IP range to access web app"},
        @{Name="Allow Rogers IPs for testing"; IPs=$rogersIpRanges; Priority=2000; Description="Allow Rogers ISP IP range to access web app"},
        @{Name="Allow UVic IPs for testing"; IPs=$uvicIpRanges; Priority=2000; Description="Allow UVic ISP IP range to access web app"}
    )
} else {
    # Production environment: Actual rules from d837ad-prod-recap-webapp  
    Write-Host "Applying production environment access rules (actual deployed rules)" -ForegroundColor Cyan
    
    $accessRules = @(
        @{Name="Allow-SPANBC-To-WebApp"; IPs=$spanbcNetworks; Priority=1000; Description="Allow SPANBC IP range to access web app"},
        @{Name="Allow Telus IPs for testing"; IPs=$telusIpRanges; Priority=2000; Description="Allow Telus ISP IP range to access web app"}
    )
}

# Apply access restriction rules
foreach ($rule in $accessRules) {
    # Skip rules with empty IP arrays (like developer networks with no IPs defined)
    if ($rule.IPs.Count -eq 0 -or ($rule.IPs.Count -eq 1 -and [string]::IsNullOrEmpty($rule.IPs[0]))) {
        Write-Host "Skipping '$($rule.Name)' - no IP addresses defined" -ForegroundColor Yellow
        continue
    }
    
    # Check if access restriction already exists
    $existingRule = az webapp config access-restriction show --name $webAppName --resource-group $resourceGroup --query "ipSecurityRestrictions[?name=='$($rule.Name)']" --output tsv 2>$null

    if (-not $existingRule) {
        Write-Host "Adding access restriction rule: $($rule.Name)..." -ForegroundColor Yellow
        
        # Create comma-separated IP list for Azure CLI
        $ipList = $rule.IPs -join ","
        
        az webapp config access-restriction add `
            --name $webAppName `
            --resource-group $resourceGroup `
            --rule-name $rule.Name `
            --action Allow `
            --ip-address $ipList `
            --priority $rule.Priority `
            --description $rule.Description
            
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[SUCCESS] '$($rule.Name)' access restriction rule added successfully" -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Failed to add '$($rule.Name)' access restriction rule - manual configuration may be required" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[SUCCESS] '$($rule.Name)' access restriction rule already exists" -ForegroundColor Green
    }
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