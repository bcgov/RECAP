#!/bin/sh

# Add private endpoint DNS mapping for Azure OpenAI
echo "10.46.75.69 d837ad-test-econ-llm-east.openai.azure.com" >> /etc/hosts

# Start nginx
nginx -g "daemon off;"