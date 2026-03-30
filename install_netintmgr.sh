#!/bin/sh

# netintmgr - Network Interface Manager
# This script manages network interfaces to disable Wi-Fi when connected to Ethernet to save power and remove the second default route from the routing tables.

# Exit on errors and undefined variables
set -eu

SCRIPT_PATH="/usr/local/bin/netintmgr.sh"
PLIST_PATH="/Library/LaunchDaemons/com.user.netintmgr.plist"
INSTALLER_DIR=$(dirname -- "$0")
INSTALLER_DIR=$(cd -- "$INSTALLER_DIR" && pwd)
TEMPLATE_DIR="$INSTALLER_DIR/templates"
SCRIPT_TEMPLATE_PATH="$TEMPLATE_DIR/netintmgr.sh.tmpl"
PLIST_TEMPLATE_PATH="$TEMPLATE_DIR/com.user.netintmgr.plist.tmpl"
ACTION=""
ETHERNET_INTERFACES="${ETHERNET_INTERFACES:-}"
WIFI_INTERFACE="${WIFI_INTERFACE:-}"
LOG_DIR="${LOG_DIR:-/tmp}"

# Validate network interface
validate_interface() {
    if ! ifconfig "$1" >/dev/null 2>&1; then
        printf '%s\n' "Error: Invalid interface '$1'. Please enter a valid network interface."
        return 1
    fi
}

validate_templates() {
    if [ ! -f "$SCRIPT_TEMPLATE_PATH" ]; then
        printf '%s\n' "Error: Missing script template at $SCRIPT_TEMPLATE_PATH"
        return 1
    fi

    if [ ! -f "$PLIST_TEMPLATE_PATH" ]; then
        printf '%s\n' "Error: Missing plist template at $PLIST_TEMPLATE_PATH"
        return 1
    fi
}

usage() {
    printf '%s\n' "Usage: $0 [install|reinstall|uninstall] [options]"
    printf '%s\n' ""
    printf '%s\n' "Options:"
    printf '%s\n' "  -e, --ethernet INTERFACES  Comma-separated Ethernet interfaces"
    printf '%s\n' "  -w, --wifi INTERFACE       Wi-Fi interface"
    printf '%s\n' "  -l, --log-dir DIR          Log directory for LaunchDaemon output"
    printf '%s\n' "  -h, --help                 Show this help message"
    printf '%s\n' ""
    printf '%s\n' "Examples:"
    printf '%s\n' "  $0 install --ethernet en5,en7 --wifi en0"
    printf '%s\n' "  $0 reinstall -e en5 -w en0 --log-dir /var/log"
    printf '%s\n' "  $0 uninstall"
}

fail() {
    exit_code=${2:-1}
    printf '%s\n' "Error: $1" >&2
    exit "$exit_code"
}

usage_error() {
    printf '%s\n' "Error: $1" >&2
    printf '%s\n' "Use --help for usage." >&2
    exit 2
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "This script must be run as root. Please use sudo or run as root user."
    fi
}

installation_exists() {
    [ -f "$SCRIPT_PATH" ] || [ -f "$PLIST_PATH" ]
}

stdin_is_tty() {
    [ -t 0 ]
}

prompt() {
    var_name=$1
    prompt_text=$2

    if ! stdin_is_tty; then
        fail "$prompt_text"
    fi

    printf '%s' "$prompt_text"
    # shellcheck disable=SC2034
    read -r value
    eval "$var_name=\$value"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        install | reinstall | uninstall)
            if [ -n "$ACTION" ]; then
                usage_error "Multiple actions provided."
            fi
            ACTION=$1
            ;;
        -e | --ethernet)
            [ "$#" -ge 2 ] || usage_error "Missing value for $1."
            ETHERNET_INTERFACES=$2
            shift
            ;;
        -w | --wifi)
            [ "$#" -ge 2 ] || usage_error "Missing value for $1."
            WIFI_INTERFACE=$2
            shift
            ;;
        -l | --log-dir)
            [ "$#" -ge 2 ] || usage_error "Missing value for $1."
            LOG_DIR=$2
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            usage_error "Unknown argument: $1."
            ;;
        esac
        shift
    done

    [ "$#" -eq 0 ] || usage_error "Unexpected extra arguments: $*"
}

render_template() {
    template_path=$1
    destination_path=$2

    awk \
        -v ethernet_interfaces="$ETHERNET_INTERFACES" \
        -v wifi_interface="$WIFI_INTERFACE" \
        -v script_path="$SCRIPT_PATH" \
        -v log_dir="$LOG_DIR" \
        '{
            gsub(/__ETHERNET_INTERFACES__/, ethernet_interfaces)
            gsub(/__WIFI_INTERFACE__/, wifi_interface)
            gsub(/__SCRIPT_PATH__/, script_path)
            gsub(/__LOG_DIR__/, log_dir)
            print
        }' "$template_path" >"$destination_path"
}

process_ethernet_interfaces() {
    printf '%s\n' "Processing Ethernet interfaces..."
    valid_interfaces=""

    for interface in $(printf '%s' "$ETHERNET_INTERFACES" | tr ',' '\n'); do
        interface=$(printf '%s' "$interface" | xargs)
        if validate_interface "$interface"; then
            if [ -n "$valid_interfaces" ]; then
                valid_interfaces="${valid_interfaces},${interface}"
            else
                valid_interfaces=$interface
            fi
        fi
    done

    if [ -z "$valid_interfaces" ]; then
        printf '%s\n' "No valid Ethernet interfaces detected."
        return 1
    fi

    ETHERNET_INTERFACES=$valid_interfaces
    printf '%s\n' "Valid Ethernet Interfaces: ${ETHERNET_INTERFACES}"
}

collect_install_config() {
    printf '%s\n' "Detecting network interfaces..."
    networksetup -listallhardwareports

    if [ -z "$ETHERNET_INTERFACES" ]; then
        prompt ETHERNET_INTERFACES "Enter the list of Ethernet interfaces (comma-separated, e.g., en5,en7): "
    fi

    process_ethernet_interfaces

    while :; do
        if [ -z "$WIFI_INTERFACE" ]; then
            prompt WIFI_INTERFACE "Enter the name of the Wi-Fi interface (e.g., en0): "
        fi

        if validate_interface "$WIFI_INTERFACE"; then
            break
        fi

        WIFI_INTERFACE=""
    done

    printf '%s\n' "Ethernet Interfaces: $ETHERNET_INTERFACES"
    printf '%s\n' "Wi-Fi Interface: $WIFI_INTERFACE"
}

create_script() {
    printf '%s\n' "Creating network management script..."
    render_template "$SCRIPT_TEMPLATE_PATH" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    printf '%s\n' "Network management script created at $SCRIPT_PATH"
}

create_plist() {
    printf '%s\n' "Creating LaunchDaemon plist..."
    render_template "$PLIST_TEMPLATE_PATH" "$PLIST_PATH"
    chmod 644 "$PLIST_PATH"
    printf '%s\n' "LaunchDaemon plist created at $PLIST_PATH"
}

load_daemon() {
    printf '%s\n' "Loading the LaunchDaemon..."
    if launchctl list | grep -q "com.user.netintmgr"; then
        printf '%s\n' "LaunchDaemon is already loaded. Unloading first..."
        launchctl unload "$PLIST_PATH"
    fi
    launchctl load "$PLIST_PATH"
    printf '%s\n' "LaunchDaemon loaded."
}

uninstall() {
    printf '%s\n' "Unloading and removing the LaunchDaemon and script..."
    if launchctl list | grep -q "com.user.netintmgr"; then
        launchctl unload "$PLIST_PATH"
        printf '%s\n' "LaunchDaemon unloaded."
    fi
    rm -f "$PLIST_PATH"
    printf '%s\n' "LaunchDaemon plist removed."
    rm -f "$SCRIPT_PATH"
    printf '%s\n' "Network management script removed."
}

choose_action() {
    if installation_exists; then
        prompt ACTION "Existing installation detected. Choose an action (reinstall/uninstall): "
    else
        prompt ACTION "Choose an action (install/uninstall): "
    fi
}

run_install() {
    if installation_exists; then
        fail "Existing installation detected. Use 'reinstall' or 'uninstall' instead."
    fi

    collect_install_config
    create_script
    create_plist
    load_daemon
    printf '%s\n' "Installation complete. The system will now manage network interfaces based on connection status."
}

run_reinstall() {
    if ! installation_exists; then
        fail "No existing installation detected. Use 'install' instead."
    fi

    collect_install_config
    uninstall
    create_script
    create_plist
    load_daemon
    printf '%s\n' "Reinstallation complete. The system will now manage network interfaces based on connection status."
}

main() {
    parse_args "$@"
    require_root
    validate_templates

    if [ -z "$ACTION" ]; then
        choose_action
    fi

    case "$ACTION" in
    install)
        run_install
        ;;
    reinstall)
        run_reinstall
        ;;
    uninstall)
        uninstall
        printf '%s\n' "Uninstallation complete. The system will no longer manage network interfaces."
        ;;
    *)
        usage_error "Invalid action: $ACTION."
        ;;
    esac
}

main "$@"
