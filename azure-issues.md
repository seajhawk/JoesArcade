# Azure Plugin / Skills / MCP — Issues & Improvement Suggestions

**Project:** Naval Arcade — Azure Static Web Apps deployment  
**Date:** 2026-02-21  
**Reporter:** Chris Harris (chris@harriskids.com)  
**Environment:** Windows 11, VS Code Insiders, GitHub Copilot CLI (agent mode)  
**azd version:** 1.23.5  

---

## Issue 1 — Skills not invoked automatically for Azure deployment requests

**Category:** Agent behavior / skill routing  
**Severity:** High

### What happened
When asked to "set up a CI/CD pipeline to deploy to Azure Static Web Apps," the agent bypassed `azure-prepare`, `azure-validate`, and `azure-deploy` entirely. It generated Bicep files, a GitHub Actions workflow, and a custom `provision.ps1` from its own training knowledge. The resulting Bicep was non-AZD-compatible (wrong `targetScope`, no `azd-service-name` tags, hardcoded names). The user had to explicitly ask "did you use any of the azure skills?" before the agent corrected course.

### Impact
- Wasted a full round-trip of code generation that had to be redone
- Produced Bicep that wouldn't work with `azd up`
- User had to notice and correct the omission manually

### Suggestions
- The skill routing rules should treat "deploy to Azure" / "set up CI/CD for Azure" as a hard trigger for `azure-prepare` — not advisory, but blocking
- Add a check in the agent's planning phase: *"Does this request involve Azure infrastructure or deployment? If yes, invoke `azure-prepare` before writing any code."*
- Consider adding an explicit "did you use the right skills?" self-check step after the agent produces a plan involving Azure

---

## Issue 2 — `mcp_azure_mcp_azd` MCP tool fails silently after fresh `azd` install

**Category:** MCP tooling / dependency detection  
**Severity:** Medium

### What happened
After installing `azd` v1.23.5 via `winget`, calling `mcp_azure_mcp_azd` with `command: validate_azure_yaml` returned:

```
Failed to initialize the 'azd' MCP tool.
This tool may require dependencies that are not installed.
The minimum required version that works with MCP tools is 1.20.0.
```

The installed version (1.23.5) exceeds the minimum requirement. The real cause was that the MCP server had not restarted after the install and therefore could not detect the newly-installed binary.

### Impact
- `azure-validate` skill could not complete `azure.yaml` schema validation
- Agent had no fallback path — the skill has no CLI-based fallback for this step
- Validation was effectively skipped

### Suggestions
- The error message should distinguish between "azd not found" and "MCP server needs restart" — e.g., *"azd was detected but the MCP server may need to be restarted to pick it up."*
- The `azure-validate` skill should have a CLI fallback: if `mcp_azure_mcp_azd` fails, run `azd provision --preview --no-prompt` directly via shell to validate Bicep
- The MCP server should attempt to auto-detect `azd` on PATH at each tool call rather than only at startup

---

## Issue 3 — `azd up` fails non-interactively without pre-set subscription

**Category:** azd CLI / agent workflow  
**Severity:** High

### What happened
Running `azd up --no-prompt` (required for agent/non-interactive contexts) failed with:

```
ERROR: reading subscription id: no default response for prompt 'Select an Azure Subscription to use:'
```

This happened because `AZURE_SUBSCRIPTION_ID` was not yet set in the azd environment. The agent needed to enumerate subscriptions first, but `mcp_azure_mcp_subscription_list` returned empty (see Issue 4). The agent was forced to call the ARM REST API directly using an `azd auth token` to discover subscriptions.

### Impact
- Significant delay discovering subscriptions through a workaround
- Required ARM API knowledge the agent had to apply manually
- The deploy skill's pre-deploy checklist requires subscription confirmation but the MCP tool to get it was broken

### Suggestions
- The `azure-validate` / `azure-deploy` skills should set `AZURE_SUBSCRIPTION_ID` and `AZURE_LOCATION` as a mandatory step before attempting `azd up --no-prompt`
- `mcp_azure_mcp_subscription_list` must be reliable (see Issue 4) — it is a critical dependency for this workflow
- As a fallback, the skill should try `azd auth token | ARM REST call to /subscriptions` when the MCP tool fails

---

## Issue 4 — `mcp_azure_mcp_subscription_list` returns empty due to tenant mismatch

**Category:** MCP tooling / authentication  
**Severity:** High

### What happened
`mcp_azure_mcp_subscription_list` returned `{"subscriptions": []}` — an empty list — despite the user being authenticated with valid subscriptions. The root cause was that the MCP Azure tools were authenticating with a credential from a different tenant (`f8cdef31-a31e-4b4a-93e4-5f571e91255a`, a B2C tenant) than the user's actual subscription tenant (`02f67472-dd13-437c-bf76-3c07959d38c0`, `chrisharriskids.onmicrosoft.com`).

`mcp_azure_mcp_group_list` produced a 401 error explicitly calling out the mismatch:
```
The access token is from the wrong issuer 'https://sts.windows.net/f8cdef31.../'.
It must match the tenant 'https://sts.windows.net/02f67472.../'
```

The agent had to:
1. Get an `azd auth token` scoped to `https://management.azure.com/.default`
2. Decode the JWT to find the tenant ID
3. Call `https://management.azure.com/tenants` to enumerate tenants
4. Retry with the correct tenant to list subscriptions

### Impact
- The core subscription discovery flow completely failed
- ~30+ minutes of lost time working around the issue
- Required the agent to perform multi-step JWT/REST workarounds

### Suggestions
- When `subscription_list` returns empty, the MCP server should proactively check whether a tenant mismatch is the cause and surface a diagnostic message: *"No subscriptions found. This may be due to a tenant mismatch. Currently authenticated to tenant X. Try `azd auth login --tenant-id <correct-tenant>`."*
- The MCP Azure tools should honor `AZURE_TENANT_ID` from the azd environment (`.azure/<env>/.env`) to align with the active azd context
- Consider adding `mcp_azure_mcp_tenant_list` as a discovery tool the agent can use when `subscription_list` is empty
- The pre-deploy checklist in `azure-deploy` should include a step to verify the MCP auth tenant matches the subscription tenant

---

## Issue 5 — Multi-tenant accounts cause `azd up` to fail on subscription enumeration

**Category:** azd CLI  
**Severity:** Medium

### What happened
The user had 3 tenants. When `azd up` attempted to list subscriptions across all tenants, two of them required MFA and caused the entire command to fail:

```
ERROR: listing accounts: listing subscriptions: 
  Default Directory requires MFA. Login with: azd auth login --tenant-id chrisharriskids.onmicrosoft.com
  TryCosmosDBforPG requires MFA. Login with: azd auth login --tenant-id trycosmosdbforpg.onmicrosoft.com
  AzurePython B2C requires MFA. Login with: azd auth login --tenant-id azurepythonb2c.onmicrosoft.com
```

Setting `AZURE_TENANT_ID` in the azd environment resolved this by scoping azd to a single tenant.

### Impact
- Confusing error for users with multiple tenants (common in enterprise/dev setups)
- Required the agent to know to set `AZURE_TENANT_ID` as a fix

### Suggestions
- `azure-validate` / `azure-deploy` skills should always set `AZURE_TENANT_ID` alongside `AZURE_SUBSCRIPTION_ID` as part of environment setup
- `azd up` should gracefully skip tenants that require additional auth rather than failing hard — or at minimum make it clearer that setting `AZURE_TENANT_ID` is the fix
- The skill's environment setup guide (`environment.md`) should include `AZURE_TENANT_ID` as a required variable alongside subscription and location

---

## Issue 6 — `azd auth login` hangs silently in agent terminal with no output

**Category:** azd CLI / agent UX  
**Severity:** High

### What happened
`azd auth login` was run in an async shell. It opened a browser window for sign-in but produced **zero output** — no URL, no device code, no status — while waiting. The agent polled for over 25 minutes with no way to surface progress to the user or fall back to a device code flow.

### Impact
- Extremely poor UX: user had no idea what was happening
- Agent appeared completely stuck
- No way for the agent to detect or recover from a stalled auth flow

### Suggestions
- `azd auth login` should always print a device code URL (e.g. `https://microsoft.com/devicelogin — code: XXXXXXXX`) as a fallback for non-interactive/headless terminals, even when browser auth is available
- Add `--use-device-code` as the default when azd detects it's running in a non-TTY/agent context
- The `azure-validate` skill instructions should specify using `azd auth login --use-device-code` in agent/CI contexts to avoid browser-only flows
- The agent should time out and suggest alternatives after N seconds of no output from an auth command

---

## Issue 7 — `azure-validate` skill has no CLI fallback path

**Category:** Skill design  
**Severity:** Medium

### What happened
The `azure-validate` skill's AZD recipe relies on `mcp_azure_mcp_azd` for `azure.yaml` validation. When that tool was unavailable (Issue 2), there was no documented fallback. The skill instructions don't mention running `azd provision --preview` directly as an alternative.

### Suggestions
- Add an explicit fallback block to the skill: *"If `mcp_azure_mcp_azd` is unavailable, run `azd provision --preview --no-prompt` via shell to validate Bicep compilation and parameter resolution."*
- The skill should be resilient — MCP tools should be preferred but CLI fallbacks should always exist for every validation step

---

## Summary Table

| # | Issue | Component | Severity | Suggested Fix |
|---|-------|-----------|----------|---------------|
| 1 | Skills not invoked automatically | Agent routing | 🔴 High | Hard-trigger `azure-prepare` for any Azure deploy request |
| 2 | `mcp_azure_mcp_azd` fails after fresh install | MCP server | 🟡 Medium | Better error message + CLI fallback in skill |
| 3 | `azd up --no-prompt` fails without subscription | azd / skill | 🔴 High | Always set `AZURE_SUBSCRIPTION_ID` before `azd up` |
| 4 | `subscription_list` returns empty (tenant mismatch) | MCP auth | 🔴 High | Diagnose tenant mismatch; honor `AZURE_TENANT_ID` from env |
| 5 | Multi-tenant MFA causes `azd up` to fail entirely | azd CLI | 🟡 Medium | Set `AZURE_TENANT_ID`; skip non-authed tenants gracefully |
| 6 | `azd auth login` hangs silently, no output | azd CLI / UX | 🔴 High | Always print device code URL; auto-detect non-TTY context |
| 7 | `azure-validate` has no CLI fallback | Skill design | 🟡 Medium | Document `azd provision --preview` as fallback |
