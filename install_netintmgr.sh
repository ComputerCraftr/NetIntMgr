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
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$INSTALLER_DIR/templates"
SCRIPT_TEMPLATE_PATH="$TEMPLATE_DIR/netintmgr.sh.tmpl"
PLIST_TEMPLATE_PATH="$TEMPLATE_DIR/com.user.netintmgr.plist.tmpl"

# Validate network interface
validate_interface() {
    if ! ifconfig "$1" >/dev/null 2>&1; then
        echo "Error: Invalid interface '$1'. Please enter a valid network interface."
        return 1
    fi
}

validate_templates() {
    if [ ! -f "$SCRIPT_TEMPLATE_PATH" ]; then
        echo "Error: Missing script template at $SCRIPT_TEMPLATE_PATH"
        return 1
    fi

    if [ ! -f "$PLIST_TEMPLATE_PATH" ]; then
        echo "Error: Missing plist template at $PLIST_TEMPLATE_PATH"
        return 1
    fi
}

render_template() {
    local template_path="$1"
    local destination_path="$2"

    awk \
        -v ethernet_interfaces="$ETHERNET_INTERFACES" \
        -v wifi_interface="$WIFI_INTERFACE" \
        -v script_path="$SCRIPT_PATH" \
        -v log_dir="${LOG_DIR:-/tmp}" \
        '{
            gsub(/__ETHERNET_INTERFACES__/, ethernet_interfaces)
            gsub(/__WIFI_INTERFACE__/, wifi_interface)
            gsub(/__SCRIPT_PATH__/, script_path)
            gsub(/__LOG_DIR__/, log_dir)
            print
        }' "$template_path" >"$destination_path"
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
    render_template "$SCRIPT_TEMPLATE_PATH" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    echo "Network management script created at $SCRIPT_PATH"
}

# Create the LaunchDaemon plist
create_plist() {
    echo "Creating LaunchDaemon plist..."

    LOG_DIR=${LOG_DIR:-/tmp}
    render_template "$PLIST_TEMPLATE_PATH" "$PLIST_PATH"
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
    validate_templates

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
