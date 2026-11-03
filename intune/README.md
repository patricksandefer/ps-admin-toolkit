# intune/

| File | Use |
|---|---|
| `Install-ArcticWolfAgent.ps1` | Put beside the Arctic Wolf portal bundle (company-named MSI + `customer.json`), package with `IntuneWinAppUtil.exe -c <folder> -s Install-ArcticWolfAgent.ps1 -o <out>`. Install cmd: `powershell.exe -ExecutionPolicy Bypass -NoProfile -File Install-ArcticWolfAgent.ps1`. Detection: service `ArcticWolfAgentMgr` exists. Same script runs from N-central as Local System. The bundle never goes in git. |
| `Detect-SmartAppControl.ps1` / `Remediate-SmartAppControl.ps1` | Intune → Devices → Scripts and remediations → Remediations: run as System, 64-bit, daily. Or run the remediation from N-central as Local System until E3 licensing lands. |
