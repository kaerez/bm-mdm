# Bye Mac MDM (BM-MDM): Smart MDM Bypass 🛡️

> Based on the original work by [Assaf Dori](https://github.com/assafdori/bypass-mdm).  
> > This version has been refactored to be architecture-agnostic (Intel/Apple Silicon), safe for existing data (no volume renaming), and context-aware (FileVault & UID detection).

### Features 🚀
* **Universal Compatibility:** Works on macOS Monterey through Sequoia (and beyond) on both Intel and Apple Silicon (M1/M2/M3).
* **Data Safe:** Unlike other scripts, this **does not rename your hard drive**, preventing Time Machine and path corruption.
* **Smart UID Calculation:** Automatically detects existing users to prevent account conflicts (no more overwriting User 501).
* **Context Aware:** Detects FileVault encryption status and provides specific instructions for unlocking the disk.
* **Network Block:** Prevents re-enrollment by blocking Apple's MDM servers in the hosts file.
* **Deep Clean:** Wipes stubborn Managed Preferences and Profile databases.
* **Total Control:** Resets ownership of Applications and System Extensions to the new user.

### Also see the [Advanced Service Termination & Cleanup](https://github.com/kaerez/bm-mdm/README2.md) Companion Module

---

### Disclaimer & No Liability ⚖️

**NO LIABILITY:** This software is provided "AS IS" without warranty of any kind, express or implied. The authors and contributors are not liable for any data loss, hardware damage, or legal consequences resulting from its use.

* **Backup Recommended:** It is strongly recommended to backup your data before running this script.
* **Use at Your Own Risk:** This tool removes local configuration restrictions, but the device serial number remains registered in the organization's ABM (Apple Business Manager) inventory. This tool is for educational and authorized recovery purposes only. Use responsibly.

---

### Prerequisites ⚠️

* **For Fresh Installs:** It is advised to erase the hard drive prior to starting for the cleanest result.
* **For Existing Users:** **ALWAYS BACKUP YOUR DATA** before running system-level scripts. Ensure you know the password of an existing admin account to unlock FileVault.
* **Network:** You will need a WiFi connection in Recovery Mode to download the script.

### Installation Instructions 🛠️

#### 1. Boot into Recovery Mode
* **Apple Silicon (M1/M2/M3):** Turn off the Mac. Press and **hold** the Power button until you see "Loading startup options". Select *Options* > *Continue*.
* **Intel Macs:** Restart and immediately hold <kbd>CMD</kbd> + <kbd>R</kbd> until the Apple logo appears.

#### 2. Prepare the Environment
1.  Connect to WiFi in the top right corner.
2.  **Mount your Disk:** Open **Disk Utility**. If your main drive (`Macintosh HD`) is greyed out, select it and click **Mount**. Enter your password if prompted.
3.  Close Disk Utility.

#### 3. Run the Script
1.  Open **Safari** from the recovery menu.
2.  Navigate to this page (or just type the URL below directly into Terminal if you prefer).
3.  Open **Terminal** (Utilities > Terminal).
4.  Copy and paste the following command, then press <kbd>ENTER</kbd>:

```zsh
curl -L https://raw.githubusercontent.com/kaerez/bm-mdm/main/bmmdm.sh -o bmmdm.sh && chmod +x ./bmmdm.sh && ./bmmdm.sh
```

---

### Usage Guide 📖

The script will present a menu with two modes. Choose the one that matches your situation:

#### Option A: Fresh Setup (New/Wiped Mac)
* **Best for:** Brand new Macs or after a factory reset.
* **Action:** Creates a standard Admin user (UID 501).
* **Next Steps:**
    1.  Reboot.
    2.  Login with the new user (Default: `Apple` / `1234`).
    3.  Skip all setup screens (Apple ID, Siri, etc.).
    4.  Go to **System Settings > Users & Groups** to create your *real* personal account.
    5.  Log out and delete the temporary `Apple` account.

#### Option B: Preserve Data (Existing Users)
* **Best for:** Macs that already have a user account you want to keep.
* **Action:** Creates a secondary Admin user (UID 502+) to avoid corrupting your current data.
* **Next Steps:**
    1.  Reboot.
    2.  **Unlock FileVault:** You must login with your **OLD** user first to unlock the disk.
    3.  **Grant Access (Important):** To let the new user unlock the disk in the future, open Terminal as your *Old User* and run:
        ```zsh
        sysadminctl -secureTokenOn Apple -password - -adminUser YOUR_OLD_NAME -adminPassword -
        ```
    4.  (Replace `Apple` with the new username and `YOUR_OLD_NAME` with your current username).
