az account show --query "{name:name, id:id, state:state, isDefault:isDefault, user:user}" --output json
# Azure Front Door Standard/Premium deployment script (using az afd)
# This script creates an Azure Front Door profile, endpoint, origin group, origin, and route for a backend (e.g., your Azure OpenAI endpoint or web app).
# Adjust variables as needed before running. No prompting will occur.

# ====== USER CONFIGURATION ======
$subscriptionId = "5445292b-8313-4272-96aa-f30efd1e1654"
$resourceGroup = "d837ad-test-networking"
$region = "canadacentral"  # Adjust as needed
$afdProfileName = "recapafd-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$afdEndpointName = "$afdProfileName-endpoint"
$originGroupName = "$afdProfileName-origingroup"
$originName = "$afdProfileName-origin"
$routeName = "$afdProfileName-route"
$backendHost = "d837ad-test-recap-llm-east.openai.azure.com"  # Change to your backend host
# =================================

# Set the subscription if specified
if ($subscriptionId -and $subscriptionId -notmatch '^<.*>$') {
    az account set --subscription $subscriptionId
}
az account show --query "{name:name, id:id, state:state, isDefault:isDefault, user:user}" --output json

# Ensure the Azure Front Door extension is installed
Write-Host "Ensuring Azure Front Door extension is installed..." -ForegroundColor Yellow
az extension add --name front-door

# Create AFD profile
Write-Host "Creating Azure Front Door Standard/Premium profile $afdProfileName..." -ForegroundColor Yellow
az afd profile create --resource-group $resourceGroup --profile-name $afdProfileName --sku Standard_AzureFrontDoor
if ($?) {
    Write-Host "AFD profile $afdProfileName created successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to create AFD profile. Exiting script." -ForegroundColor Red
    exit 1
}

# Create AFD endpoint
Write-Host "Creating AFD endpoint $afdEndpointName..." -ForegroundColor Yellow
az afd endpoint create --resource-group $resourceGroup --profile-name $afdProfileName --endpoint-name $afdEndpointName
if ($?) {
    Write-Host "AFD endpoint $afdEndpointName created successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to create AFD endpoint. Exiting script." -ForegroundColor Red
    exit 1
}

# Create origin group
Write-Host "Creating origin group $originGroupName..." -ForegroundColor Yellow
az afd origin-group create --resource-group $resourceGroup --profile-name $afdProfileName --origin-group-name $originGroupName --probe-request-type GET --probe-protocol Https --probe-path / --probe-interval-in-seconds 60 --sample-size 4 --successful-samples-required 3
if ($?) {
    Write-Host "Origin group $originGroupName created successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to create origin group. Exiting script." -ForegroundColor Red
    exit 1
}

# Add backend/origin
Write-Host "Adding origin $originName ($backendHost)..." -ForegroundColor Yellow
az afd origin create --resource-group $resourceGroup --profile-name $afdProfileName --origin-group-name $originGroupName --origin-name $originName --host-name $backendHost --origin-host-header $backendHost --https-port 443 --priority 1 --weight 1000 --enabled-state Enabled
if ($?) {
    Write-Host "Origin $originName added successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to add origin. Exiting script." -ForegroundColor Red
    exit 1
}

# Create route to forward traffic to the backend
Write-Host "Creating route $routeName..." -ForegroundColor Yellow
az afd route create --resource-group $resourceGroup --profile-name $afdProfileName --endpoint-name $afdEndpointName --route-name $routeName --origin-group $originGroupName --https-redirect Enabled --supported-protocols Http Https --patterns-to-match '/*' --forwarding-protocol MatchRequest --link-to-default-domain Enabled
if ($?) {
    Write-Host "Route $routeName created successfully." -ForegroundColor Green
} else {
    Write-Host "Failed to create route. Exiting script." -ForegroundColor Red
    exit 1
}

# Output the actual AFD endpoint
$afdHostName = az afd endpoint show --resource-group $resourceGroup --profile-name $afdProfileName --endpoint-name $afdEndpointName --query hostName -o tsv
if ($afdHostName) {
    $afdUrl = "https://$afdHostName"
    Write-Host "Azure Front Door deployed and available at: $afdUrl" -ForegroundColor Cyan
} else {
    Write-Host "Azure Front Door deployed, but could not determine endpoint hostname." -ForegroundColor Yellow
}
