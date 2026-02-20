# Provision Azure resources for Naval Arcade
# Prerequisites: Azure CLI installed and logged in (az login)
# Usage: .\infra\provision.ps1 -ResourceGroup "rg-navalarcade" -Location "eastus"

param(
    [string]$ResourceGroup = "rg-navalarcade",
    [string]$Location = "eastus",
    [string]$BaseName = "navalarcade",
    [string]$GitHubRepo = "seajhawk/JoesArcade",
    [string]$Branch = "master"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Creating resource group '$ResourceGroup' in '$Location'..." -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --output none

Write-Host "==> Deploying Bicep template..." -ForegroundColor Cyan
$deploy = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$PSScriptRoot\main.bicep" `
    --parameters baseName=$BaseName repoUrl="https://github.com/$GitHubRepo" branch=$Branch `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$swaUrl      = $deploy.staticWebAppUrl.value
$apiToken    = $deploy.staticWebAppApiToken.value
$storageName = $deploy.storageAccountName.value

Write-Host ""
Write-Host "==> Deployment complete!" -ForegroundColor Green
Write-Host "    Static Web App URL : $swaUrl"
Write-Host "    Storage Account    : $storageName"
Write-Host ""
Write-Host "==> Adding AZURE_STATIC_WEB_APPS_API_TOKEN to GitHub repo secrets..." -ForegroundColor Cyan
Write-Host "    (requires 'gh' CLI logged in — run 'gh auth login' first if needed)"

gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN `
    --repo $GitHubRepo `
    --body $apiToken

Write-Host ""
Write-Host "==> All done. Push to '$Branch' to trigger your first deployment." -ForegroundColor Green
