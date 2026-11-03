# ps-admin-toolkit

Vendor-neutral PowerShell and configuration for Microsoft 365, Entra, Intune, Azure and AWS administration.
Public and generic by design: no tenant IDs, no company or customer names, no IP addresses, no credentials.

## Folders

| Folder | Contents |
|---|---|
| `profiles/` | PowerShell profiles (daily driver, admin/PAW) and the shared `common.ps1` prompt helpers |
| `inventory/` | Tenant inventory (`Inventory.ps1`) and the M&A source-endpoint sweep |
| `security/` | PIM assignments, Conditional Access export/import, travel-exception group scripts, kit signing |
| `intune/` | Arctic Wolf agent installer, Smart App Control detect/remediate |
| `azure/` | Bicep for management groups, policy, monitoring (added as Checklist I is built) |
| `freshservice/` | Catalog-item and workflow templates (added as Checklist J is built) |
| `mail/` | `New-InboxRules.ps1` — IT inbox folder tree and triage rules |
| `runbooks/` | Operational runbooks (Zscaler down, PAW, office decommission, application-control publishers) |
| `settings/` | `settings.local.ps1.example` only; real values are never committed |

## Rules

1. Every real value is a parameter or a `<PLACEHOLDER>`; real values live in an untracked `settings.local.ps1` (copy the `.example`).
2. A pre-commit hook (gitleaks) blocks GUIDs and identifying names. After cloning, run once:
   `git config core.hooksPath .githooks`
3. Nothing here is the copy that runs in production; that copy lives in the company repo.

## First use on a managed laptop

```powershell
$raw = 'https://raw.githubusercontent.com/<github-user>/ps-admin-toolkit/main'
Invoke-WebRequest "$raw/<folder>/<file>" -OutFile C:\Admin\Toolkit\<folder>\<file> -UseBasicParsing
Unblock-File C:\Admin\Toolkit\<folder>\<file>
```

Scripts that need real values dot-source `settings\settings.local.ps1` from `C:\Admin\Toolkit\settings\` (see `profiles\common.ps1`, `Import-ToolkitSettings`).
