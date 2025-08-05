param(
    [string]$ApiKey,
    [ValidateSet("test", "prod", "dev")]
    [string]$Environment = "prod",
    [ValidateSet("gpt-4o", "gpt-4o-mini", "both")]
    [string]$Model = "both",
    [string]$Question = "Hello"
)

$headers = @{ 
    "api-key" = $ApiKey
    "Content-Type" = "application/json"
}

# Function to test a specific model
function Test-Model {
    param(
        [string]$ModelName,
        [string]$Environment,
        [hashtable]$Headers,
        [string]$Question
    )
    
    Write-Host "`n=== Testing '$ModelName' model ===" -ForegroundColor Cyan
    
    # Create request body with model-specific parameters
    $chatBody = @{
        messages = @(@{
            role = "user"
            content = $Question
        })
        max_tokens = 50
    } | ConvertTo-Json

    try {
        $webAppUrl = "https://d837ad-$Environment-recap-webapp.azurewebsites.net"
        # Standard API version for all models
        $apiVersion = "2024-02-15-preview"
        $apiUrl = "$webAppUrl/openai/deployments/$ModelName/chat/completions?api-version=$apiVersion"
        
        Write-Host "Making request to: $apiUrl" -ForegroundColor Yellow
        
        $response = Invoke-WebRequest -Uri $apiUrl -Method POST -Headers $Headers -Body $chatBody -UseBasicParsing
        
        Write-Host "✅ SUCCESS!" -ForegroundColor Green
        $json = $response.Content | ConvertFrom-Json
        
        $responseContent = $json.choices[0].message.content
        if ([string]::IsNullOrWhiteSpace($responseContent)) {
            Write-Host "Response: [EMPTY OR NULL RESPONSE]" -ForegroundColor Red
            Write-Host "Full response object:" -ForegroundColor Yellow
            Write-Host ($json | ConvertTo-Json -Depth 3) -ForegroundColor Gray
        } else {
            Write-Host "Response: $responseContent" -ForegroundColor White
        }
        
        Write-Host "Tokens used: $($json.usage.total_tokens)" -ForegroundColor Yellow
        Write-Host "- Input: $($json.usage.prompt_tokens)" -ForegroundColor Gray
        Write-Host "- Output: $($json.usage.completion_tokens)" -ForegroundColor Gray
        
        return $true
        
    } catch {
        Write-Host "❌ FAILED: $($_)" -ForegroundColor Red
        return $false
    }
}

Write-Host "Testing AI models in $Environment environment through RECAP proxy..." -ForegroundColor Cyan

$successCount = 0
$totalTests = 0

if ($Model -eq "both") {
    $modelsToTest = @("gpt-4o", "gpt-4o-mini")
} else {
    $modelsToTest = @($Model)
}

foreach ($modelName in $modelsToTest) {
    $totalTests++
    $success = Test-Model -ModelName $modelName -Environment $Environment -Headers $headers -Question $Question
    if ($success) {
        $successCount++
    }
}

Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Total models tested: $totalTests" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $($totalTests - $successCount)" -ForegroundColor Red
Write-Host "Success rate: $([math]::Round(($successCount / $totalTests) * 100, 1))%" -ForegroundColor Yellow

if ($successCount -eq $totalTests) {
    Write-Host "`n🎉 All models working correctly!" -ForegroundColor Green
} else {
    Write-Host "`n⚠️ Some models failed - check deployment status" -ForegroundColor Yellow
}