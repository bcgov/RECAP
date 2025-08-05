#!/bin/sh

# Add private endpoint DNS mapping for Azure OpenAI (for debugging)
echo "10.46.76.4 d837ad-prod-econ-llm-east.openai.azure.com" >> /etc/hosts

# Start nginx in foreground with optimized settings for private endpoints
exec nginx -g "daemon off;"