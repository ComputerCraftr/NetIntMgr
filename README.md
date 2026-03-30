# NetIntMgr - Network Interface Manager
This script manages network interfaces to disable Wi-Fi when connected to Ethernet to save power and remove the second default route from the routing tables.

## Usage

```sh
sudo ./install_netintmgr.sh install --ethernet en5,en7 --wifi en0
sudo ./install_netintmgr.sh reinstall --ethernet en5,en7 --wifi en0
sudo ./install_netintmgr.sh uninstall
sudo ./install_netintmgr.sh --help
```

## Command line options

```text
install_netintmgr.sh [install|reinstall|uninstall] [options]

  -e, --ethernet INTERFACES  Comma-separated Ethernet interfaces
  -w, --wifi INTERFACE       Wi-Fi interface
  -l, --log-dir DIR          Log directory for LaunchDaemon output
  -h, --help                 Show help
```

`install` creates the managed script and LaunchDaemon and fails if an installation already exists.

`reinstall` removes the existing installation, then recreates it with the supplied configuration.

`uninstall` removes the managed script and LaunchDaemon.

If you omit `--ethernet` or `--wifi`, the installer falls back to interactive prompts.

## Multiple Ethernet interfaces

The installer supports multiple Ethernet interfaces. Pass them as a comma-separated list:

```sh
sudo ./install_netintmgr.sh install --ethernet en5,en7,en8 --wifi en0
```

At runtime, NetIntMgr disables Wi-Fi when any configured Ethernet interface is active. If none of the configured Ethernet interfaces are active, Wi-Fi is turned back on.
