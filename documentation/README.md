# RECAP Documentation Index

Welcome to the RECAP (Responsible Evaluation And Consolidated Analytics Platform) documentation.

## 📖 Available Documentation

### Core Architecture
- **[Azure Landing Zone Documentation](./RECAP-Azure-LandingZone.md)** - Comprehensive Azure infrastructure architecture, cost analysis ($0.83/day), and deployment details with interactive Mermaid diagrams
- **[Architecture Diagram](./RECAP-Architecture-Diagram.md)** - System architecture overview and component relationships
- **[VNet Solution](./RECAP-VNet-Solution.md)** - Virtual network configuration and security implementation

### Technical Solutions  
- **[Connection Pooling Solution](./RECAP-Connection-Pooling-Solution.md)** - Optimized connection management for Azure OpenAI services
- **[Multi-Client Solution](./RECAP-multi-client-solution.md)** - Multi-tenant architecture and client isolation strategies

### Deployment & Operations
- **[GitOps Deployment Flow](./RECAP-GitOps-deployment-Flow.md)** - CI/CD pipeline and automated deployment processes

## 🚀 Quick Start

For immediate deployment, refer to the main [README.md](../README.md) which contains:
- Repository structure overview
- Quick deployment commands
- Prerequisites and troubleshooting

## 📊 Cost Overview

The RECAP test environment operates at **CA$0.83 per day** with comprehensive security:
- **Azure App Service**: CA$0.02/day (B1 Linux)
- **Container Registry**: CA$0.16/day  
- **Private Endpoints**: CA$0.24/day
- **Microsoft Defender**: CA$0.41/day
- **GPT-4o-mini**: 94% cheaper than GPT-4o for most use cases

## 🏗️ Architecture Highlights

- **Private Network Access**: All AI services behind private endpoints
- **Multi-Environment**: Separate test/prod with VNet isolation  
- **Container-Based**: Docker + Azure Container Registry
- **Cost-Optimized**: GPT-4o-mini for 94% cost savings
- **BC Gov Compliant**: SPANBC network access, security monitoring

---

**Last Updated**: August 6, 2025  
**Status**: Active Development
