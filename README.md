# \# ps-admin-toolkit

# 

# Vendor-neutral PowerShell and configuration for Microsoft 365, Entra, Intune, Azure and AWS administration.

# Public and generic by design: no tenant IDs, no company or customer names, no IP addresses, no credentials.

# 

# \## Folders

# \- profiles/      PowerShell profiles (daily driver, admin) and shared prompt functions

# \- inventory/     tenant inventory and export scripts

# \- security/      PIM, Conditional Access templates, group-with-expiry scripts

# \- intune/        policy templates (names and settings only)

# \- azure/         Bicep for management groups, policy, monitoring

# \- freshservice/  catalog-item and workflow templates

# \- mail/          inbox rules

# \- runbooks/      operational runbooks (Zscaler down, PAW, office decommission)

# \- settings/      settings.local.ps1.example only; real values are never committed

# 

# \## Rules

# 1\. Every real value is a parameter or a <PLACEHOLDER>; real values live in an untracked settings.local.ps1.

# 2\. A pre-commit hook (gitleaks) blocks GUIDs and identifying names. Run `git config core.hooksPath .githooks` once after cloning.

# 3\. Nothing here is the copy that runs in production; that copy lives in the company repo.

