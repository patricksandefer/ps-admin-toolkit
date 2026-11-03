# Runbook: Privileged Access Workstation (Windows 365 Cloud PC)

**What it is for:** admin portals and PowerShell against the tenant, Azure, AWS and the security tools, signed in as the admin account only.
**What it is not for:** email, Teams, web research, downloads from anywhere but vendor/Microsoft domains on the allow-list.

- Reach it only from a compliant company laptop via the Windows App; Conditional Access (`CA-PAW-Access`) enforces this.
- Clipboard, drive and USB redirection are off by policy; nothing is pasted out of the PAW.
- Profiles: `profiles\admin.ps1` + `profiles\common.ps1`; every session is transcribed to `C:\Admin\Logs`.
- If the PAW is unreachable: use the admin Edge profile on the laptop as the fallback and log a ticket. If Zscaler is the cause, follow `zscaler-down.md`.
- If anything looks wrong on the PAW: re-provision the Cloud PC from Intune rather than cleaning it.
- Patching: PAWs are in the fastest update ring (0-day quality updates, 2-day deadline).
