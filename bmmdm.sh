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
# Universal detection for APFS Data Volumes
get_data_volume() {
    # Try finding standard macOS Data volume pattern
    vol=$(ls -d /Volumes/*" - Data" 2>/dev/null | head -n 1)
    if [ -z "$vol" ]; then
        # Fallback: check for simple "Data"
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
    # Safely finds the highest user ID > 500
    last_uid=$(dscl -f "$dscl_path" localhost -list /Local/Default/Users UniqueID | awk '$2 >= 500 {print $2}' | sort -rn | head -1)
    
    if [ -z "$last_uid" ]; then
        echo "501" # Default for fresh systems
    else
        echo $((last_uid + 1)) # Increment
    fi
}

# --- Header Display ---
clear
echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}               BM-MDM Utility                 ${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

if [ -z "$DATA_VOL" ]; then
    echo -e "${RED}CRITICAL ERROR: Data volume not found.${NC}"
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
            break
            ;;
        "Preserve Data (Existing Users)")
            echo -e "${GRN}>> Mode: Preserve Data${NC}"
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
    echo -e "${RED}Error: User database not found.${NC}"
    exit 1
fi

echo ""
echo -e "${GRN}[1/4] Creating User '$username' (UID $TARGET_UID)...${NC}"
# Create User Record
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UserShell "/bin/zsh"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" RealName "$realName"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" UniqueID "$TARGET_UID"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" PrimaryGroupID "20"
dscl -f "$dscl_path" localhost -create "/Local/Default/Users/$username" NFSHomeDirectory "/Users/$username"
dscl -f "$dscl_path" localhost -passwd "/Local/Default/Users/$username" "$passw"
dscl -f "$dscl_path" localhost -append "/Local/Default/Groups/admin" GroupMembership $username

# Create Home Directory & Fix Permissions
mkdir -p "$DATA_VOL/Users/$username"
# Set owner to new user, group to staff (20)
chown -R "$TARGET_UID:20" "$DATA_VOL/Users/$username"
# Ensure standard permissions (755) so OS can read it
chmod 755 "$DATA_VOL/Users/$username"

echo -e "${GRN}[2/4] Blocking MDM Domains...${NC}"
HOSTS_FILE="$DATA_VOL/private/etc/hosts"
if [ ! -f "$HOSTS_FILE" ]; then
    # Fallback/Create if missing
    mkdir -p "$DATA_VOL/private/etc"
    touch "$HOSTS_FILE"
fi

if [ -f "$HOSTS_FILE" ]; then
    if ! grep -q "deviceenrollment.apple.com" "$HOSTS_FILE"; then
        echo "0.0.0.0 deviceenrollment.apple.com" >> "$HOSTS_FILE"
        echo "0.0.0.0 mdmenrollment.apple.com" >> "$HOSTS_FILE"
        echo "0.0.0.0 iprofiles.apple.com" >> "$HOSTS_FILE"
        echo "Blocked MDM domains."
    else
        echo "Domains already blocked."
    fi
else
    echo -e "${RED}Warning: Could not access hosts file.${NC}"
fi

echo -e "${GRN}[3/4] Removing Enrollment Profiles...${NC}"
touch "$DATA_VOL/private/var/db/.AppleSetupDone"
CONF_PATH="$DATA_VOL/private/var/db/ConfigurationProfiles"

# Ensure directory exists
mkdir -p "$CONF_PATH/Settings"

rm -rf "$CONF_PATH/Settings/.cloudConfigHasActivationRecord"
rm -rf "$CONF_PATH/Settings/.cloudConfigRecordFound"
touch "$CONF_PATH/Settings/.cloudConfigProfileInstalled"
touch "$CONF_PATH/Settings/.cloudConfigRecordNotFound"

# --- 4. Database Wipe (Critical for Existing Users) ---
echo -e "${GRN}[4/4] System Cleanup...${NC}"
# Removes installed profile databases
rm -rf "$CONF_PATH/Store"
rm -rf "$CONF_PATH/Setup"

# --- Completion ---
echo ""
echo -e "${CYAN}==============================================${NC}"
echo -e "${GRN}   SUCCESS: Operation Complete                ${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

if [[ "$TARGET_UID" != "501" ]] && [[ "$FV_RAW_STATUS" != "Inactive" ]]; then
    echo -e "${YEL}IMPORTANT NEXT STEPS (FileVault is $FV_RAW_STATUS):${NC}"
    echo -e "1. Reboot."
    echo -e "2. Login with OLD User (to unlock disk)."
    echo -e "3. Open Terminal, run:"
    echo -e "${PUR}sysadminctl -secureTokenOn $username -password - -adminUser OLD_USERNAME -adminPassword -${NC}"
else
    echo -e "You can now reboot and log in as '$username'."
fi

echo -e "${NC}You may now restart your Mac.${NC}"


