# Environment-aware Azure Container Registry (ACR) script
# This script handles ONLY ACR operations: create, tag, login, and push
# Web app deployment is handled separately for GitOps integration

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod", "dev")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$LocalImage = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Repository = "recap-web-proxy",
    
    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest"
)

Write-Host "=== Azure Container Registry Operations ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Local Image: $LocalImage" -ForegroundColor Yellow
Write-Host "Repository: $Repository" -ForegroundColor Yellow
Write-Host "Tag: $Tag" -ForegroundColor Yellow

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

# Set default local image name if not provided
if ([string]::IsNullOrEmpty($LocalImage)) {
    $LocalImage = "$Environment-recap-web-proxy:latest"
}

# ACR configuration
$resourceGroup = "d837ad-$Environment-networking"
$acrName = "d837ad$($Environment)containers"
$acrLoginServer = "$acrName.azurecr.io"
$acrImage = "$acrLoginServer/$Environment-$Repository" + ":" + "$Tag"

# Check if ACR exists, create if not
Write-Host "Checking for Azure Container Registry $acrName..." -ForegroundColor Yellow
$acrCheck = az acr show --name $acrName --resource-group $resourceGroup 2>$null
if (-not $acrCheck) {
    Write-Host "ACR $acrName does not exist. Creating..." -ForegroundColor Yellow
    az acr create --name $acrName --resource-group $resourceGroup --sku Basic --admin-enabled true
    if ($?) {
        Write-Host "ACR $acrName created successfully." -ForegroundColor Green
    } else {
        Write-Host "Failed to create ACR $acrName. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "ACR $acrName already exists." -ForegroundColor Green
}

# Check if local image exists, build if not
Write-Host "Checking if local image $LocalImage exists..." -ForegroundColor Yellow
$imageExists = docker images --format "table {{.Repository}}:{{.Tag}}" | Select-String -Pattern "^$LocalImage$"
if (-not $imageExists) {
    Write-Host "Local image $LocalImage not found. Building Docker image with $Environment nginx.conf..." -ForegroundColor Yellow
    docker build -t $LocalImage .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker image built successfully with $Environment configuration." -ForegroundColor Green
    } else {
        Write-Host "Failed to build Docker image. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Local image $LocalImage already exists." -ForegroundColor Green
}

# Tag the local image for ACR
Write-Host "Tagging local image $LocalImage as $acrImage..." -ForegroundColor Yellow
docker tag $LocalImage $acrImage
if ($LASTEXITCODE -eq 0) {
    Write-Host "Image tagged successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to tag image. Exiting script." -ForegroundColor Red
    exit 1
}

# Log in to ACR
Write-Host "Logging in to Azure Container Registry $acrLoginServer..." -ForegroundColor Yellow
az acr login --name $acrName
if ($?) {
    Write-Host "ACR login successful." -ForegroundColor Green
} else {
    Write-Host "ACR login failed. Exiting script." -ForegroundColor Red
    exit 1
}

# Push the image to ACR
Write-Host "Pushing image $acrImage to ACR..." -ForegroundColor Yellow
docker push $acrImage
if ($LASTEXITCODE -eq 0) {
    Write-Host "Image pushed to ACR successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to push image to ACR. Exiting script." -ForegroundColor Red
    exit 1
}

# Verify image in ACR
Write-Host "Verifying image in ACR..." -ForegroundColor Yellow
$acrRepository = "$Environment-$Repository"
az acr repository show-tags --name $acrName --repository $acrRepository --output table

Write-Host "" -ForegroundColor White
Write-Host "=== ACR Operations Complete ===" -ForegroundColor Green
Write-Host "Image: $acrImage" -ForegroundColor Green
Write-Host "Registry: $acrLoginServer" -ForegroundColor Green
Write-Host "" -ForegroundColor White
Write-Host "Next Steps for GitOps Integration:" -ForegroundColor Cyan
Write-Host "1. Update your GitOps pipeline to pull from: $acrImage" -ForegroundColor White
Write-Host "2. Or configure JFrog Artifactory to sync from this ACR" -ForegroundColor White
Write-Host "3. Deploy web app using separate deployment script" -ForegroundColor White
