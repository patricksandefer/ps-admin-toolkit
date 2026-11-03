# Application-control publisher strings

Collected with `Get-AppLockerFileInformation -Path <installer> | Select-Object -ExpandProperty Publisher`.
Rules are **publisher-only** (product `*`, binary `*`, version `*` and above) because vendors put the
release number in the product and binary names, so pinning either breaks on the next update.

| Vendor | Publisher | Rule scope |
|---|---|---|
| Arctic Wolf Agent | `O=ARCTIC WOLF NETWORKS, INC., L=EDEN PRAIRIE, S=MINNESOTA, C=US` | Msi + Exe (+ Script if the agent drops scripts) |
| Zscaler Client Connector | *(collect from the ZCC installer)* | Msi/Exe |
| N-able agent | *(collect from the N-able installer)* | Exe |
| Keeper | *(collect from the Keeper installer)* | Exe |
| Microsoft 365 Apps, Edge, PowerShell 7 | Microsoft Corporation (default Microsoft rules) | — |

State found on the standard laptop image: no AppLocker policy; kernel code integrity enforced (normal);
Smart App Control in evaluation (`VerifiedAndReputablePolicyState = 2`). Decision: SAC Off on managed
devices (see `intune/Remediate-SmartAppControl.ps1`), WDAC in audit mode later with the rules above.
