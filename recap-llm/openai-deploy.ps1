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
Write-Host "Checking Azure CLI authentication..." -ForegroundColor Cyan
try {
    $azAccount = az account show --output json | ConvertFrom-Json
    Write-Host "✅ Authenticated as: $($azAccount.user.name)" -ForegroundColor Green
    Write-Host "✅ Subscription: $($azAccount.name)" -ForegroundColor Green
} catch {
    Write-Host "You are not logged in to Azure. Please log in..." -ForegroundColor Red
    az login
    if (-not $?) {
        Write-Host "Azure login failed. Exiting script." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Step 1: Creating Azure OpenAI Service..." -ForegroundColor Cyan
Write-Host "Note: Using ARM template for BC Gov policy compliance (publicNetworkAccess: Disabled, networkAcls: Deny)" -ForegroundColor Yellow

# Create ARM template for policy compliance
$armTemplate = @"
{
  "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "accountName": {
      "type": "string",
      "defaultValue": "$openAIName"
    },
    "location": {
      "type": "string", 
      "defaultValue": "$Location"
    }
  },
  "resources": [
    {
      "type": "Microsoft.CognitiveServices/accounts",
      "apiVersion": "2023-05-01",
      "name": "[parameters('accountName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "S0"
      },
      "kind": "OpenAI",
      "properties": {
        "customSubDomainName": "[parameters('accountName')]",
        "publicNetworkAccess": "Disabled",
        "networkAcls": {
          "defaultAction": "Deny",
          "ipRules": [],
          "virtualNetworkRules": []
        }
      }
    }
  ]
}
"@

$armTemplate | Out-File -FilePath "openai-template.json" -Encoding UTF8

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "openai-template.json" `
    --parameters accountName=$openAIName location=$Location

Remove-Item "openai-template.json" -Force

if (-not $?) {
    Write-Host "Failed to create Azure OpenAI service." -ForegroundColor Red
    exit 1
}

Write-Host "Step 2: Creating GPT-4o deployment..." -ForegroundColor Cyan

# Check if GPT-4o deployment already exists
try {
    $gpt4oCheck = az cognitiveservices account deployment show --name $openAIName --resource-group $ResourceGroup --deployment-name "gpt-4o" --query "name" --output tsv
    if ($gpt4oCheck -eq "gpt-4o") {
        Write-Host "✅ GPT-4o deployment already exists, skipping..." -ForegroundColor Yellow
        $gpt4oExists = $true
    } else {
        $gpt4oExists = $false
    }
} catch {
    $gpt4oExists = $false
}

if (-not $gpt4oExists) {
    $result = az cognitiveservices account deployment create `
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
    } else {
        Write-Host "GPT-4o deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "Step 3: Creating gpt-4o-mini deployment..." -ForegroundColor Cyan
Write-Host "Note: gpt-4o-mini is 94% cheaper than gpt-4o (\$0.15/\$0.60 vs \$2.50/\$10.00 per M tokens)" -ForegroundColor Yellow

# Check if gpt-4o-mini deployment already exists
try {
    $gpt4oMiniCheck = az cognitiveservices account deployment show --name $openAIName --resource-group $ResourceGroup --deployment-name "gpt-4o-mini" --query "name" --output tsv
    if ($gpt4oMiniCheck -eq "gpt-4o-mini") {
        Write-Host "✅ gpt-4o-mini deployment already exists, skipping..." -ForegroundColor Yellow
        $gpt4oMiniExists = $true
    } else {
        $gpt4oMiniExists = $false
    }
} catch {
    $gpt4oMiniExists = $false
}

if (-not $gpt4oMiniExists) {
    $result = az cognitiveservices account deployment create `
        --name $openAIName `
        --resource-group $ResourceGroup `
        --deployment-name "gpt-4o-mini" `
        --model-name "gpt-4o-mini" `
        --model-version "2024-07-18" `
        --model-format OpenAI `
        --sku-capacity 10 `
        --sku-name "GlobalStandard"

    if (-not $?) {
        Write-Host "Failed to create gpt-4o-mini deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "gpt-4o-mini deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Azure OpenAI Service: $openAIName" -ForegroundColor Yellow
Write-Host "Endpoint: https://$openAIName.openai.azure.com/" -ForegroundColor Yellow
Write-Host "`nModel Deployments:" -ForegroundColor Green
Write-Host "  - gpt-4o (2024-11-20): Standard SKU, capacity 10 - \$2.50/\$10.00 per M tokens" -ForegroundColor White
Write-Host "  - gpt-4o-mini (2024-07-18): GlobalStandard SKU, capacity 10 - \$0.15/\$0.60 per M tokens (94% cheaper)" -ForegroundColor White

Write-Host "`nModel Endpoints:" -ForegroundColor Cyan
Write-Host "  GPT-4o: https://$openAIName.openai.azure.com/openai/deployments/gpt-4o/chat/completions" -ForegroundColor White
Write-Host "  GPT-4o-mini: https://$openAIName.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions" -ForegroundColor White

Write-Host "`nGet API Key:" -ForegroundColor Cyan
Write-Host "az cognitiveservices account keys list --name $openAIName --resource-group $ResourceGroup --query key1 --output tsv" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Create private endpoint using scripts in recap-web-proxy folder" -ForegroundColor White
Write-Host "2. Update nginx configuration with private endpoint details" -ForegroundColor White
Write-Host "3. Deploy web app and proxy container" -ForegroundColor White