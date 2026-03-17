# Azure OpenAI Service Deployment Setup for RECAP Proxy
# Creates the Azure OpenAI service for RECAP proxy
# Private endpoints and networking are handled in recap-web-proxy folder

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod")]
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
    Write-Host "[SUCCESS] Authenticated as: $($azAccount.user.name)" -ForegroundColor Green
    Write-Host "[SUCCESS] Subscription: $($azAccount.name)" -ForegroundColor Green
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
        Write-Host "[SUCCESS] GPT-4o deployment already exists, skipping..." -ForegroundColor Yellow
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
        --sku-capacity 150 `
        --sku-name "Standard"

    if (-not $?) {
        Write-Host "Failed to create GPT-4o deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "GPT-4o deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "Step 3: Creating GPT-4o-mini deployment..." -ForegroundColor Cyan

# Check if GPT-4o-mini deployment already exists
try {
    $gpt4oMiniCheck = az cognitiveservices account deployment show --name $openAIName --resource-group $ResourceGroup --deployment-name "gpt-4o-mini" --query "name" --output tsv
    if ($gpt4oMiniCheck -eq "gpt-4o-mini") {
        Write-Host "[SUCCESS] GPT-4o-mini deployment already exists, skipping..." -ForegroundColor Yellow
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
        --sku-capacity 250 `
        --sku-name "GlobalStandard"

    if (-not $?) {
        Write-Host "Failed to create GPT-4o-mini deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "GPT-4o-mini deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "Step 4: Creating GPT-5-mini deployment..." -ForegroundColor Cyan
Write-Host "Note: GPT-5-mini is next-generation model with enhanced capabilities" -ForegroundColor Yellow

# Check if GPT-5-mini deployment already exists
try {
    $gpt5MiniCheck = az cognitiveservices account deployment show --name $openAIName --resource-group $ResourceGroup --deployment-name "gpt-5-mini" --query "name" --output tsv
    if ($gpt5MiniCheck -eq "gpt-5-mini") {
        Write-Host "[SUCCESS] GPT-5-mini deployment already exists, skipping..." -ForegroundColor Yellow
        $gpt5MiniExists = $true
    } else {
        $gpt5MiniExists = $false
    }
} catch {
    $gpt5MiniExists = $false
}

if (-not $gpt5MiniExists) {
    $result = az cognitiveservices account deployment create `
        --name $openAIName `
        --resource-group $ResourceGroup `
        --deployment-name "gpt-5-mini" `
        --model-name "gpt-5-mini" `
        --model-version "2025-08-07" `
        --model-format OpenAI `
        --sku-capacity 250 `
        --sku-name "GlobalStandard"

    if (-not $?) {
        Write-Host "Failed to create GPT-5-mini deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "GPT-5-mini deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "Step 5: Creating GPT-5-nano deployment..." -ForegroundColor Cyan
Write-Host "Note: GPT-5-nano is next-generation nano model with fastest response times" -ForegroundColor Yellow

# Check if GPT-5-nano deployment already exists
try {
    $gpt5NanoCheck = az cognitiveservices account deployment show --name $openAIName --resource-group $ResourceGroup --deployment-name "gpt-5-nano" --query "name" --output tsv
    if ($gpt5NanoCheck -eq "gpt-5-nano") {
        Write-Host "[SUCCESS] GPT-5-nano deployment already exists, skipping..." -ForegroundColor Yellow
        $gpt5NanoExists = $true
    } else {
        $gpt5NanoExists = $false
    }
} catch {
    $gpt5NanoExists = $false
}

if (-not $gpt5NanoExists) {
    $result = az cognitiveservices account deployment create `
        --name $openAIName `
        --resource-group $ResourceGroup `
        --deployment-name "gpt-5-nano" `
        --model-name "gpt-5-nano" `
        --model-version "2025-08-07" `
        --model-format OpenAI `
        --sku-capacity 300 `
        --sku-name "GlobalStandard"

    if (-not $?) {
        Write-Host "Failed to create GPT-5-nano deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "GPT-5-nano deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "Step 6: Creating text-embedding-3-large deployment..." -ForegroundColor Cyan
Write-Host "Note: text-embedding-3-large provides high-quality embeddings with enhanced rate limits" -ForegroundColor Yellow

# Check if text-embedding-3-large deployment already exists
try {
    $embeddingCheck = az cognitiveservices account deployment show --name $openAIName --resource-group $ResourceGroup --deployment-name "text-embedding-3-large" --query "name" --output tsv
    if ($embeddingCheck -eq "text-embedding-3-large") {
        Write-Host "[SUCCESS] text-embedding-3-large deployment already exists, skipping..." -ForegroundColor Yellow
        $embeddingExists = $true
    } else {
        $embeddingExists = $false
    }
} catch {
    $embeddingExists = $false
}

if (-not $embeddingExists) {
    $result = az cognitiveservices account deployment create `
        --name $openAIName `
        --resource-group $ResourceGroup `
        --deployment-name "text-embedding-3-large" `
        --model-name "text-embedding-3-large" `
        --model-version "1" `
        --model-format OpenAI `
        --sku-capacity 150 `
        --sku-name "Standard"

    if (-not $?) {
        Write-Host "Failed to create text-embedding-3-large deployment." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "text-embedding-3-large deployment created successfully." -ForegroundColor Green
    }
}

Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host "Azure OpenAI Service: $openAIName" -ForegroundColor Yellow
Write-Host "Endpoint: https://$openAIName.openai.azure.com/" -ForegroundColor Yellow
Write-Host "`nModel Deployments:" -ForegroundColor Green
Write-Host "  - gpt-4o (2024-11-20): Standard SKU, capacity 150 - \$2.50/\$10.00 per M tokens" -ForegroundColor White
Write-Host "  - gpt-4o-mini (2024-07-18): GlobalStandard SKU, capacity 250 - \$0.15/\$0.60 per M tokens (94% cheaper)" -ForegroundColor White
Write-Host "  - gpt-5-mini (2025-08-07): GlobalStandard SKU, capacity 250 - Next-generation model" -ForegroundColor White
Write-Host "  - gpt-5-nano (2025-08-07): GlobalStandard SKU, capacity 300 - Next-generation nano model (fastest)" -ForegroundColor White
Write-Host "  - text-embedding-3-large (1): Standard SKU, capacity 150 - High-quality embeddings" -ForegroundColor White

Write-Host "`nModel Endpoints:" -ForegroundColor Cyan
Write-Host "  GPT-4o: https://$openAIName.openai.azure.com/openai/deployments/gpt-4o/chat/completions" -ForegroundColor White
Write-Host "  GPT-4o-mini: https://$openAIName.openai.azure.com/openai/deployments/gpt-4o-mini/chat/completions" -ForegroundColor White
Write-Host "  GPT-5-mini: https://$openAIName.openai.azure.com/openai/deployments/gpt-5-mini/chat/completions" -ForegroundColor White
Write-Host "  GPT-5-nano: https://$openAIName.openai.azure.com/openai/deployments/gpt-5-nano/chat/completions" -ForegroundColor White
Write-Host "  Embeddings: https://$openAIName.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings" -ForegroundColor White

Write-Host "`nGet API Key:" -ForegroundColor Cyan
Write-Host "az cognitiveservices account keys list --name $openAIName --resource-group $ResourceGroup --query key1 --output tsv" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Create private endpoint using scripts in recap-web-proxy folder" -ForegroundColor White
Write-Host "2. Update nginx configuration with private endpoint details" -ForegroundColor White
Write-Host "3. Deploy web app and proxy container" -ForegroundColor White