#!/bin/bash

# netintmgr - Network Interface Manager
# This script manages network interfaces to disable Wi-Fi when connected to Ethernet to save power and remove the second default route from the routing tables.

# Exit on errors, undefined variables, and pipe failures
set -euo pipefail
IFS=$'\n\t'

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo or run as root user."
    exit 1
fi

SCRIPT_PATH="/usr/local/bin/netintmgr.sh"
PLIST_PATH="/Library/LaunchDaemons/com.user.netintmgr.plist"

# Validate network interface
validate_interface() {
    if ! ifconfig "$1" >/dev/null 2>&1; then
        echo "Error: Invalid interface '$1'. Please enter a valid network interface."
        return 1
    fi
}

# Process and validate Ethernet interfaces
process_ethernet_interfaces() {
    echo "Processing Ethernet interfaces..."

    # Initialize an array to store valid interfaces
    VALID_INTERFACES=()

    # Split the input and iterate over each interface
    for interface in $(echo "$ETHERNET_INTERFACES" | tr ',' '\n'); do
        interface=$(echo "$interface" | xargs) # Trim whitespace
        if validate_interface "$interface"; then
            VALID_INTERFACES+=("$interface")
        fi
    done

    # Check if we have valid interfaces
    if [ "${#VALID_INTERFACES[@]}" -eq 0 ]; then
        echo "No valid Ethernet interfaces detected."
        return 1
    fi

    # Store the valid interfaces as a comma-separated string
    ETHERNET_INTERFACES=$(
        IFS=','
        echo "${VALID_INTERFACES[*]}"
    )
    echo "Valid Ethernet Interfaces: ${ETHERNET_INTERFACES}"
}

# Detect network interfaces
detect_interfaces() {
    echo "Detecting network interfaces..."
    networksetup -listallhardwareports

    # Read and process Ethernet interfaces
    read -r -p "Enter the list of Ethernet interfaces (comma-separated, e.g., en5,en7): " ETHERNET_INTERFACES
    process_ethernet_interfaces

    # Read and validate the Wi-Fi interface
    read -r -p "Enter the name of the Wi-Fi interface (e.g., en0): " WIFI_INTERFACE
    while ! validate_interface "$WIFI_INTERFACE"; do
        read -r -p "Enter the name of the Wi-Fi interface (e.g., en0): " WIFI_INTERFACE
    done

    echo "Ethernet Interfaces: $ETHERNET_INTERFACES"
    echo "Wi-Fi Interface: $WIFI_INTERFACE"
}

# Create the network management script
create_script() {
    echo "Creating network management script..."
    tee "$SCRIPT_PATH" >/dev/null <<EOF
#!/bin/bash

# Exit on errors, undefined variables, and pipe failures
set -euo pipefail
IFS=\$'\n\t'

LOCKFILE="/tmp/netintmgr.lock"
ETHERNET_INTERFACES="$ETHERNET_INTERFACES"
WIFI_INTERFACE="$WIFI_INTERFACE"

# Check if another instance is running
if [ -f "\$LOCKFILE" ]; then
    echo "Another instance of the script is already running."
    exit 1
fi

# Create the lock file and ensure it's removed on exit
trap 'EXIT_CODE=\$?; rm -f "\$LOCKFILE"; exit \$EXIT_CODE' INT TERM EXIT
touch "\$LOCKFILE"

# Add a delay to ensure the interface status is updated
sleep 2

check_ethernet_status() {
    for interface in \$(echo "\$ETHERNET_INTERFACES" | tr ',' '\n'); do
        if [ "\$(ifconfig "\$interface" 2>/dev/null | grep -c 'status: active')" -gt 0 ]; then
            return 0
        fi
    done
    return 1
}

if check_ethernet_status; then
    # Ethernet is connected, turn off Wi-Fi
    networksetup -setairportpower "\$WIFI_INTERFACE" off
else
    # Ethernet is not connected, turn on Wi-Fi
    networksetup -setairportpower "\$WIFI_INTERFACE" on
fi

# Remove the lock file
rm -f "\$LOCKFILE"
trap - INT TERM EXIT
EOF

    chmod +x "$SCRIPT_PATH"
    echo "Network management script created at $SCRIPT_PATH"
}

# Create the LaunchDaemon plist
create_plist() {
    echo "Creating LaunchDaemon plist..."

    LOG_DIR=${LOG_DIR:-/tmp}
    tee "$PLIST_PATH" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.netintmgr</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>WatchPaths</key>
    <array>
        <string>/Library/Preferences/SystemConfiguration</string>
    </array>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/netintmgr.out</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/netintmgr.err</string>
</dict>
</plist>
EOF

    chmod 644 "$PLIST_PATH"
    echo "LaunchDaemon plist created at $PLIST_PATH"
}

# Load the LaunchDaemon
load_daemon() {
    echo "Loading the LaunchDaemon..."
    if launchctl list | grep -q "com.user.netintmgr"; then
        echo "LaunchDaemon is already loaded. Unloading first..."
        launchctl unload "$PLIST_PATH"
    fi
    launchctl load "$PLIST_PATH"
    echo "LaunchDaemon loaded."
}

# Unload and remove the LaunchDaemon and script
uninstall() {
    echo "Unloading and removing the LaunchDaemon and script..."
    if launchctl list | grep -q "com.user.netintmgr"; then
        launchctl unload "$PLIST_PATH"
        echo "LaunchDaemon unloaded."
    fi
    rm -f "$PLIST_PATH"
    echo "LaunchDaemon plist removed."
    rm -f "$SCRIPT_PATH"
    echo "Network management script removed."
}

# Main execution
main() {
    if [ -f "$SCRIPT_PATH" ] || [ -f "$PLIST_PATH" ]; then
        read -r -p "Existing installation detected. Do you want to reinstall or uninstall the network management script? (reinstall/uninstall): " ACTION
    else
        read -r -p "Do you want to install or uninstall the network management script? (install/uninstall): " ACTION
    fi

    case "$ACTION" in
    install | reinstall)
        detect_interfaces
        create_script
        create_plist
        load_daemon
        echo "Installation complete. The system will now manage network interfaces based on connection status."
        ;;
    uninstall)
        uninstall
        echo "Uninstallation complete. The system will no longer manage network interfaces."
        ;;
    *)
        echo "Invalid action. Please run the script again and choose 'install', 'reinstall', or 'uninstall'."
        return 1
        ;;
    esac
}

main
