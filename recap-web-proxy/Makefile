# RECAP Web Proxy Makefile
# Following BC Gov EPIC.search patterns

.PHONY: help setup build run deploy clean test

help: ## Show this help message
	@echo "RECAP Web Proxy - BC Gov Deployment"
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Copy sample environment file
	@if [ ! -f .env ]; then \
		cp sample.env .env; \
		echo "Created .env file from sample.env. Please customize it."; \
	else \
		echo ".env file already exists"; \
	fi

build: ## Build Docker image
	docker build -t recap-web-proxy:latest .

run: ## Run locally with Docker Compose
	docker-compose up -d

stop: ## Stop Docker Compose services
	docker-compose down

deploy: setup ## Deploy to Azure (requires .env configuration)
	@powershell -ExecutionPolicy Bypass -File deploy-bcgov.ps1

deploy-test: setup ## Deploy to test environment
	@powershell -ExecutionPolicy Bypass -File deploy-bcgov.ps1 -Environment test

deploy-prod: setup ## Deploy to production environment
	@powershell -ExecutionPolicy Bypass -File deploy-bcgov.ps1 -Environment prod

clean: ## Clean up Docker resources
	docker-compose down -v
	docker rmi recap-web-proxy:latest || true

test: ## Test the deployment
	@echo "Testing RECAP Web Proxy..."
	@curl -f http://localhost || echo "Local service not running"

logs: ## Show Docker Compose logs
	docker-compose logs -f

status: ## Show service status
	docker-compose ps