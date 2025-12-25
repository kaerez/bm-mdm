#!/bin/bash
# ==============================================================================
#  BM-MDM Utility
#  Author: Erez Kalman
# ==============================================================================

# Define color codes
RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m'

# --- 1. Dynamic Volume Detection ---
# Universal detection for APFS Data Volumes (Intel & Apple Silicon)
get_data_volume() {
    # Try finding standard macOS Data volume pattern (e.g. "Macintosh HD - Data")
    vol=$(ls -d /Volumes/*" - Data" 2>/dev/null | head -n 1)
    if [ -z "$vol" ]; then
        # Fallback: check for simple "Data" (common in custom setups)
        vol=$(ls -d /Volumes/Data 2>/dev/null | head -n 1)
    fi
    echo "$vol"
}

DATA_VOL=$(get_data_volume)

# --- 2. FileVault Detection ---
check_filevault() {
    if [ -z "$DATA_VOL" ]; then
        echo "Unknown"
        return
    fi
    # fdesetup is the standard binary for FileVault management across all architectures
    fv_status=$(fdesetup status 2>/dev/null)
    
    if [[ "$fv_status" == *"On"* ]]; then
        echo "Active"
    elif [[ "$fv_status" == *"Off"* ]]; then
        echo "Inactive"
    else
        echo "Unknown"
    fi
}

FV_RAW_STATUS=$(check_filevault)

# Set Color for FV Status
if [ "$FV_RAW_STATUS" == "Active" ]; then
    FV_DISPLAY="${GRN}Active${NC}"
elif [ "$FV_RAW_STATUS" == "Inactive" ]; then
    FV_DISPLAY="${RED}Inactive${NC}"
else
    FV_DISPLAY="${YEL}Unknown${NC}"
fi

# --- 3. Smart UID Calculation ---
get_next_available_uid() {
    dscl_path="$DATA_VOL/private/var/db/dslocal/nodes/Default"
    
    # Safely finds the highest user ID > 500 to avoid conflicts
    last_uid=$(dscl -f "$dscl_path" localhost -list /Local/Default/Users UniqueID | awk '$2 >= 500 {print $2}' | sort -rn | head -1)
    
    if [ -z "$last_uid" ]; then
        # Default start for fresh systems
        echo "501"
    else
        # Increment highest found ID by 1
        echo $((last_uid + 1))
    fi
}

# --- Header Display ---
clear
echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}               BM-MDM Utility                 ${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

if [ -z "$DATA_VOL" ]; then
    echo -e "${RED}CRITICAL ERROR: Data volume not found in /Volumes.${NC}"
    echo -e "1. Open Disk Utility."
    echo -e "2. Right-click 'Macintosh HD - Data' (or your drive name) and select Mount."
    echo -e "3. Run this script again."
    exit 1
else
    echo -e "Target Volume:    ${YEL}$DATA_VOL${NC}"
    echo -e "FileVault Status: $FV_DISPLAY"
    echo ""
fi

# --- Main Menu ---
PS3='Select your setup type: '
options=("Fresh Setup (New/Wiped Mac)" "Preserve Data (Existing Users)" "Reboot & Exit")
select opt in "${options[@]}"; do
    case $opt in
        "Fresh Setup (New/Wiped Mac)")
            TARGET_UID="501"
            echo -e "${GRN}>> Mode: Fresh Setup${NC}"
            echo -e "Creating Primary Admin (UID 501)..."
            break
            ;;
        "Preserve Data (Existing Users)")
            echo -e "${GRN}>> Mode: Preserve Data${NC}"
            echo -e "Calculating safe UID to prevent account conflicts..."
            TARGET_UID=$(get_next_available_uid)
            echo -e "Target UID assigned: ${CYAN}$TARGET_UID${NC}"
            break
            ;;
        "Reboot & Exit")
            echo "Rebooting..."
            reboot
            exit 0
            ;;
        *) echo "Invalid option $REPLY" ;;
    esac
done

# --- Credentials Input ---
echo ""
echo -e "${YEL}User Configuration:${NC}"
read -p "Enter New Username (Default: 'Apple'): " username
username="${username:=Apple}"
read -p "Enter Full Name (Default: 'Apple Admin'): " realName
realName="${realName:=Apple Admin}"
read -p "Enter Password (Default: '1234'): " passw
passw="${passw:=1234}"

# --- Execution ---
dscl_path="$DATA_VOL/private/var/db/dslocal/nodes/Default"

if [ ! -d "$dscl_path" ]; then
    echo -e "${RED}Error: User database not found at $dscl_path${NC}"
    exit 1
fi

echo ""
echo -e "${GRN}[1/4] Creating User '$username' (UID $TARGET_UID)...${NC}"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$TARGET_UID"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
mkdir -p "$DATA_VOL/Users/$username"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username

echo -e "${GRN}[2/4] Blocking MDM Domains...${NC}"
HOSTS_FILE="$DATA_VOL/private/etc/hosts"
# Fallback if Data volume uses a symlink for etc (rare but possible in future OS)
if [ ! -f "$HOSTS_FILE" ]; then
    HOSTS_FILE="/Volumes/Macintosh HD/etc/hosts" 
fi

if [ -f "$HOSTS_FILE" ]; then
    # Clean check to avoid duplicate entries if script runs twice
    if ! grep -q "deviceenrollment.apple.com" "$HOSTS_FILE"; then
        echo "0.0.0.0 deviceenrollment.apple.com" >> "$HOSTS_FILE"
        echo "0.0.0.0 mdmenrollment.apple.com" >> "$HOSTS_FILE"
        echo "0.0.0.0 iprofiles.apple.com" >> "$HOSTS_FILE"
        echo "Blocked MDM domains."
    else
        echo "MDM domains already blocked."
    fi
else
    echo -e "${RED}Warning: Could not locate hosts file. Network block skipped.${NC}"
fi

echo -e "${GRN}[3/4] Removing Enrollment Profiles...${NC}"
touch "$DATA_VOL/private/var/db/.AppleSetupDone"
CONF_PATH="$DATA_VOL/private/var/db/ConfigurationProfiles"

# Ensure directory exists to avoid errors on fresh systems
mkdir -p "$CONF_PATH/Settings"

rm -rf "$CONF_PATH/Settings/.cloudConfigHasActivationRecord"
rm -rf "$CONF_PATH/Settings/.cloudConfigRecordFound"
touch "$CONF_PATH/Settings/.cloudConfigProfileInstalled"
touch "$CONF_PATH/Settings/.cloudConfigRecordNotFound"

# --- 4. Database Wipe (The Missing Fix) ---
echo -e "${GRN}[4/4] System Cleanup...${NC}"
# This removes the actual database of installed profiles
rm -rf "$CONF_PATH/Store"
rm -rf "$CONF_PATH/Setup"

# --- Completion & Instructions ---
echo ""
echo -e "${CYAN}==============================================${NC}"
echo -e "${GRN}   SUCCESS: Operation Complete                ${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

# Logic: Display Secure Token instructions ONLY if:
# 1. We created a secondary user (UID != 501)
# 2. FileVault is NOT Inactive (Active or Unknown)
if [[ "$TARGET_UID" != "501" ]] && [[ "$FV_RAW_STATUS" != "Inactive" ]]; then
    echo -e "${YEL}IMPORTANT NEXT STEPS (FileVault is $FV_RAW_STATUS):${NC}"
    echo -e "1. Reboot your Mac."
    echo -e "2. Login with your OLD User (to unlock the disk)."
    echo -e "3. Open Terminal and run this command to fix disk access for '$username':"
    echo ""
    echo -e "${PUR}------------------------------------------------------------${NC}"
    echo -e "sysadminctl -secureTokenOn $username -password - -adminUser OLD_USERNAME -adminPassword -"
    echo -e "${PUR}------------------------------------------------------------${NC}"
    echo -e "(Replace OLD_USERNAME with your current admin name)"
    echo ""
else
    echo -e "You can now reboot and log in as '$username'."
fi

echo -e "${NC}You may now restart your Mac.${NC}"


