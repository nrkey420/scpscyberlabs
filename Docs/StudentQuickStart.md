# CyberLab -- Student Quick Start Guide

Welcome to CyberLab, your school's cybersecurity lab platform. This guide will help you get started with accessing labs, connecting to virtual machines, and completing objectives.

---

## Table of Contents

1. [Accessing CyberLab](#1-accessing-cyberlab)
2. [Finding Your Assigned Labs](#2-finding-your-assigned-labs)
3. [Connecting to VMs](#3-connecting-to-vms)
4. [Understanding the Lab Interface](#4-understanding-the-lab-interface)
5. [Submitting Flags](#5-submitting-flags)
6. [Viewing Your Progress and Leaderboard](#6-viewing-your-progress-and-leaderboard)
7. [Tips for Success](#7-tips-for-success)
8. [Getting Help and Troubleshooting](#8-getting-help-and-troubleshooting)
9. [Code of Conduct for Lab Use](#9-code-of-conduct-for-lab-use)

---

## 1. Accessing CyberLab

### What You Need

- A modern web browser (Chrome, Firefox, Edge, or Safari)
- Your school Microsoft account credentials
- An internet connection

No additional software installation is required. Everything runs in your browser.

### How to Log In

1. Open your browser and go to the CyberLab URL provided by your instructor (e.g., `https://cyberlab.yourdomain.edu`).
2. Click **Sign in with Microsoft**.
3. Enter your school email address (e.g., `firstname.lastname@yourdomain.edu`).
4. Enter your password.
5. Complete multi-factor authentication if prompted.
6. You will be taken to your Student Dashboard.

---

## 2. Finding Your Assigned Labs

After logging in, your dashboard shows all labs assigned to you.

### Lab Card Information

Each assigned lab appears as a card with:

| Field              | Description                                    |
|--------------------|------------------------------------------------|
| **Lab Name**       | The name of the lab scenario                   |
| **Status**         | Assigned, In Progress, Completed, or Expired   |
| **Due Date**       | When the session expires                       |
| **Difficulty**     | Beginner, Intermediate, Advanced, or Expert    |
| **Duration**       | Estimated time to complete                     |
| **Progress**       | Number of objectives completed                 |

### Lab Statuses

- **Assigned** -- Your instructor has assigned this lab to you, but you have not started yet.
- **In Progress** -- You have connected to the lab and started working.
- **Completed** -- You have finished all objectives (or the session ended).
- **Expired** -- The session time ran out. Your progress is saved.

Click **Open Lab** on any assigned lab to enter the lab environment.

---

## 3. Connecting to VMs

CyberLab uses browser-based virtual machine access. You do not need to install any VPN, RDP client, or SSH client.

### How to Connect

1. Open your assigned lab.
2. You will see a list of available VMs on the left sidebar.
3. Click on a VM name to open a console connection.
4. The VM desktop or terminal appears directly in your browser.
5. Interact with the VM using your keyboard and mouse just as you would with a local computer.

### Connection Tips

- **Full Screen** -- Click the full-screen button in the toolbar to maximize the VM view.
- **Clipboard** -- Use the clipboard panel (Ctrl+Alt+Shift on the console) to copy/paste text between your computer and the VM.
- **Keyboard Shortcuts** -- Some keyboard shortcuts (like Ctrl+Alt+Del) have special buttons in the toolbar since your browser may intercept them.
- **Multiple VMs** -- You can switch between VMs by clicking different VM names in the sidebar. Only one VM console is displayed at a time.

### If You Cannot Connect

- Make sure the VM status shows **Running** (green indicator).
- If the VM shows **Paused** or **Saved**, click **Resume** to bring it back.
- If the screen is black, wait a moment -- the VM may still be booting.
- Try refreshing your browser page.

---

## 4. Understanding the Lab Interface

The lab interface has three main areas:

### Left Sidebar

- **VM List** -- All virtual machines in your lab with their status indicators.
- **Objectives Panel** -- A checklist of objectives you need to complete, with point values.
- **Hints** -- Available hints for each objective (may cost points depending on the lab).
- **Timer** -- Time remaining in your lab session.

### Center Area

- **VM Console** -- The main area where you interact with the selected virtual machine.
- **Toolbar** -- Controls for full screen, clipboard, Ctrl+Alt+Del, and screenshot.

### Right Sidebar (if visible)

- **Flag Submission** -- A text field to submit flags when you find them.
- **Activity Log** -- Your recent actions and events.
- **Notes** -- A scratchpad where you can take notes during the lab.

### Objective Status Icons

| Icon   | Status       | Description                              |
|--------|--------------|------------------------------------------|
| Circle | Not Started  | You have not attempted this objective yet |
| Clock  | In Progress  | You are currently working on this         |
| Check  | Completed    | You have successfully completed this      |
| Skip   | Skipped      | You chose to skip this objective          |

---

## 5. Submitting Flags

Many lab objectives require you to find and submit a **flag** -- a special text string that proves you completed the objective.

### What Flags Look Like

Flags follow this format:

```
FLAG{some_text_here_1234}
```

You will find flags in various places depending on the objective:
- In a file on the target system
- Displayed after running a specific command
- Hidden in a web application
- In a log file or database

### How to Submit

1. Copy the entire flag text, including `FLAG{` and `}`.
2. In the **Flag Submission** field on the right sidebar, paste the flag.
3. Click **Submit**.
4. If correct, the objective is marked as completed and your points are awarded.
5. If incorrect, you will see an error message. Check for typos and try again.

### Attempt Tracking

The system tracks how many attempts you make for each flag. There is no penalty for incorrect attempts, but your instructor can see the attempt count.

---

## 6. Viewing Your Progress and Leaderboard

### Your Progress

Click **My Progress** on the dashboard or within a lab to see:

- **Objectives Completed** -- How many objectives you have finished across all labs.
- **Total Points** -- Your cumulative score.
- **Badges Earned** -- Special achievements you have unlocked.
- **Time Spent** -- Total time connected to lab VMs.
- **Lab History** -- A list of all past and current lab assignments with scores.

### Leaderboard

The leaderboard shows how you rank among your classmates. Access it from **My Progress** > **Leaderboard**.

The leaderboard displays:

| Rank | Student       | Points | Badges | Labs Completed |
|------|---------------|--------|--------|----------------|
| 1    | Alice J.      | 1,400  | 5      | 3              |
| 2    | Bob S.        | 1,200  | 4      | 3              |
| 3    | You           | 1,100  | 3      | 2              |

### Badges

Badges are awarded for achievements such as:

- **First Flag** -- Submit your first correct flag
- **Speed Demon** -- Complete a lab in under half the estimated time
- **Perfect Score** -- Complete all objectives in a lab
- **Persistent** -- Submit 10+ flag attempts (keep trying!)
- **Team Player** -- Complete a team-based lab objective

---

## 7. Tips for Success

### Before the Lab

- **Read the lab guide** provided by your instructor. It contains the scenario description, network diagram, and objective details.
- **Review prerequisite concepts** mentioned in the lab description.
- **Check your browser** -- make sure you are using an up-to-date version of Chrome, Firefox, Edge, or Safari.

### During the Lab

- **Read each objective carefully** before starting. Understanding what you need to accomplish saves time.
- **Take notes** using the built-in notes panel or your own notebook. Document commands, IP addresses, and findings.
- **Use snapshots** if available. Before attempting something risky, create a snapshot so you can roll back if needed.
- **Work methodically.** In cybersecurity, following a structured approach (reconnaissance, enumeration, exploitation, post-exploitation) yields better results than random guessing.
- **Use hints wisely.** If you are stuck for more than 15 minutes on an objective, check the available hints.
- **Do not skip steps.** Later objectives often build on earlier ones.
- **Watch your timer.** Keep an eye on the session time remaining.

### After the Lab

- **Review what you learned.** The most valuable part of a lab is understanding *why* something worked, not just *that* it worked.
- **Check your progress** to see which objectives you missed.
- **Ask your instructor** about objectives you could not complete.

---

## 8. Getting Help and Troubleshooting

### Common Issues

| Problem                          | Solution                                                |
|----------------------------------|---------------------------------------------------------|
| Cannot log in                    | Verify your school email and password. Contact your instructor if your account is not set up. |
| No labs appear on dashboard      | Your instructor may not have assigned a lab yet. Check with them. |
| VM console is blank/black        | Wait 30 seconds for the VM to boot. If still blank, try refreshing the page. |
| Keyboard not working in VM       | Click inside the VM console area first. Try the on-screen keyboard button in the toolbar. |
| Clipboard paste not working      | Use Ctrl+Alt+Shift to open the Guacamole clipboard panel. Paste text there, then paste inside the VM. |
| VM is paused                     | Click the **Resume** button next to the VM in the sidebar. |
| Session expired                  | Contact your instructor. They may be able to deploy a new session for you. Your progress is saved. |
| Flag is not accepted             | Double-check for extra spaces, capitalization, and that you included `FLAG{` and `}`. |
| Browser is slow or laggy         | Close unnecessary browser tabs. Try a wired network connection instead of Wi-Fi. |

### Getting Human Help

- **During class** -- Raise your hand or ask your instructor directly.
- **Outside class** -- Email your instructor or use the class communication channel.
- **Technical issues** -- If you believe the platform itself has a bug, report it to your instructor with:
  - Your browser name and version
  - What you were doing when the issue occurred
  - Any error messages you saw
  - A screenshot if possible

---

## 9. Code of Conduct for Lab Use

By using CyberLab, you agree to the following rules:

### Acceptable Use

- Use lab VMs **only** for assigned lab activities and learning.
- Stay within the lab network. Do **not** attempt to access systems outside the lab environment.
- Follow your instructor's directions for each lab scenario.
- Report any platform bugs or security issues to your instructor.
- Help classmates learn, but do **not** share flag answers.

### Prohibited Activities

- **Do not** attempt to attack the CyberLab platform itself (the web application, database, or host server).
- **Do not** attempt to access other students' lab sessions or VMs.
- **Do not** use lab VMs for any purpose other than the assigned lab (no personal browsing, downloading, mining, etc.).
- **Do not** share your login credentials with anyone.
- **Do not** copy or distribute lab content, flags, or walkthroughs outside of class.
- **Do not** attempt to bypass session time limits or resource quotas.
- **Do not** intentionally disrupt shared VMs that other students are using.

### Consequences

Violations of this code of conduct may result in:

- Loss of lab access for the remainder of the semester
- A zero grade for the affected lab assignment
- Referral to school administration for disciplinary action

### Remember

The skills you learn in these labs are powerful. The purpose of this platform is to teach you how to **defend** systems and understand how attacks work so you can **prevent** them. Always use your cybersecurity knowledge ethically and responsibly.
