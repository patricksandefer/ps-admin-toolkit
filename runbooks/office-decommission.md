# Runbook: office decommission (per acquisition, lease run-off)

Owner: migration engineer. Start at lease-end minus the longest notice period among circuits and phones.

| Step | When | Done |
|---|---|---|
| Inventory on-site servers, network gear, printers, badge controllers, phones, fax; record serials and what each still does | Lease end −90 days | ☐ |
| Confirm server workloads cut over to AWS (MGN test cutover passed); file shares on FSx; nothing new plugged in since the lease-run-off rules began | −60 | ☐ |
| Give notice on ISP/circuits and phone lines; port numbers to the cloud phone system; move fax to e-fax | −60 (per contract notice) | ☐ |
| Retrieve or wipe servers (certificate of destruction for disks), wipe and reimage devices left behind, collect laptops for Autopilot reset | −30 | ☐ |
| Scan and retain paper records per compliance; agree scanning vendor and retention before anything leaves the building | −30 | ☐ |
| Forward or cancel the physical mailing address; update registrar/vendor contact addresses | −14 | ☐ |
| Remove ZPA app connectors and any site-specific named locations/CA exceptions; remove the site from monitoring | −7 | ☐ |
| Remove the acquired company's domains from scanning configs (`.gitleaks.toml`) only when the domain is removed from the tenant and no longer referenced | after domain removal | ☐ |
| Lease-end walkthrough with facilities; keys and badges returned; photos of the empty space | 0 | ☐ |
