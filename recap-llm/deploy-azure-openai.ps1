# Azure OpenAI Service Deployment Script
# Creates ONLY the Azure OpenAI service for RECAP proxy
# Private endpoints and networking are handled in recap-web-proxy folder

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod", "dev")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "d837ad-$Environment-networking",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "canadaeast"
)

Write-Host "=== Azure OpenAI Service Deployment ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Yellow
Write-Host "Location: $Location" -ForegroundColor Yellow

# Generate resource names based on environment
$openAIName = "d837ad-$Environment-econ-llm-east"

Write-Host "OpenAI Service: $openAIName" -ForegroundColor Green

# Check if logged in to Azure
$azAccount = az account show 2>$null
if (-not $azAccount) {
    Write-Host "You are not logged in to Azure. Please log in..." -ForegroundColor Red
    az login
    if (-not $?) {
        Write-Host "Azure login failed. Exiting script." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Step 1: Creating Azure OpenAI Service..." -ForegroundColor Cyan
az cognitiveservices account create `
    --name $openAIName `
    --resource-group $ResourceGroup `
    --location $Location `
    --kind OpenAI `
    --sku S0 `
    --public-network-access Disabled `
    --custom-domain $openAIName

if (-not $?) {
    Write-Host "Failed to create Azure OpenAI service." -ForegroundColor Red
    exit 1
}

Write-Host "Step 2: Creating GPT-4o deployment..." -ForegroundColor Cyan
az cognitiveservices account deployment create `
    --name $openAIName `
    --resource-group $ResourceGroup `
    --deployment-name "gpt-4o" `
    --model-name "gpt-4o" `
    --model-version "2024-11-20" `
    --model-format OpenAI `
    --sku-capacity 10 `
    --sku-name "Standard"

if (-not $?) {
    Write-Host "Failed to create GPT-4o deployment." -ForegroundColor Red
    exit 1
}

Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Azure OpenAI Service: $openAIName" -ForegroundColor Yellow
Write-Host "Endpoint: https://$openAIName.openai.azure.com/" -ForegroundColor Yellow

Write-Host "`nGet API Key:" -ForegroundColor Cyan
Write-Host "az cognitiveservices account keys list --name $openAIName --resource-group $ResourceGroup --query key1 --output tsv" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Create private endpoint using scripts in recap-web-proxy folder" -ForegroundColor White
Write-Host "2. Update nginx configuration with private endpoint details" -ForegroundColor White
Write-Host "3. Deploy web app and proxy container" -ForegroundColor White