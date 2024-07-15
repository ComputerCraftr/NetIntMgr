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

ETHERNET_INTERFACE="$ETHERNET_INTERFACE"
WIFI_INTERFACE="$WIFI_INTERFACE"

ETHERNET_STATUS=\$(ifconfig \$ETHERNET_INTERFACE | grep 'status: active')

if [ -n "\$ETHERNET_STATUS" ]; then
    # Ethernet is connected, turn off Wi-Fi
    networksetup -setairportpower \$WIFI_INTERFACE off
else
    # Ethernet is not connected, turn on Wi-Fi
    networksetup -setairportpower \$WIFI_INTERFACE on
fi
EOF

    chmod +x "$SCRIPT_PATH"
    echo "Network management script created at $SCRIPT_PATH"
}

# Create the LaunchDaemon plist
create_plist() {
    echo "Creating LaunchDaemon plist..."
    tee "$PLIST_PATH" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.netintmgr</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>WatchPaths</key>
    <array>
        <string>/Library/Preferences/SystemConfiguration</string>
    </array>
</dict>
</plist>
EOF

    chmod 644 "$PLIST_PATH"
    echo "LaunchDaemon plist created at $PLIST_PATH"
}

# Load the LaunchDaemon
load_daemon() {
    echo "Loading the LaunchDaemon..."
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
    read -r -p "Do you want to install or uninstall the network management script? (install/uninstall): " ACTION
    case "$ACTION" in
    install)
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
        echo "Invalid action. Please run the script again and choose 'install' or 'uninstall'."
        exit 1
        ;;
    esac
}

main
