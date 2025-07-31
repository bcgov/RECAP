# Check if logged in to Azure

$azAccount = az account show 2>$null
if (-not $azAccount) {
    Write-Host "You are not logged in to Azure. Please log in..."
    az login
    if ($?) {
        Write-Host "Azure login successful." -ForegroundColor Yellow
    } else {
        Write-Host "Azure login failed. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Already logged in to Azure." -ForegroundColor Green
}

# Docker image and ACR details
$containerName = "nginx-container"
$resourceGroup = "d837ad-test-networking"
$localImage = "recap-web-proxy:latest"  # Change if your local image name is different

# Azure must be able to pull the image from a registry that it can access, such as:
# - Azure Container Registry (ACR)
# - Docker Hub (public or authenticated)
# - Another public/private registry accessible from Azure
$acrName = "d837adcontainers"
$acrLoginServer = "$acrName.azurecr.io"
$acrImage = "$acrLoginServer/recap-web-proxy:latest"

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

# Tag the local image for ACR
Write-Host "Tagging local image $localImage as $acrImage..." -ForegroundColor Yellow
docker tag $localImage $acrImage
if ($?) {
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
if ($?) {
    Write-Host "Image pushed to ACR successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to push image to ACR. Exiting script." -ForegroundColor Red
    exit 1
}


# Drop the container if it exists
$existingContainer = az container show --name $containerName --resource-group $resourceGroup 2>$null
if ($existingContainer) {
    Write-Host "Container $containerName exists. Deleting..." -ForegroundColor Yellow
    az container delete --name $containerName --resource-group $resourceGroup --yes
    if ($?) {
        Write-Host "Container $containerName deleted." -ForegroundColor Yellow
    } else {
        Write-Host "Failed to delete container $containerName. Exiting script." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "No existing container named $containerName found. Proceeding to create." -ForegroundColor Green
}

# Troubleshoot: List images in ACR before create
Write-Host "Listing images in ACR to verify image existence..." -ForegroundColor Yellow
az acr repository show-tags --name $acrName --repository recap-web-proxy

# Get ACR admin credentials
Write-Host "Fetching ACR admin credentials..." -ForegroundColor Yellow
$acrCreds = az acr credential show --name $acrName | ConvertFrom-Json
$acrUsername = $acrCreds.username
$acrPassword = $acrCreds.passwords[0].value

# Create the container instance with DNS name label for FQDN
$dnsNameLabel = "$containerName-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
Write-Host "Creating container $containerName with DNS name label $dnsNameLabel..." -ForegroundColor Yellow
az container create `
  --resource-group $resourceGroup `
  --name $containerName `
  --image $acrImage `
  --registry-login-server $acrLoginServer `
  --registry-username $acrUsername `
  --registry-password $acrPassword `
  --ip-address public `
  --dns-name-label $dnsNameLabel `
  --ports 8080 `
  --os-type Linux `
  --cpu 1 `
  --memory 1.0
if ($?) {
    Write-Host "Container $containerName created successfully. FQDN: $dnsNameLabel.$($resourceGroup.ToLower()).azurecontainer.io" -ForegroundColor Green
} else {
    Write-Host "Failed to create container $containerName." -ForegroundColor Red
    exit 1
}
