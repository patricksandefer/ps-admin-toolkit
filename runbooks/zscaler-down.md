# Runbook: Zscaler is down (admin access emergency path)

Applies once admin portals are restricted to Zscaler egress (CA-ADM-05).

1. Confirm it is Zscaler: https://trust.zscaler.com (status) — and check whether a colleague on a different network is also affected.
2. If it is a Zscaler outage: on your laptop, disable Zscaler Client Connector with the uninstall/disable password (held in the password manager, `IT – Break-glass (sealed)`).
3. Sign in from the documented static home IP (named location `Admin home static IPs`), **or** add yourself to `sg-admin-zscaler-bypass` for 4 hours using `security\Add-GroupMemberWithExpiry.ps1 -GroupName sg-admin-zscaler-bypass` from the break-glass account.
4. Open a P1 ticket in the service desk with the time, who, and what was changed.
5. When Zscaler is back: re-enable ZCC, confirm sign-in works through Zscaler.
6. Confirm `sg-admin-zscaler-bypass` is empty (the hourly `Remove-ExpiredGroupMembers.ps1` run clears it; verify anyway).
7. Record the event and timing in the decision log. Test this runbook once a quarter.
