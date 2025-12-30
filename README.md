# Microsoft 365 & Entra Scripts

Automation scripts for Microsoft 365 services and Entra ID (Azure AD). This repository contains operational tooling for Exchange Online, SharePoint/OneDrive, Teams, Intune, Security & Compliance, Licensing, and Graph API utilities.

Primary languages: **PowerShell**

---

## 📊 Status & Info

![Last Commit](https://img.shields.io/github/last-commit/BlindTrevor/365-Scripts)
![Issues](https://img.shields.io/github/issues/BlindTrevor/365-Scripts)
![Repo Size](https://img.shields.io/github/repo-size/BlindTrevor/365-Scripts)

---

## 🚀 Overview
This repo centralizes repeatable tasks, bulk operations, reporting, and admin automation across the Microsoft 365 tenant.

---

## 🔐 Security & Secrets

- **Never** commit secrets, tokens, or export tenant data that may be sensitive.
- Use a **secrets manager** (e.g., 1Password, Azure Key Vault, or environment variables).
- Scripts should read secrets via environment variables or injected at runtime.
- If logs may contain PII, write to a secure path and restrict permissions.

---

## 🧭 Conventions

- **Script naming**: `Verb-Noun-Service.ps1` (e.g., `Get-LicensingReport-Graph.ps1`)
- **Idempotency**: scripts should support re-runs without unintended changes.

---

## 🔑 Authentication Patterns

### Interactive (admin operator)
```powershell
# Exchange Online
Connect-ExchangeOnline -ShowProgress $false

# Microsoft Graph (SDK)
Connect-MgGraph -Scopes "User.Read.All","Group.Read.All" -TenantId <tenant-id>
Select-MgProfile -Name beta  # if needed for preview endpoints
```

### Unattended (service principal + certificate)
```powershell
$TenantId = "<tenant-id>"
$ClientId = "<app-id>"
$CertThumb = "<thumbprint>"
Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertThumb -NoWelcome
```

### Device code (fallback)
```powershell
Connect-MgGraph -Scopes "User.Read.All" -TenantId <tenant-id> -UseDeviceCode
``
---

## ⚠️ Disclaimer

These scripts are provided as-is. Review, test in a **non-production** tenant or sandbox first, and run under the principle of least privilege. Some endpoints may require elevated roles (e.g., `Compliance Administrator`).

