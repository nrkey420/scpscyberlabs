# Lab Guide: SOC Analyst Training

## Overview

In this lab, you will step into the role of a Security Operations Center (SOC) analyst. A simulated corporate network has been pre-compromised with several attack scenarios running in the background. Your job is to monitor alerts, triage incidents, investigate the attack chain, and document your findings using industry-standard SIEM and log analysis tools.

You will not be attacking anything in this lab. Instead, you will be defending -- detecting what the automated attacker has done and building a complete incident timeline.

**Difficulty:** Intermediate
**Estimated Duration:** 3 hours
**Total Points:** 1,000

### Learning Objectives

By completing this lab, you will be able to:

- Navigate and query a SIEM (Splunk) to find security events
- Triage alerts by severity and determine true vs. false positives
- Investigate incidents by correlating events across multiple log sources
- Analyze network traffic captures using Wireshark and Zeek
- Identify indicators of compromise (IOCs)
- Build an incident timeline from raw log data
- Classify attack techniques using the MITRE ATT&CK framework
- Write an incident report suitable for management review

---

## Network Topology

```
                         ┌─────────────────────────┐
                         │     pfSense Firewall     │
                         │         .1               │
                         └────┬───────────┬─────────┘
                              │           │
               ┌──────────────┘           └──────────────┐
               │                                         │
      ┌────────┴────────┐                       ┌────────┴────────┐
      │   Corporate Net │                       │    DMZ Net      │
      │  10.X.Y.0/24    │                       │  10.X.Y.0/24   │
      └──┬──┬──┬──┬─────┘                       └────────┬────────┘
         │  │  │  │                                      │
         │  │  │  │                             ┌────────┴────────┐
         │  │  │  │                             │  Web Server     │
         │  │  │  │                             │  (Compromised)  │
         │  │  │  │                             │   .30           │
         │  │  │  │                             └─────────────────┘
         │  │  │  │
         │  │  │  └──────────────────────┐
         │  │  │                         │
┌────────┴──┴──┴──────┐     ┌───────────┴──────────┐
│ Windows Workstation  │     │  Domain Controller   │
│  (Compromised)       │     │  Windows Server 2019 │
│   .20                │     │   .21                │
└──────────────────────┘     └──────────────────────┘
         │
┌────────┴────────────────────────────────────────────┐
│                  SOC Analyst Workstation             │
│                                                     │
│  ┌─────────────┐  ┌───────────┐  ┌──────────────┐  │
│  │ Splunk SIEM │  │ Security  │  │ Analyst      │  │
│  │  (Web UI)   │  │ Onion     │  │ Desktop      │  │
│  │   .50       │  │  .51      │  │  .10         │  │
│  └─────────────┘  └───────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## VM Descriptions and Credentials

| VM                      | OS                   | Role            | RAM   | CPU | IP Address |
|-------------------------|----------------------|-----------------|-------|-----|------------|
| Analyst Desktop         | Ubuntu Desktop 22.04 | Your workstation| 4 GB  | 2   | .10        |
| Windows Workstation     | Windows 10 Pro       | Compromised     | 4 GB  | 2   | .20        |
| Domain Controller       | Windows Server 2019  | Compromised     | 4 GB  | 2   | .21        |
| Web Server              | Ubuntu Server 22.04  | Compromised     | 2 GB  | 1   | .30        |
| Splunk SIEM             | Splunk Enterprise    | Log analysis    | 8 GB  | 4   | .50        |
| Security Onion          | Security Onion 2.4   | NSM platform    | 8 GB  | 4   | .51        |
| pfSense Firewall        | pfSense 2.7          | Network         | 1 GB  | 1   | .1         |

> **Credentials:** Displayed in the CyberLab sidebar for each VM. Your primary workspace is the **Analyst Desktop** and the **Splunk** web interface.

---

## Objectives Walkthrough

### Objective 1: SIEM Orientation and Alert Triage (100 points)

**Goal:** Log into Splunk, review the alert queue, and triage at least 5 alerts as true positive or false positive.

**Flag:** `FLAG{soc_triage_complete_5_alerts_a7b2}`

#### Step-by-Step

1. Connect to the **Analyst Desktop** VM and open Firefox.

2. Navigate to the Splunk web interface:

```
http://10.X.Y.50:8000
```

3. Log in with the credentials shown in the CyberLab sidebar.

4. Navigate to **Search & Reporting** > **Alerts**. You will see a queue of triggered alerts.

5. For each alert, perform basic triage:
   - Read the alert description
   - Click into the triggering events
   - Determine if it is a **True Positive** (real attack) or **False Positive** (benign activity)

6. Document your triage decisions in a table:

| Alert Name                    | Severity | Source IP    | Verdict       | Reasoning                          |
|-------------------------------|----------|-------------|---------------|-------------------------------------|
| Suspicious PowerShell Exec    | High     | 10.X.Y.20   | True Positive | Encoded command, unusual parent proc|
| Failed Login (3 attempts)     | Medium   | 10.X.Y.15   | False Positive| Known admin during maintenance      |

7. After triaging at least 5 alerts, run the validation:

```bash
/opt/validation/check_triage.sh
```

8. Submit the flag.

---

### Objective 2: Investigate Phishing-Based Initial Access (150 points)

**Goal:** Determine how the attacker gained initial access to the Windows workstation.

**Flag:** `FLAG{phishing_initial_access_identified_c3d9}`

#### Step-by-Step

1. In Splunk, search for events on the Windows workstation around the time of the first alert:

```spl
index=windows host="WORKSTATION" sourcetype="WinEventLog:Security"
| sort _time
| head 200
```

2. Look for process creation events (Event ID 4688 or Sysmon Event ID 1):

```spl
index=windows host="WORKSTATION" sourcetype="WinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=1
| table _time, ParentImage, Image, CommandLine, User
| sort _time
```

3. Identify the initial execution chain. Look for:
   - `OUTLOOK.EXE` or `WINWORD.EXE` spawning `cmd.exe` or `powershell.exe`
   - Macro execution indicators
   - Downloaded executables from user directories

4. Search for email-related events:

```spl
index=email OR index=exchange
| search subject="*" attachment="*"
| table _time, sender, recipient, subject, attachment_name
```

5. Trace the execution from the phishing email to the initial payload:
   - What application opened the malicious file?
   - What child processes were spawned?
   - What network connections were made?

6. Document the initial access vector. The flag is revealed after validation:

```bash
/opt/validation/check_initial_access.sh
```

---

### Objective 3: Detect Command and Control (C2) Communication (100 points)

**Goal:** Identify the C2 channel the attacker is using to communicate with the compromised workstation.

**Flag:** `FLAG{c2_beacon_detected_dns_tunnel_8f2e}`

#### Step-by-Step

1. In Security Onion, access the Kibana dashboard:

```
http://10.X.Y.51
```

2. Search Zeek DNS logs for unusual DNS queries from the workstation:

```
source.ip: 10.X.Y.20 AND event.dataset: zeek.dns
```

3. Look for indicators of DNS tunneling:
   - Very long subdomain names (data encoded in DNS queries)
   - High volume of DNS requests to a single domain
   - TXT record queries to uncommon domains
   - Regular interval beaconing patterns

4. In Splunk, query for network flow data:

```spl
index=network sourcetype=zeek_conn src_ip="10.X.Y.20"
| stats count by dest_ip, dest_port
| sort -count
```

5. Look for beaconing behavior (regular interval connections):

```spl
index=network sourcetype=zeek_conn src_ip="10.X.Y.20" dest_port=443
| sort _time
| streamstats current=f last(_time) as prev_time by dest_ip
| eval interval=_time-prev_time
| stats avg(interval) as avg_interval, stdev(interval) as stdev_interval by dest_ip
| where stdev_interval < 5
```

A low standard deviation in connection intervals indicates automated beaconing.

6. Document the C2 infrastructure: domain name, IP address, protocol, beacon interval.

7. Validate and submit the flag.

---

### Objective 4: Track Lateral Movement (150 points)

**Goal:** Identify how the attacker moved from the compromised workstation to the domain controller.

**Flag:** `FLAG{lateral_movement_psexec_detected_6a1c}`

#### Step-by-Step

1. Search for authentication events on the domain controller:

```spl
index=windows host="DC01" EventCode=4624
| table _time, Account_Name, Source_Network_Address, Logon_Type
| sort _time
```

Focus on:
- **Logon Type 3** (Network logon) -- typical for PsExec, SMB
- **Logon Type 10** (RemoteInteractive) -- RDP

2. Look for PsExec indicators:

```spl
index=windows host="DC01" sourcetype="WinEventLog:Microsoft-Windows-Sysmon/Operational"
| search Image="*psexe*" OR ParentImage="*PSEXESVC*" OR CommandLine="*\\\\*\\ADMIN$*"
| table _time, Image, ParentImage, CommandLine, User
```

3. Check for service creation events (PsExec creates a temporary service):

```spl
index=windows host="DC01" EventCode=7045
| table _time, Service_Name, Service_File_Name, Service_Account
```

4. In Security Onion, look for SMB traffic between the workstation and DC:

```
source.ip: 10.X.Y.20 AND destination.ip: 10.X.Y.21 AND destination.port: 445
```

5. Check for pass-the-hash or pass-the-ticket attacks:

```spl
index=windows host="DC01" EventCode=4624 Logon_Type=3
| search Account_Name!="*$"
| table _time, Account_Name, Source_Network_Address, Authentication_Package
```

- `NTLM` authentication from unexpected sources may indicate pass-the-hash.

6. Document the lateral movement path and technique used.

7. Validate and submit the flag.

---

### Objective 5: Identify Data Exfiltration (100 points)

**Goal:** Detect evidence of data exfiltration from the domain controller.

**Flag:** `FLAG{data_exfil_detected_https_upload_4b7d}`

#### Step-by-Step

1. Check for large outbound transfers from the domain controller:

```spl
index=network sourcetype=zeek_conn src_ip="10.X.Y.21"
| stats sum(orig_bytes) as bytes_out by dest_ip, dest_port
| sort -bytes_out
| eval MB=round(bytes_out/1024/1024, 2)
```

2. Look for archive creation on the DC:

```spl
index=windows host="DC01" sourcetype="WinEventLog:Microsoft-Windows-Sysmon/Operational" EventCode=1
| search CommandLine="*zip*" OR CommandLine="*rar*" OR CommandLine="*7z*" OR CommandLine="*tar*"
| table _time, Image, CommandLine, User
```

3. Check for file access events on sensitive directories:

```spl
index=windows host="DC01" EventCode=4663
| search Object_Name="*confidential*" OR Object_Name="*HR*" OR Object_Name="*Finance*"
| table _time, Account_Name, Object_Name, Access_Mask
```

4. In Security Onion, analyze outbound HTTPS connections for data volume anomalies:

```
source.ip: 10.X.Y.21 AND destination.port: 443
```

5. Document: what data was targeted, how it was staged, and how it was exfiltrated.

6. Validate and submit the flag.

---

### Objective 6: Analyze Malware Artifact (100 points)

**Goal:** Analyze the malware dropper found on the compromised workstation.

**Flag:** `FLAG{malware_hash_identified_trojan_9c5a}`

#### Step-by-Step

1. On the **Analyst Desktop**, the malware sample has been safely extracted for analysis at `/opt/samples/dropper.exe`.

2. Compute the file hash:

```bash
sha256sum /opt/samples/dropper.exe
md5sum /opt/samples/dropper.exe
```

3. Check the file type:

```bash
file /opt/samples/dropper.exe
```

4. Extract strings for quick analysis:

```bash
strings /opt/samples/dropper.exe | less
```

Look for:
- URLs or IP addresses (C2 servers)
- Registry key paths (persistence)
- File paths
- API calls (CreateProcess, WriteFile, RegSetValue)

5. Examine the PE headers:

```bash
objdump -x /opt/samples/dropper.exe | head -100
```

6. Check the hash against known threat intelligence by searching the hash in the provided threat intel database:

```bash
/opt/tools/threat_intel_lookup.sh $(sha256sum /opt/samples/dropper.exe | awk '{print $1}')
```

7. Document your findings: file type, hashes, embedded IOCs, and classification.

8. Validate and submit the flag.

---

### Objective 7: Build an Incident Timeline (150 points)

**Goal:** Construct a complete timeline of the attack from initial access through data exfiltration.

**Flag:** `FLAG{incident_timeline_complete_7d3e}`

#### Step-by-Step

1. Using all the evidence gathered from Objectives 1--6, build a chronological timeline.

2. Your timeline should include:

| Time (UTC) | Source         | Event                                    | ATT&CK Technique       |
|------------|----------------|------------------------------------------|------------------------|
| HH:MM:SS   | Email logs     | Phishing email received                  | T1566.001 Spearphishing|
| HH:MM:SS   | Sysmon         | Malicious macro executed                 | T1204.002 User Exec    |
| HH:MM:SS   | Sysmon         | PowerShell beacon launched               | T1059.001 PowerShell   |
| HH:MM:SS   | DNS logs       | C2 DNS tunnel established                | T1071.004 DNS          |
| HH:MM:SS   | Security Log   | Lateral movement to DC via PsExec       | T1021.002 SMB/Admin    |
| HH:MM:SS   | Security Log   | Sensitive files accessed                 | T1005 Local Data       |
| HH:MM:SS   | Network flows  | Data exfiltrated over HTTPS              | T1048.002 Exfil C2     |

3. Save your timeline to a file on the Analyst Desktop:

```bash
nano /home/analyst/incident_timeline.txt
```

4. Validate:

```bash
/opt/validation/check_timeline.sh /home/analyst/incident_timeline.txt
```

5. Submit the flag.

---

### Objective 8: Write an Incident Report (100 points)

**Goal:** Write a formal incident report summarizing the attack, impact, and recommendations.

**Flag:** `FLAG{incident_report_submitted_2e8f}`

#### Step-by-Step

1. Create an incident report with the following sections:

**Incident Summary**
- Date/time of detection
- Severity level (Critical/High/Medium/Low)
- Systems affected
- Brief description

**Incident Details**
- Attack vector (how did the attacker get in?)
- Attack progression (timeline summary)
- Impact assessment (what data was compromised?)
- Indicators of Compromise (IOCs) -- IPs, domains, file hashes

**Containment Actions Taken**
- What was done to stop the attack?
- Which systems were isolated?

**Recommendations**
- Short-term fixes (patch, block IOCs, reset credentials)
- Long-term improvements (email filtering, EDR deployment, network segmentation)

2. Save and validate:

```bash
nano /home/analyst/incident_report.txt
/opt/validation/check_report.sh /home/analyst/incident_report.txt
```

3. Submit the flag.

---

## Hints and Tips

- **Start with the alerts.** They point you to the most interesting events. From there, pivot to related logs.
- **Use Splunk's timeline view** to visualize when events occurred and identify clusters of activity.
- **Correlation is key.** A single log entry rarely tells the full story. Cross-reference Windows events, network flows, and DNS logs.
- **MITRE ATT&CK Navigator** is a great tool for mapping out the techniques you observe.
- **When in doubt, search broadly** in Splunk (e.g., `index=* 10.X.Y.20`) and then narrow down with filters.
- **Take notes as you go.** You will need them for the timeline and report objectives.

---

## Additional Resources

- [MITRE ATT&CK Framework](https://attack.mitre.org/) -- Technique reference
- [Splunk Search Processing Language (SPL)](https://docs.splunk.com/Documentation/Splunk/latest/SearchReference) -- Query syntax
- [Security Onion Documentation](https://docs.securityonion.net/) -- NSM platform guide
- [SANS Incident Handler's Handbook](https://www.sans.org/white-papers/33901/) -- Incident response methodology
- [Sigma Rules](https://github.com/SigmaHQ/sigma) -- Generic SIEM detection rules
- [Cyber Kill Chain](https://www.lockheedmartin.com/en-us/capabilities/cyber/cyber-kill-chain.html) -- Attack lifecycle model

---

## Expected Outcomes

After completing this lab, you should be able to:

1. **Triage security alerts** efficiently, distinguishing true positives from false positives.
2. **Query a SIEM** to search, filter, and correlate security events using SPL.
3. **Investigate a multi-stage attack** from initial access through data exfiltration.
4. **Analyze malware artifacts** using static analysis techniques.
5. **Construct an incident timeline** mapping events to MITRE ATT&CK techniques.
6. **Write a professional incident report** suitable for management and technical audiences.
7. **Understand the daily workflow** of a SOC analyst and the tools they use.
