# BC Gov Azure Web App Deployment Script
# This script deploys the RECAP web proxy to BC Gov's public cloud landing zone
# Following EPIC.search deployment patterns

param(
    [string]$EnvironmentFile = ".env",
    [string]$Environment = "test"
)

# Load environment variables from file (similar to EPIC.search pattern)
if (Test-Path $EnvironmentFile) {
    Get-Content $EnvironmentFile | ForEach-Object {
        if ($_ -match "^([^#][^=]*)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
    Write-Host "Loaded configuration from $EnvironmentFile" -ForegroundColor Green
} else {
    Write-Host "Environment file not found. Please copy sample.env to .env and configure." -ForegroundColor Red
    exit 1
}

# BC Gov naming convention: ministry-environment-application-resource
$MinistryCode = $env:MINISTRY_CODE
$WebAppName = "$MinistryCode-$Environment-recap-webapp"
$AppServicePlan = "$MinistryCode-$Environment-recap-asp"
$ResourceGroupName = $env:RESOURCE_GROUP_NAME
$SubscriptionId = $env:SUBSCRIPTION_ID
$Location = $env:LOCATION
$ContainerRegistry = $env:CONTAINER_REGISTRY

Write-Host "Deploying RECAP Web Proxy to BC Gov Azure..." -ForegroundColor Green

# Set subscription context
az account set --subscription $SubscriptionId

# Create App Service Plan (Linux)
Write-Host "Creating App Service Plan: $AppServicePlan" -ForegroundColor Yellow
az appservice plan create `
    --name $AppServicePlan `
    --resource-group $ResourceGroupName `
    --location $Location `
    --is-linux `
    --sku B1

# Build and push Docker image to ACR
Write-Host "Building and pushing Docker image..." -ForegroundColor Yellow
$ImageName = "recap-web-proxy:latest"
$AcrLoginServer = "$ContainerRegistry.azurecr.io"

# Login to ACR
az acr login --name $ContainerRegistry

# Build and push image
docker build -t $ImageName .
docker tag $ImageName "$AcrLoginServer/$ImageName"
docker push "$AcrLoginServer/$ImageName"

# Create Web App for Containers
Write-Host "Creating Web App: $WebAppName" -ForegroundColor Yellow
az webapp create `
    --resource-group $ResourceGroupName `
    --plan $AppServicePlan `
    --name $WebAppName `
    --deployment-container-image-name "$AcrLoginServer/$ImageName"

# Configure Web App to use ACR
Write-Host "Configuring container registry..." -ForegroundColor Yellow
az webapp config container set `
    --name $WebAppName `
    --resource-group $ResourceGroupName `
    --docker-custom-image-name "$AcrLoginServer/$ImageName" `
    --docker-registry-server-url "https://$AcrLoginServer"

# Enable container registry authentication
az webapp identity assign --resource-group $ResourceGroupName --name $WebAppName
$principalId = (az webapp identity show --resource-group $ResourceGroupName --name $WebAppName --query principalId --output tsv)

# Grant ACR pull permissions to web app
az role assignment create `
    --assignee $principalId `
    --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerRegistry/registries/$ContainerRegistry" `
    --role AcrPull

# Configure app settings for BC Gov compliance
Write-Host "Configuring app settings..." -ForegroundColor Yellow
az webapp config appsettings set `
    --resource-group $ResourceGroupName `
    --name $WebAppName `
    --settings `
        WEBSITES_ENABLE_APP_SERVICE_STORAGE=false `
        WEBSITES_PORT=80 `
        DOCKER_REGISTRY_SERVER_URL="https://$AcrLoginServer"

Write-Host "Deployment completed!" -ForegroundColor Green
Write-Host "Your app is available at: https://$WebAppName.azurewebsites.net" -ForegroundColor Cyan

# Display resource information
Write-Host "`nDeployed Resources:" -ForegroundColor Yellow
az resource list --resource-group $ResourceGroupName --output table