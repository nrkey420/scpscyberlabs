# CyberLab Orchestration Platform -- Instructor Manual

## Table of Contents

1. [Logging In](#1-logging-in)
2. [Dashboard Overview](#2-dashboard-overview)
3. [Deploying a Lab](#3-deploying-a-lab)
4. [Monitoring Students](#4-monitoring-students)
5. [Managing Sessions](#5-managing-sessions)
6. [Viewing Student Progress](#6-viewing-student-progress)
7. [Generating Reports](#7-generating-reports)
8. [Managing Snapshots](#8-managing-snapshots)
9. [Best Practices for Lab Management](#9-best-practices-for-lab-management)
10. [FAQ](#10-faq)

---

## 1. Logging In

CyberLab uses your school's Microsoft Entra ID (formerly Azure AD) for single sign-on.

1. Open your browser and navigate to your institution's CyberLab URL (e.g., `https://cyberlab.yourdomain.edu`).
2. Click **Sign in with Microsoft**.
3. Enter your school email and password when prompted by the Microsoft login page.
4. If multi-factor authentication (MFA) is enabled, complete the MFA challenge.
5. You will be redirected to the CyberLab Instructor Dashboard.

> **Note:** Your account must be in the Instructor security group in Entra ID. If you see an "Access Denied" message, contact your system administrator.

---

## 2. Dashboard Overview

After logging in, you land on the Instructor Dashboard. The dashboard is organized into the following sections:

### Top Navigation Bar

| Element           | Description                                          |
|-------------------|------------------------------------------------------|
| **Home**          | Returns to the dashboard                             |
| **Labs**          | Browse and deploy lab templates                      |
| **Sessions**      | View and manage active lab sessions                  |
| **Students**      | View student roster, progress, and leaderboard       |
| **Reports**       | Generate and download reports                        |
| **Profile**       | Account settings and sign out                        |

### Dashboard Cards

- **Active Sessions** -- Number of currently running lab sessions with a quick-action button to view details.
- **Students Online** -- Count of students currently connected to VMs.
- **Resource Usage** -- A gauge showing RAM, vCPU, and disk utilization of the Hyper-V host.
- **Recent Activity** -- A scrollable feed of the latest student and system events.

### Quick Actions

- **Deploy New Lab** -- Starts the lab deployment wizard.
- **View All Sessions** -- Opens the session management page.
- **Student Leaderboard** -- Opens the gamification leaderboard.

---

## 3. Deploying a Lab

Deploying a lab is a 3-step wizard process.

### Step 1: Select a Lab Template

1. Click **Deploy New Lab** from the dashboard or navigate to **Labs** in the top menu.
2. Browse available lab templates. Each template card shows:
   - Lab name and description
   - Difficulty level (Beginner, Intermediate, Advanced, Expert)
   - Estimated duration
   - Number of VMs required
   - Resource requirements (total RAM and vCPUs)
3. Click **Select** on the desired template.

*The template catalog includes labs such as Red Team/Blue Team Cyber Range, Web Application Penetration Testing, SOC Analyst Training, Network Attack and Defense, and Malware Analysis Sandbox.*

### Step 2: Configure the Session

On the configuration screen, fill in:

| Field               | Description                                              | Default          |
|---------------------|----------------------------------------------------------|------------------|
| **Session Name**    | A friendly name for this session (e.g., "Period 3 Lab")  | Template name    |
| **Students**        | Select students from your roster or enter student IDs    | --               |
| **Duration**        | How long the session should remain active                 | 4 hours          |
| **Auto-Pause**      | Pause idle VMs after inactivity timeout                   | Enabled (30 min) |
| **Snapshots**       | Allow students to create snapshots                        | Enabled          |

The system performs a **resource availability check** before proceeding. If insufficient resources are available, you will see a warning with details on what is lacking.

### Step 3: Review and Deploy

1. Review the session summary:
   - Template name and version
   - Number of VMs to provision
   - Assigned students
   - Total resource cost
   - Session expiration time
2. Click **Deploy Lab**.
3. The system begins provisioning. A progress indicator shows:
   - Creating virtual switches
   - Creating differencing disks
   - Starting VMs and waiting for heartbeats
   - Configuring networking
   - Creating initial snapshots
   - Registering connections in Guacamole
4. When provisioning completes, the session status changes to **Running** and students can connect.

> **Tip:** Provisioning typically takes 2--5 minutes depending on the number of VMs.

---

## 4. Monitoring Students

### Real-Time Dashboard

Navigate to **Sessions** and select an active session. The monitoring view shows:

- **Session Header** -- Session name, template, status, time remaining, and resource usage.
- **VM Status Grid** -- A card for each VM showing:
  - VM name and role
  - Current state (Running, Paused, Saved, Stopped)
  - IP address
  - CPU and memory usage
  - Connected student (if applicable)
- **Student Status List** -- Shows each assigned student with:
  - Connection status (Connected / Disconnected)
  - Current VM being used
  - Time connected
  - Objectives completed (progress bar)

### Activity Feed

A live-updating feed at the bottom of the session view shows:

- Student login/logout events
- VM state changes (start, pause, resume, stop)
- Flag submissions (correct and incorrect attempts)
- Snapshot creation and restore events
- System events (auto-pause due to inactivity, resource warnings)

Each entry includes a timestamp, student name, action, and details.

### VM Statuses

| Status Icon | State     | Meaning                                          |
|-------------|-----------|--------------------------------------------------|
| Green       | Running   | VM is powered on and responsive                  |
| Yellow      | Paused    | VM state is suspended (can resume instantly)      |
| Blue        | Saved     | VM state is saved to disk (resume takes seconds)  |
| Gray        | Stopped   | VM is powered off                                |
| Red         | Failed    | VM encountered an error                          |

---

## 5. Managing Sessions

From the session detail page, you have access to the following management actions.

### Extend Timeout

1. Click **Extend Session** in the session header.
2. Choose an extension period (30 minutes, 1 hour, 2 hours, or custom).
3. Click **Confirm**. The new expiration time updates immediately.

### Pause / Resume VMs

- **Pause All VMs** -- Suspends all running VMs in the session. Students are disconnected but can resume where they left off.
- **Resume All VMs** -- Resumes all paused VMs. Students can reconnect.
- **Pause/Resume Individual VM** -- Click the pause/resume button on a specific VM card.

### Reset VMs

- **Reset to Initial State** -- Restores a VM to its "InitialState" snapshot. This erases all student work on that VM.
- **Reset All VMs** -- Restores every VM in the session to initial state.

> **Warning:** Resetting a VM is irreversible. Students will lose any unsaved progress on that VM.

### Terminate Session

1. Click **Terminate Session**.
2. Confirm the action in the dialog.
3. The system will:
   - Stop all running VMs
   - Remove all VM snapshots
   - Delete differencing disks
   - Remove the virtual switch
   - Mark the session as "cleaned_up" in the database

Student progress and scores are preserved in the database even after termination.

---

## 6. Viewing Student Progress

### Individual Student View

1. Navigate to **Students** or click a student name in the session view.
2. The student detail page shows:
   - **Assignment Status** -- Assigned, In Progress, Completed, Expired
   - **Objectives Progress** -- A checklist of all lab objectives with status:
     - Not Started
     - In Progress
     - Completed (with timestamp and points earned)
     - Skipped
   - **Total Score** -- Points earned out of maximum possible points
   - **Connection History** -- Timestamps of when the student connected and disconnected from each VM
   - **Flag Submissions** -- History of submitted flags with correct/incorrect results and attempt counts

### Objectives Overview

From the session view, click **Objectives** to see a matrix of all students vs. all objectives:

| Student        | Obj 1 | Obj 2 | Obj 3 | Obj 4 | Obj 5 | Score |
|----------------|-------|-------|-------|-------|-------|-------|
| Alice Johnson  | Done  | Done  | Done  | --    | --    | 500   |
| Bob Smith      | Done  | Done  | --    | --    | --    | 300   |
| Carol Davis    | Done  | --    | --    | --    | --    | 100   |

### Leaderboard

The gamification system tracks:

- **Points** -- Earned by completing objectives
- **Badges** -- Awarded for achievements (first flag, speed completion, all objectives, etc.)
- **Rank** -- Position on the class leaderboard

Access the leaderboard from **Students** > **Leaderboard**.

---

## 7. Generating Reports

Navigate to **Reports** to generate session and student reports.

### Available Report Types

| Report                  | Description                                              |
|-------------------------|----------------------------------------------------------|
| **Session Summary**     | Overview of a session: duration, VMs, students, scores   |
| **Student Progress**    | Per-student breakdown of objectives, scores, time spent  |
| **Class Performance**   | Aggregate statistics across all students in a session    |
| **Activity Audit**      | Detailed log of all actions during a session             |
| **Resource Utilization**| RAM, CPU, and disk usage over the session lifetime       |

### Export Formats

- **PDF** -- Formatted report suitable for printing or archiving
- **CSV** -- Raw data export suitable for spreadsheets and further analysis

### Generating a Report

1. Select the report type.
2. Choose the session(s) and/or student(s) to include.
3. Select the export format (PDF or CSV).
4. Click **Generate Report**.
5. The report is generated in the background. A download link appears when ready.

---

## 8. Managing Snapshots

Snapshots allow saving and restoring VM state at a point in time.

### Instructor Snapshot Actions

| Action                | Description                                                |
|-----------------------|------------------------------------------------------------|
| **Create Snapshot**   | Save the current state of a VM with a custom name          |
| **View Snapshots**    | List all snapshots for a VM with timestamps and names      |
| **Restore Snapshot**  | Revert a VM to a specific snapshot                         |
| **Delete Snapshot**   | Remove a snapshot to free disk space                       |

### Snapshot Limits

- Maximum snapshots per VM: **5** (configurable)
- Snapshot names must be unique per VM
- The "InitialState" snapshot is created automatically during provisioning and cannot be deleted by students

### How to Create a Snapshot

1. Open the session detail page.
2. Find the target VM card and click **Snapshots**.
3. Click **Create Snapshot**.
4. Enter a name (e.g., "Before Exploit Attempt").
5. Click **Save**. The snapshot is created within seconds.

### How to Restore a Snapshot

1. Open the snapshot list for the VM.
2. Click **Restore** next to the desired snapshot.
3. Confirm the action. The VM will be reverted to that state.

> **Note:** Restoring a snapshot will disconnect the student from the VM temporarily.

---

## 9. Best Practices for Lab Management

### Before Class

- **Test the lab** by deploying it yourself and verifying all VMs start correctly and objectives are achievable.
- **Check resources** on the dashboard to ensure sufficient RAM and CPU for your class size.
- **Pre-deploy labs** 10--15 minutes before class to allow VMs to fully boot.

### During Class

- **Monitor the activity feed** for students who may be stuck (no progress for extended periods).
- **Use the pause feature** if you need to deliver a lecture or demonstration mid-lab.
- **Encourage snapshots** so students can experiment without fear of breaking their environment.
- **Watch resource usage** -- if the host approaches capacity, consider pausing idle sessions.

### After Class

- **Review student progress** before terminating the session.
- **Export reports** for grading and record-keeping.
- **Terminate sessions promptly** to free resources for other classes.
- **Provide feedback** using the student assignment feedback field.

### General Tips

- Start with Beginner-level labs at the beginning of the semester and progress to Advanced.
- Assign team labs (like Red Team/Blue Team) in pairs or small groups.
- Use the leaderboard to motivate students, but remind them that learning matters more than points.
- Schedule labs with buffer time -- students often need more time than the estimated duration.
- Maintain a running document of lessons learned for each lab to improve future iterations.

---

## 10. FAQ

**Q: How many labs can I run simultaneously?**
A: This depends on your server resources. Each lab template specifies its resource requirements. The system will prevent deployment if resources are insufficient. As an instructor, you can run up to 3 concurrent sessions (configurable by your administrator).

**Q: Can students access labs outside of class time?**
A: Yes, as long as the session has not expired and VMs are running or saved. Students can reconnect via the CyberLab URL at any time during the session window.

**Q: What happens when a session expires?**
A: Expired sessions are automatically cleaned up by the background cleanup job. VMs are stopped and deleted, but student progress and scores remain in the database.

**Q: Can I extend a session after it has expired?**
A: No. Once a session expires and is cleaned up, VMs are deleted. You would need to deploy a new session. Student progress from the previous session is preserved in reports.

**Q: How do I add a student to a running session?**
A: Navigate to the session detail page, click **Add Students**, select the student(s), and click **Assign**. The student will be able to connect to the shared VMs or have new per-student VMs provisioned depending on the template configuration.

**Q: Can students accidentally break shared VMs (like Security Onion)?**
A: Shared VMs are accessible to all students in a session. While students cannot delete or stop shared VMs, their actions within the VM could disrupt services. Use snapshots to quickly restore shared VMs if needed.

**Q: How do I grade students?**
A: Navigate to the student progress view for the session. Each objective shows whether it was completed and the points earned. You can also export a CSV report for import into your gradebook.

**Q: What browsers are supported for VM console access?**
A: CyberLab uses Apache Guacamole for browser-based console access. Any modern browser works: Chrome, Firefox, Edge, or Safari. No plugins or extensions are required.

**Q: Can I customize lab templates?**
A: Template customization requires administrator access. Contact your system administrator to create or modify lab templates. You can, however, adjust session parameters (duration, auto-pause, snapshots) during deployment.

**Q: What do I do if a VM is stuck and not responding?**
A: From the session view, use the **Force Stop** action on the VM, wait a few seconds, then **Start** it again. If the issue persists, **Reset to Initial State** using the snapshot restore feature.
