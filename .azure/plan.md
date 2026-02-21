# Azure Deployment Plan — Naval Arcade

> **Status:** Executing

---

## 1. Project Overview

**Goal:** Deploy static HTML arcade site to Azure Static Web Apps with an Azure Functions leaderboard API backed by Azure Table Storage.

**Path:** Modernize Existing (pure static HTML → Azure)

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | Development / Personal |
| Scale | Small |
| Budget | Cost-Optimized (Free tier SWA, LRS Storage) |
| Subscription | Set via `azd env set AZURE_SUBSCRIPTION_ID` |
| Location | Set via `azd env set AZURE_LOCATION` |

---

## 3. Components Detected

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Naval Arcade | Frontend (static) | HTML/CSS/JS | `/` |
| Leaderboard API | API | Node.js Azure Functions | `/api` |

---

## 4. Recipe Selection

**Selected:** AZD (Bicep)

**Rationale:**
- Static site with managed Functions API — SWA is the natural fit
- Bicep is the default, Azure-only, simplest path
- `azd up` provisions everything in one command

---

## 5. Architecture

**Stack:** App Service (Static Web Apps)

### Service Mapping

| Component | Azure Service | SKU |
|-----------|---------------|-----|
| Static site + managed API | Azure Static Web Apps | Free ($0) |
| Leaderboard data | Azure Table Storage | Standard LRS (~$0/mo at this scale) |

### Supporting Services

| Service | Status |
|---------|--------|
| Log Analytics | Not included (cost optimization for personal project) |
| Application Insights | Not included (can add later) |
| Key Vault | Not included — connection string stored in SWA app settings |
| Managed Identity | Not available on SWA Free tier; upgrade to Standard to enable |

---

## 6. Execution Checklist

### Phase 1: Planning ✅
- [x] Analyze workspace
- [x] Select recipe (AZD + Bicep)
- [x] Plan architecture

### Phase 2: Execution ✅
- [x] `azure.yaml` — AZD service configuration
- [x] `package.json` — build script (copies HTML → `public/`)
- [x] `infra/main.bicep` — subscription-scoped entry point
- [x] `infra/modules/resources.bicep` — SWA + Storage + Table
- [x] `infra/main.parameters.json` — AZD parameter file
- [x] `.github/workflows/azure-static-web-apps.yml` — CI/CD
- [x] `api/` — Azure Functions leaderboard (GET/POST /api/scores)
- [x] `staticwebapp.config.json` — routing + security headers

### Phase 3: Validation
- [ ] Run `azd provision --preview` to validate Bicep
- [ ] Invoke azure-validate skill

### Phase 4: Deployment
- [ ] Run `azd up` (first time) or `azd deploy` (subsequent)

---

## 7. Files Generated

| File | Purpose |
|------|---------|
| `azure.yaml` | AZD service configuration |
| `package.json` | Build script to copy static files to `public/` |
| `infra/main.bicep` | Subscription-scoped Bicep entry point |
| `infra/modules/resources.bicep` | SWA + Storage resources |
| `infra/main.parameters.json` | AZD parameter bindings |
| `.github/workflows/azure-static-web-apps.yml` | GitHub Actions CI/CD |
| `api/host.json` | Functions host config |
| `api/package.json` | Functions Node.js project |
| `api/scores/function.json` | HTTP trigger definition |
| `api/scores/index.js` | Leaderboard read/write logic |
| `staticwebapp.config.json` | SWA routing + security headers |

---

## 8. Deploy Instructions

```bash
# First time: provision Azure resources + deploy
azd auth login
azd up

# Subsequent deploys (code only)
azd deploy

# CI/CD: push to master → GitHub Actions auto-deploys via SWA token
```

## 9. Notes

- SWA Free tier does not support Managed Identity on managed functions.
  To use `DefaultAzureCredential` instead of connection strings, upgrade to Standard (~$9/mo) and assign `Storage Table Data Contributor` role to the SWA system identity.
- The `STORAGE_CONNECTION_STRING` is provisioned by Bicep into SWA app settings — it is NOT in source code.
