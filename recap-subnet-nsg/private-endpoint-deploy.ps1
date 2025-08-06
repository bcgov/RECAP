# Private Endpoint Creation for Azure OpenAI Service
# Creates private endpoint to connect OpenAI service to VNet

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "d837ad-$Environment-networking",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "canadacentral"
)

Write-Host "=== Private Endpoint Creation for OpenAI Service ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Yellow

# Resource names based on environment
$openAIName = "d837ad-$Environment-econ-llm-east"
$privateEndpointName = "d837ad-$Environment-econ-llm-east-pe"
$vnetName = "d837ad-$Environment-vwan-spoke"
$subnetName = "d837ad-$Environment-private-endpoint-subnet"
$connectionName = "openai-private-connection"

Write-Host "`nResources:" -ForegroundColor Green
Write-Host "  OpenAI Service: $openAIName" -ForegroundColor White
Write-Host "  Private Endpoint: $privateEndpointName" -ForegroundColor White
Write-Host "  VNet: $vnetName" -ForegroundColor White
Write-Host "  Subnet: $subnetName" -ForegroundColor White

# Check Azure CLI authentication
Write-Host "`nChecking Azure CLI authentication..." -ForegroundColor Cyan
try {
    $azAccount = az account show --output json | ConvertFrom-Json
    Write-Host "✅ Authenticated as: $($azAccount.user.name)" -ForegroundColor Green
    Write-Host "✅ Subscription: $($azAccount.name)" -ForegroundColor Green
} catch {
    Write-Host "❌ Not logged in to Azure. Please log in..." -ForegroundColor Red
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Azure login failed. Exiting script." -ForegroundColor Red
        exit 1
    }
}

# Get subscription ID for resource ID construction
$subscriptionId = az account show --query "id" --output tsv
$openAIResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$openAIName"

Write-Host "`nOpenAI Resource ID: $openAIResourceId" -ForegroundColor Yellow

# Verify OpenAI service exists
Write-Host "`nVerifying OpenAI service exists..." -ForegroundColor Cyan
$openAIService = az cognitiveservices account show --name $openAIName --resource-group $ResourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ OpenAI service $openAIName not found. Please deploy it first." -ForegroundColor Red
    exit 1
}
Write-Host "✅ OpenAI service verified" -ForegroundColor Green

# Verify subnet exists
Write-Host "Verifying private endpoint subnet exists..." -ForegroundColor Cyan
$subnet = az network vnet subnet show --name $subnetName --vnet-name $vnetName --resource-group $ResourceGroup 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Subnet $subnetName not found. Please create networking infrastructure first." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Private endpoint subnet verified" -ForegroundColor Green

# Check if private endpoint already exists
Write-Host "`nChecking if private endpoint already exists..." -ForegroundColor Cyan
$existingPE = az network private-endpoint show --name $privateEndpointName --resource-group $ResourceGroup 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "⚠️ Private endpoint $privateEndpointName already exists. Skipping creation." -ForegroundColor Yellow
    
    # Show existing private endpoint details
    $peDetails = az network private-endpoint show --name $privateEndpointName --resource-group $ResourceGroup --query "{Name:name, State:provisioningState, PrivateIp:customDnsConfigs[0].ipAddresses[0]}" --output json | ConvertFrom-Json
    Write-Host "✅ Existing Private Endpoint Details:" -ForegroundColor Green
    Write-Host "  Name: $($peDetails.Name)" -ForegroundColor White
    Write-Host "  State: $($peDetails.State)" -ForegroundColor White
    Write-Host "  Private IP: $($peDetails.PrivateIp)" -ForegroundColor White
    
    exit 0
}

# Create private endpoint
Write-Host "`nCreating private endpoint..." -ForegroundColor Cyan
Write-Host "This may take 2-3 minutes..." -ForegroundColor Yellow

$privateEndpointResult = az network private-endpoint create `
    --name $privateEndpointName `
    --resource-group $ResourceGroup `
    --vnet-name $vnetName `
    --subnet $subnetName `
    --private-connection-resource-id $openAIResourceId `
    --group-id "account" `
    --connection-name $connectionName `
    --location $Location 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create private endpoint:" -ForegroundColor Red
    Write-Host $privateEndpointResult -ForegroundColor Red
    exit 1
}

Write-Host "✅ Private endpoint created successfully!" -ForegroundColor Green

# Configure OpenAI network access rules
Write-Host "`nConfiguring OpenAI network access for private endpoint..." -ForegroundColor Cyan
$networkRuleResult = az cognitiveservices account network-rule add `
    --name $openAIName `
    --resource-group $ResourceGroup `
    --vnet $vnetName `
    --subnet $subnetName 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ OpenAI network access rule added for private endpoint subnet" -ForegroundColor Green
} else {
    Write-Host "⚠️ Failed to add OpenAI network rule for private endpoint (may already exist): $networkRuleResult" -ForegroundColor Yellow
}

# Also add network rule for web app integration subnet
$webAppSubnetName = "d837ad-$Environment-webapp-integration-subnet"
Write-Host "Configuring OpenAI network access for web app integration..." -ForegroundColor Cyan
$webAppNetworkRuleResult = az cognitiveservices account network-rule add `
    --name $openAIName `
    --resource-group $ResourceGroup `
    --vnet $vnetName `
    --subnet $webAppSubnetName 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ OpenAI network access rule added for web app integration subnet" -ForegroundColor Green
} else {
    Write-Host "⚠️ Failed to add OpenAI network rule for web app integration (may already exist): $webAppNetworkRuleResult" -ForegroundColor Yellow
}

# Wait a moment for DNS to propagate
Write-Host "`nWaiting for DNS propagation..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Get private endpoint details
Write-Host "`nRetrieving private endpoint details..." -ForegroundColor Cyan
$peDetails = az network private-endpoint show `
    --name $privateEndpointName `
    --resource-group $ResourceGroup `
    --query "{Name:name, State:provisioningState, Location:location}" `
    --output json | ConvertFrom-Json

# Try to get private IP address
$privateIP = $null
try {
    $privateIP = az network private-endpoint show `
        --name $privateEndpointName `
        --resource-group $ResourceGroup `
        --query "customDnsConfigs[0].ipAddresses[0]" `
        --output tsv 2>$null
    
    if ([string]::IsNullOrEmpty($privateIP) -or $privateIP -eq "null") {
        # Try alternative method with network interface
        $nicId = az network private-endpoint show `
            --name $privateEndpointName `
            --resource-group $ResourceGroup `
            --query "networkInterfaces[0].id" `
            --output tsv
        
        if (![string]::IsNullOrEmpty($nicId)) {
            $nicName = ($nicId -split '/')[-1]
            $privateIP = az network nic show --ids $nicId --query "ipConfigurations[0].privateIPAddress" --output tsv
        }
    }
} catch {
    Write-Host "⚠️ Could not retrieve private IP immediately. This is normal - DNS may still be propagating." -ForegroundColor Yellow
}

Write-Host "`n=== Private Endpoint Creation Complete ===" -ForegroundColor Green
Write-Host "✅ Private Endpoint: $($peDetails.Name)" -ForegroundColor White
Write-Host "✅ State: $($peDetails.State)" -ForegroundColor White
Write-Host "✅ Location: $($peDetails.Location)" -ForegroundColor White

if (![string]::IsNullOrEmpty($privateIP) -and $privateIP -ne "null") {
    Write-Host "✅ Private IP Address: $privateIP" -ForegroundColor White
} else {
    Write-Host "⚠️ Private IP Address: Not yet available (DNS propagating)" -ForegroundColor Yellow
}

Write-Host "`nConnection Details:" -ForegroundColor Cyan
Write-Host "  Connection Name: $connectionName" -ForegroundColor White
Write-Host "  Target Resource: $openAIName" -ForegroundColor White
Write-Host "  Subnet: $subnetName" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Wait 2-3 minutes for DNS propagation" -ForegroundColor White
Write-Host "2. Generate nginx configuration: .\recap-web-proxy\nginx-generate-config.ps1 -Environment $Environment" -ForegroundColor White
Write-Host "3. Build and deploy web app" -ForegroundColor White

Write-Host "`nTo verify private endpoint IP later:" -ForegroundColor Cyan
Write-Host "az network private-endpoint show --name $privateEndpointName --resource-group $ResourceGroup --query `"customDnsConfigs[0].ipAddresses[0]`" --output tsv" -ForegroundColor Gray