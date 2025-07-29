#!/bin/sh

# Add private endpoint DNS mapping for Azure OpenAI
echo "10.46.75.68 d837ad-test-recap-llm-east.openai.azure.com" >> /etc/hosts

# Start nginx
nginx -g "daemon off;"