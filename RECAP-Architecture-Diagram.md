# RECAP LLM Responsible Evaluation And Consolidated Analytics Platform - Architecture

## System Overview

**BC Gov Azure Landing Zone**
- **VNet**: d837ad-test-vwan-spoke
  - **webapp-integration-subnet** (10.46.75.128/26)
    - **Azure Web App**: d837ad-test-recap-webapp
    - **Nginx Proxy Container**: Authentication, Header mapping, Token tracking
  - **private-endpoint-subnet** (10.46.75.64/26)
    - **Private Endpoint**: d837ad-test-recap-llm-east-pe (IP: 10.46.75.68)

**Azure OpenAI Service** (d837ad-test-recap-llm-east)
- **API Management**: Private Endpoint Support, DNS Management, Rate Limiting
- **GPT-4o Model**: Chat Completions, Token Usage, Performance Metrics
- **Responsible AI**: Content Filtering, Abuse Detection, Usage Analytics

**Data Flow:**
👤 External Users → 🌐 Azure Web App → 🔗 Private Endpoint → ⚙️ API Management → 🤖 GPT-4o → 🛡️ Responsible AI

```mermaid
graph TB
    subgraph "BC Gov Azure Landing Zone"
        subgraph "d837ad-test-vwan-spoke VNet"
            subgraph "webapp-integration-subnet (10.46.75.128/26)"
                WebApp["🌐 Azure Web App<br/>d837ad-test-recap-webapp<br/><br/>📦 Nginx Proxy Container<br/>• Authentication<br/>• Header mapping<br/>• Token tracking"]
            end
            
            subgraph "private-endpoint-subnet (10.46.75.64/26)"
                PE["🔗 Private Endpoint<br/>d837ad-test-recap-llm-east-pe<br/>IP: 10.46.75.68<br/><br/>DNS Resolution &<br/>Private Connectivity"]
            end
        end
    end
    
    subgraph "Azure OpenAI Service"
        subgraph "d837ad-test-recap-llm-east"
            APIM["⚙️ API Management<br/>• Private Endpoint Support<br/>• DNS Management<br/>• Rate Limiting"]
            GPT["🤖 GPT-4o Model<br/>• Chat Completions<br/>• Token Usage<br/>• Performance Metrics"]
            RAI["🛡️ Responsible AI<br/>• Content Filtering<br/>• Abuse Detection<br/>• Usage Analytics"]
        end
    end
    
    Users["👤 External Users"] -->|HTTPS| WebApp
    WebApp -->|VNet Integration| PE
    PE -->|Private Link| APIM
    APIM --> GPT
    GPT --> RAI
    
    classDef userStyle fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef webStyle fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    classDef networkStyle fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef aiStyle fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    
    class Users userStyle
    class WebApp webStyle
    class PE networkStyle
    class APIM,GPT,RAI aiStyle
```

## Data Flow Sequence

**Request Processing Steps:**
1. **User** → POST /openai/deployments/gpt-4o/chat/completions (Authorization: Bearer api-key)
2. **Web App (Nginx Proxy)** → Map Authorization → api-key header
3. **Web App** → Route through VNet integration to Private Endpoint
4. **Private Endpoint** → DNS resolution & private connectivity to API Management
5. **API Management** → Forward to GPT-4o deployment
6. **GPT-4o Model** → Content filtering & monitoring by Responsible AI
7. **Responsible AI** → Return approved response to GPT-4o
8. **GPT-4o Model** → Response with token metrics to API Management
9. **API Management** → Return response with headers to Private Endpoint
10. **Private Endpoint** → Forward response to Web App
11. **Web App** → Response with usage data to User (rate-limit headers exposed)

**Security Notes:**
- Secure private network communication throughout
- Public access disabled, private endpoint only
- All traffic remains within BC Gov Azure Landing Zone

```mermaid
sequenceDiagram
    participant U as 👤 User
    participant W as 🌐 Web App<br/>(Nginx Proxy)
    participant P as 🔗 Private Endpoint<br/>(10.46.75.68)
    participant A as ⚙️ API Management
    participant G as 🤖 GPT-4o Model
    participant R as 🛡️ Responsible AI
    
    U->>W: 1. POST /openai/deployments/gpt-4o/chat/completions<br/>Authorization: Bearer api-key
    W->>W: 2. Map Authorization → api-key header
    W->>P: 3. Route through VNet integration
    P->>A: 4. DNS resolution & private connectivity
    A->>G: 5. Forward to GPT-4o deployment
    G->>R: 6. Content filtering & monitoring
    R->>G: 7. Approved response
    G->>A: 8. Response with token metrics
    A->>P: 9. Return response with headers
    P->>W: 10. Forward response
    W->>U: 11. Response with usage data<br/>(rate-limit headers exposed)
    
    Note over U,R: Secure private network communication
    Note over A,R: Public access disabled, private endpoint only
```

## Network Architecture

**Network Topology:**
- **Internet** → **BC Gov Azure Landing Zone** → **Azure OpenAI Platform**

**BC Gov Azure Landing Zone:**
- **VNet**: d837ad-test-vwan-spoke
  - **webapp-integration subnet** (10.46.75.128/26): Web App with Nginx Container
  - **private-endpoint subnet** (10.46.75.64/26): Private Endpoint (10.46.75.68)

**Azure OpenAI Platform:**
- **Service**: d837ad-test-recap-llm-east
- **Public Access**: DISABLED
- **Private Access**: ENABLED via Private Link

**Connection Flow:**
👤 Users --HTTPS--> 🌐 Web App --VNet Integration--> 🔗 Private Endpoint --Private Link--> 🤖 Azure OpenAI Service

```mermaid
graph LR
    subgraph "Internet"
        Users["👤 Users"]
    end
    
    subgraph "BC Gov Azure Landing Zone"
        subgraph "VNet: d837ad-test-vwan-spoke"
            subgraph "Subnet: webapp-integration<br/>10.46.75.128/26"
                WebApp["🌐 Web App<br/>Nginx Container"]
            end
            
            subgraph "Subnet: private-endpoint<br/>10.46.75.64/26" 
                PE["🔗 Private Endpoint<br/>10.46.75.68"]
            end
        end
    end
    
    subgraph "Azure OpenAI Platform"
        OpenAI["🤖 Azure OpenAI Service<br/>d837ad-test-recap-llm-east<br/><br/>Public Access: DISABLED<br/>Private Access: ENABLED"]
    end
    
    Users -->|HTTPS| WebApp
    WebApp -.->|VNet Integration| PE
    PE -.->|Private Link| OpenAI
    
    classDef internet fill:#bbdefb,stroke:#1976d2,stroke-width:2px
    classDef bcgov fill:#c8e6c9,stroke:#388e3c,stroke-width:2px  
    classDef azure fill:#ffcdd2,stroke:#d32f2f,stroke-width:2px
    
    class Users internet
    class WebApp,PE bcgov
    class OpenAI azure
```

## Architecture Components

### Web Application Tier
- **Azure Web App**: `d837ad-test-recap-webapp.azurewebsites.net`
- **Container**: Nginx proxy with authentication handling
- **VNet Integration**: Connected to `webapp-integration-subnet`

### Network Tier  
- **Virtual Network**: `d837ad-test-vwan-spoke` 
- **Subnets**: 
  - `webapp-integration-subnet` (10.46.75.128/26)
  - `private-endpoint-subnet` (10.46.75.64/26)
- **Private Endpoint**: `d837ad-test-recap-llm-east-pe` (10.46.75.68)

### AI Service Tier
- **Azure OpenAI**: `d837ad-test-recap-llm-east`
- **API Management**: Full private endpoint support with DNS management
- **Model**: GPT-4o deployment with rate limiting and usage analytics
- **Security**: Public access disabled, private endpoint connectivity enabled

### Authentication Flow
1. User → `Authorization: <api-key>` header
2. Nginx → Maps to `api-key: <api-key>` header  
3. Private endpoint → Routes to Azure OpenAI
4. DNS resolution and secure connectivity established

### Deployment Architecture
- Secure private endpoint connectivity
- Comprehensive API management and monitoring
- Scalable container-based web application tier