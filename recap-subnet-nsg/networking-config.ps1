# Networking Infrastructure Setup for RECAP
# Creates subnets, NSGs, and private endpoint prerequisites

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("test", "prod")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "d837ad-$Environment-networking",
    
    [Parameter(Mandatory=$false)]
    [string]$VNetName = "d837ad-$Environment-vwan-spoke",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "canadacentral"
)

Write-Host "=== RECAP Networking Infrastructure Setup ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Yellow
Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Yellow
Write-Host "VNet: $VNetName" -ForegroundColor Yellow

# Network configuration based on RECAP documentation - environment specific IP ranges
switch ($Environment) {
    "test" {
        $vnetAddressSpace = "10.46.75.0/24"
        $privateEndpointSubnetPrefix = "10.46.75.0/27"
        $webAppSubnetPrefix = "10.46.75.32/28"
    }
    "prod" {
        $vnetAddressSpace = "10.46.76.0/24"
        $privateEndpointSubnetPrefix = "10.46.76.0/27"
        $webAppSubnetPrefix = "10.46.76.32/28"
    }
}
$privateEndpointSubnetName = "d837ad-$Environment-private-endpoint-subnet"
$webAppSubnetName = "d837ad-$Environment-webapp-integration-subnet"

# NSG names
$privateEndpointNsgName = "d837ad-$Environment-pe-nsg"
$webAppNsgName = "d837ad-$Environment-webapp-nsg"

Write-Host "`nNetwork Configuration:" -ForegroundColor Green
Write-Host "  VNet Address Space: $vnetAddressSpace" -ForegroundColor White
Write-Host "  Private Endpoint Subnet: $privateEndpointSubnetPrefix (/27 - 27 usable IPs)" -ForegroundColor White
Write-Host "  Web App Integration Subnet: $webAppSubnetPrefix (/28 - 11 usable IPs)" -ForegroundColor White

# Check Azure CLI authentication
Write-Host "`nChecking Azure CLI authentication..." -ForegroundColor Cyan
try {
    $azAccount = az account show --output json | ConvertFrom-Json
    Write-Host "✅ Authenticated as: $($azAccount.user.name)" -ForegroundColor Green
    Write-Host "✅ Subscription: $($azAccount.name)" -ForegroundColor Green
} catch {
    Write-Host "❌ Not logged in to Azure. Please log in..." -ForegroundColor Red
    az login
    if (-not $?) {
        Write-Host "Azure login failed. Exiting script." -ForegroundColor Red
        exit 1
    }
}

# Step 1: Create Network Security Groups
Write-Host "`nStep 1: Creating Network Security Groups..." -ForegroundColor Cyan

# Private Endpoint NSG
Write-Host "Creating NSG for private endpoint subnet..." -ForegroundColor Yellow
$nsgResult = az network nsg create `
    --name $privateEndpointNsgName `
    --resource-group $ResourceGroup `
    --location $Location 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create private endpoint NSG: $nsgResult" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Private endpoint NSG created successfully" -ForegroundColor Green

# Add rule to allow SPANBC traffic (142.22.0.0/16)
az network nsg rule create `
    --name "Allow-SPANBC-Inbound" `
    --nsg-name $privateEndpointNsgName `
    --resource-group $ResourceGroup `
    --priority 1000 `
    --source-address-prefixes "142.22.0.0/16" `
    --destination-port-ranges 443 `
    --access Allow `
    --protocol Tcp `
    --direction Inbound `
    --description "Allow SPANBC network access to OpenAI"

# Web App Integration NSG  
Write-Host "Creating NSG for web app integration subnet..." -ForegroundColor Yellow
$webAppNsgResult = az network nsg create `
    --name $webAppNsgName `
    --resource-group $ResourceGroup `
    --location $Location 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create web app NSG: $webAppNsgResult" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Web app NSG created successfully" -ForegroundColor Green

# Add rule for web app outbound to private endpoint
az network nsg rule create `
    --name "Allow-WebApp-To-PrivateEndpoint" `
    --nsg-name $webAppNsgName `
    --resource-group $ResourceGroup `
    --priority 1000 `
    --source-address-prefixes $webAppSubnetPrefix `
    --destination-address-prefixes $privateEndpointSubnetPrefix `
    --destination-port-ranges 443 `
    --access Allow `
    --protocol Tcp `
    --direction Outbound `
    --description "Allow web app to access private endpoint"

Write-Host "✅ Network Security Groups created successfully" -ForegroundColor Green

# Step 2: Create Subnets
Write-Host "`nStep 2: Creating Subnets..." -ForegroundColor Cyan

# Private Endpoint Subnet
Write-Host "Creating private endpoint subnet ($privateEndpointSubnetPrefix)..." -ForegroundColor Yellow
az network vnet subnet create `
    --name $privateEndpointSubnetName `
    --resource-group $ResourceGroup `
    --vnet-name $VNetName `
    --address-prefixes $privateEndpointSubnetPrefix `
    --network-security-group $privateEndpointNsgName `
    --disable-private-endpoint-network-policies true

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create private endpoint subnet" -ForegroundColor Red
    exit 1
}

# Web App Integration Subnet
Write-Host "Creating web app integration subnet ($webAppSubnetPrefix)..." -ForegroundColor Yellow
az network vnet subnet create `
    --name $webAppSubnetName `
    --resource-group $ResourceGroup `
    --vnet-name $VNetName `
    --address-prefixes $webAppSubnetPrefix `
    --network-security-group $webAppNsgName `
    --delegations Microsoft.Web/serverFarms

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create web app integration subnet" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Subnets created successfully" -ForegroundColor Green

# Step 3: Verify Configuration
Write-Host "`nStep 3: Verifying Network Configuration..." -ForegroundColor Cyan

# Show subnet details
Write-Host "Subnet Configuration:" -ForegroundColor Yellow
az network vnet subnet list `
    --resource-group $ResourceGroup `
    --vnet-name $VNetName `
    --query "[].{Name:name, AddressPrefix:addressPrefix, NSG:networkSecurityGroup.id}" `
    --output table

Write-Host "`n=== Networking Infrastructure Complete ===" -ForegroundColor Green
Write-Host "✅ Private Endpoint Subnet: $privateEndpointSubnetName ($privateEndpointSubnetPrefix)" -ForegroundColor White
Write-Host "✅ Web App Integration Subnet: $webAppSubnetName ($webAppSubnetPrefix)" -ForegroundColor White
Write-Host "✅ Network Security Groups: $privateEndpointNsgName, $webAppNsgName" -ForegroundColor White
Write-Host "✅ SPANBC Access: 142.22.0.0/16 allowed on port 443" -ForegroundColor White

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Run openai-deploy.ps1 to create OpenAI service with private endpoint" -ForegroundColor White
Write-Host "2. The private endpoint will be created in: $privateEndpointSubnetName" -ForegroundColor White
Write-Host "3. Web app will integrate with: $webAppSubnetName" -ForegroundColor White
Write-Host "4. Generate nginx configuration with private endpoint IP" -ForegroundColor White