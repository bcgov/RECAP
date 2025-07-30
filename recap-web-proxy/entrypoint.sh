#!/bin/sh

# Add private endpoint DNS mapping for Azure OpenAI (for debugging)
echo "10.46.75.69 d837ad-test-econ-llm-east.openai.azure.com" >> /etc/hosts

# Start nginx in foreground with optimized settings for private endpoints
exec nginx -g "daemon off;"