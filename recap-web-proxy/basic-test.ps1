param([string]$ApiKey)

$headers = @{ 
    "api-key" = $ApiKey
    "Content-Type" = "application/json"
}

$chatBody = @{
    messages = @(@{
        role = "user"
        content = "Tell me a new joke about cats."
    })
    max_tokens = 50
} | ConvertTo-Json

Write-Host "Testing 'Question' prompt through RECAP proxy..." -ForegroundColor Cyan

try {
    $response = Invoke-WebRequest -Uri "https://d837ad-test-recap-webapp.azurewebsites.net/openai/deployments/gpt-4o/chat/completions?api-version=2024-02-01" -Method POST -Headers $headers -Body $chatBody -UseBasicParsing
    
    Write-Host "SUCCESS!" -ForegroundColor Green
    $json = $response.Content | ConvertFrom-Json
    
    Write-Host "Response: $($json.choices[0].message.content)" -ForegroundColor White
    Write-Host "Tokens used: $($json.usage.total_tokens)" -ForegroundColor Yellow
    Write-Host "- Input: $($json.usage.prompt_tokens)" -ForegroundColor Gray
    Write-Host "- Output: $($json.usage.completion_tokens)" -ForegroundColor Gray
    
} catch {
    Write-Host "Error: $($_)" -ForegroundColor Red
}