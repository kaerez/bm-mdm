# Advanced Service Termination & Cleanup 🧹

> **Companion Module to [Bye Mac MDM (BM-MDM)](https://github.com/kaerez/bm-mdm)**
> While **BM-MDM** handles the operating system level (Apple MDM enrollment), this guide handles the **application level**—specifically stubborn third-party agents (Cisco Secure Client, CrowdStrike Falcon, GlobalProtect) that persist effectively like malware.

### Disclaimer & No Liability ⚖️

**NO LIABILITY:** This guide and associated commands are provided "AS IS" without warranty of any kind, express or implied. The authors and contributors are not liable for any data loss, system instability, hardware damage, or legal consequences resulting from their use.

* **Backup Recommended:** It is strongly recommended to backup your data before running system-level commands (`sudo`, `launchctl`, `rm`).

* **Use at Your Own Risk:** This procedure forcefully terminates background services and modifies system configuration. This tool is for educational and authorized recovery purposes only. Use responsibly.

### Purpose 🎯

Standard Operating Procedure for forcefully terminating, disabling, and **permanently blocking** persistent background services on macOS. This is critical for post-bypass cleanup or removing "unkillable" security agents.

### The Core Logic 🧠

Simply running `kill` or `pkill` is ineffective for services managed by `launchd` (the macOS service manager) because the system is configured to restart them immediately upon death (`KeepAlive: true`).

**The Universal Strategy:**
To successfully terminate a persistent process, you must follow this specific order of operations:

1. **Identify:** Find the process ID (PID) and the internal "Service Label".

2. **Bootout:** Instruct `launchd` to stop managing the service.

3. **Disable:** Mark the service as disabled in the system database to prevent restarts.

4. **Kill:** Forcefully terminate the lingering process.

### Universal Workflow (The "PID Method") 🛠️

Use this workflow for **any** stubborn application that refuses to quit.

#### 1. Discovery

Find the process ID (PID) and the correct name of the running application.

```zsh
# List all running processes matching your keyword
pgrep -fl <search_term>
```

* *Note the PID (number) and the distinct name string.*

#### 2. Identify the Service Label

Filenames (like `.plist`) often do not match the internal Service Label. Always query `launchd`.

```zsh
launchctl list | grep <PID>
# Output Format: <PID> <Status> <SERVICE_LABEL>
```

#### 3. Bootout & Disable

Once you have the `<SERVICE_LABEL>`, determine if it is a **User** service (running as you) or a **System** service (running as root).

* **If running as User (GUI):**

  ```zsh
  launchctl bootout gui/$(id -u)/<SERVICE_LABEL>
  launchctl disable gui/$(id -u)/<SERVICE_LABEL>
  ```

* **If running as Root (System):**

  ```zsh
  sudo launchctl bootout system/<SERVICE_LABEL>
  sudo launchctl disable system/<SERVICE_LABEL>
  ```

#### 4. The Kill

Now that the manager (`launchd`) is detached, the process can be killed without respawning.

```zsh
# WARNING: The -f flag matches the FULL command line.
# Be specific! Use "Cisco Secure Client" not just "Client".
pkill -9 -f "<Specific App Name>"
```

### Real-World Examples 🌍

#### Example A: Cisco Secure Client (User Agent)

*Scenario: A standard user-level application that keeps respawning.*

1. **Discovery:** `pgrep -fl cisco` reveals `"Cisco Secure Client"`.

2. **Label Lookup:** `launchctl list | grep <PID>` reveals `com.cisco.secureclient.vpn.notification`.

3. **Action (User Scope):**

   ```zsh
   launchctl bootout gui/$(id -u)/com.cisco.secureclient.vpn.notification
   launchctl disable gui/$(id -u)/com.cisco.secureclient.vpn.notification
   pkill -9 -f "Cisco Secure Client"
   ```

#### Example B: CrowdStrike Falcon (System Daemon + Tamper Protection)

*Scenario: A root-level security agent with variable names and kernel protection.*

1. **Discovery:** `pgrep -fl falcon` shows `"Falcon Notifications"` (PID 15482).

2. **Label Lookup:** `launchctl list | grep 15482` reveals `com.crowdstrike.falcon.UserAgent`.

3. **Action (Mixed Scope):**

   ```zsh
   # Stop the UI (User scope)
   launchctl bootout gui/$(id -u)/com.crowdstrike.falcon.UserAgent
   
   # Stop the Kernel Agent (System scope - requires sudo)
   sudo launchctl bootout system/com.crowdstrike.falcon.Agent
   
   # Kill Remnants
   pkill -9 -f "Falcon Notifications"
   ```

### Prevention: "Salt the Earth" Strategy 🛡️

**Concept:** Just as **BM-MDM** blocks Apple servers to prevent OS re-enrollment, this strategy blocks **Local File Recreation** to prevent app re-installation.
If you fear the software will automatically reinstall via a lingering MDM script, occupy its file path with a locked, quarantined dummy file.

**The Workflow:**

1. **Delete** the original file.

2. **Touch** a dummy file at the same path.

3. **Quarantine** the dummy file (marks it as malware/suspicious).

4. **Lock** the file (immutable).

**Example Command Block:**

```zsh
TARGET="/Applications/Falcon.app" # Or a .plist path

# 1. Create dummy
sudo touch "$TARGET"

# 2. Apply Quarantine Attribute (Copy-paste exactly)
sudo xattr -w com.apple.quarantine "0083;67f124dc;Safari;/Users/Shared/file.zip" "$TARGET"

# 3. Lock the file
sudo chflags uchg,schg "$TARGET"
```

*To reverse this (unlock), run: `sudo chflags nouchg,noschg "$TARGET"`*

### Advanced Troubleshooting ⚠️

#### Issue: "Operation not permitted" (Deleting Files)

If you try to delete an app (`rm -rf ...`) and get "Operation not permitted," **Tamper Protection** or **SIP** (System Integrity Protection) is blocking you.

**Solution A: Recovery Mode Deletion (Recommended)**
This often bypasses file protections without disabling SIP globally.

1. **Reboot** into Recovery Mode (Hold Power on Apple Silicon / Cmd+R on Intel).
2. Open **Terminal** (Utilities > Terminal).
3. **Delete the files directly** (Your disk is usually mounted at `/Volumes/Macintosh HD` or `/Volumes/Data`):
   ```zsh
   rm -rf /Volumes/Macintosh\ HD/Applications/<App_Name>.app
   ```
4. **Reboot** normally.

**Solution B: Disable SIP (The "Nuclear" Option)**
If Solution A fails, you must temporarily disable SIP entirely.

1. **Reboot** into Recovery Mode > **Terminal**.
2. Run: `csrutil disable` (Type 'y' to confirm if asked).
3. **Reboot** normally and log in.
4. Delete the stubborn files (Protection is now OFF).
5. **Reboot** into Recovery Mode > **Terminal**.
6. Run: `csrutil enable` (**CRITICAL**: Never leave SIP disabled).
7. **Reboot**.

#### Issue: Locked Files

If `rm` fails with "Permission denied" (not "Operation not permitted"), check for file flags:

```zsh
ls -lO /Path/To/File
# If you see "uchg" or "schg", unlock it:
sudo chflags -R nouchg,noschg /Path/To/File
```

### Automated "Kill Script" 🤖

Save this as `kill_service.sh` to automate the **PID -> Label -> Bootout -> Disable -> Kill** workflow.

```bash
#!/bin/bash
# Usage: ./kill_service.sh "Search Term"
# Example: ./kill_service.sh "GlobalProtect"

SEARCH_TERM="$1"
USER_ID=$(id -u)

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: $0 <process_name_pattern>"
    exit 1
fi

echo "--- Hunting for processes matching: '$SEARCH_TERM' ---"
PIDS=$(pgrep -f "$SEARCH_TERM")

if [ -z "$PIDS" ]; then
    echo "No running processes found matching '$SEARCH_TERM'."
    exit 0
fi

for PID in $PIDS; do
    echo "Processing PID: $PID"
    
    # 1. Identify the Label
    LABEL_INFO=$(launchctl list | grep "\b$PID\b")
    LABEL=$(echo "$LABEL_INFO" | awk '{print $3}')
    
    if [ ! -z "$LABEL" ]; then
        echo "  [FOUND] Managed by Launchd Label: $LABEL"
        
        # 2. Attempt Bootout (Try User first, then System)
        echo "  [ACTION] Attempting Bootout..."
        launchctl bootout gui/$USER_ID/$LABEL 2>/dev/null
        if [ $? -eq 0 ]; then
             echo "    -> User bootout successful."
             # 3. Disable (User)
             echo "  [ACTION] Disabling service..."
             launchctl disable gui/$USER_ID/$LABEL
        else
             sudo launchctl bootout system/$LABEL 2>/dev/null
             if [ $? -eq 0 ]; then
                 echo "    -> System bootout successful."
                 # 3. Disable (System)
                 echo "  [ACTION] Disabling service..."
                 sudo launchctl disable system/$LABEL
             else
                 echo "    -> Bootout failed (Tamper Protection active?)."
             fi
        fi
    else
        echo "  [INFO] Not managed by launchd (or label hidden)."
    fi
    
    # 4. Force Kill
    echo "  [ACTION] Sending SIGKILL to PID $PID..."
    sudo kill -9 $PID 2>/dev/null
done

echo "--- Hunt Complete ---"
```
