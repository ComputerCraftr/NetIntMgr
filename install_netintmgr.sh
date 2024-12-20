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

# Function to detect network interfaces
detect_interfaces() {
    echo "Detecting network interfaces..."
    networksetup -listallhardwareports

    read -r -p "Enter the name of the Ethernet interface (e.g., en5): " ETHERNET_INTERFACE
    read -r -p "Enter the name of the Wi-Fi interface (e.g., en0): " WIFI_INTERFACE

    echo "Ethernet Interface: $ETHERNET_INTERFACE"
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
ETHERNET_INTERFACE="$ETHERNET_INTERFACE"
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

ETHERNET_STATUS=\$(ifconfig \$ETHERNET_INTERFACE 2>/dev/null | grep 'status: active' || true)

if [ -n "\$ETHERNET_STATUS" ]; then
    # Ethernet is connected, turn off Wi-Fi
    networksetup -setairportpower \$WIFI_INTERFACE off
else
    # Ethernet is not connected, turn on Wi-Fi
    networksetup -setairportpower \$WIFI_INTERFACE on
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
        exit 1
        ;;
    esac
}

main
