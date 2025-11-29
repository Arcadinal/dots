#!/usr/bin/env bash
# Wofi-compatible Bluetooth Manager with auto-pairing for BR/EDR and LE devices
# Dependencies: bluez-utils, wofi, expect

divider="---------"
goback="Back"

# Check if controller is powered on
power_on() {
    bluetoothctl show | grep -q "Powered: yes"
}

toggle_power() {
    if power_on; then
        bluetoothctl power off
    else
        if rfkill list bluetooth | grep -q 'Soft blocked: yes'; then
            rfkill unblock bluetooth && sleep 1
        fi
        bluetoothctl power on
    fi
    show_menu
}

scan_on() {
    bluetoothctl show | grep -q "Discovering: yes"
}

toggle_scan() {
    if scan_on; then
        bluetoothctl scan off
    else
        bluetoothctl scan on &
        echo "Scanning for devices..."
        sleep 5
        bluetoothctl scan off
    fi
    show_menu
}

pairable_on() {
    bluetoothctl show | grep -q "Pairable: yes"
}

toggle_pairable() {
    if pairable_on; then
        bluetoothctl pairable off
    else
        bluetoothctl pairable on
    fi
    show_menu
}

discoverable_on() {
    bluetoothctl show | grep -q "Discoverable: yes"
}

toggle_discoverable() {
    if discoverable_on; then
        bluetoothctl discoverable off
    else
        bluetoothctl discoverable on
    fi
    show_menu
}

device_connected() {
    bluetoothctl info "$1" | grep -q "Connected: yes"
}

device_paired() {
    bluetoothctl info "$1" | grep -q "Paired: yes"
}

device_trusted() {
    bluetoothctl info "$1" | grep -q "Trusted: yes"
}

# Auto-pair using expect to handle PIN/SSP
auto_pair() {
    mac=$1
    pin=${2:-0000}  # default PIN
    expect -c "
        spawn bluetoothctl
        expect \"> \"
        send \"pair $mac\r\"
        expect {
            \"[agent] Enter PIN code:\" {
                send \"$pin\r\"
                exp_continue
            }
            \"[agent] Confirm passkey\" {
                send \"yes\r\"
                exp_continue
            }
            eof
        }
    "
    bluetoothctl trust "$mac" &>/dev/null
    bluetoothctl connect "$mac" &>/dev/null
}

toggle_connection() {
    if device_connected "$1"; then
        bluetoothctl disconnect "$1"
    else
        auto_pair "$1"
    fi
    device_menu "$1"
}

toggle_paired() {
    if device_paired "$1"; then
        bluetoothctl remove "$1"
    else
        auto_pair "$1"
    fi
    device_menu "$1"
}

toggle_trust() {
    if device_trusted "$1"; then
        bluetoothctl untrust "$1"
    else
        bluetoothctl trust "$1"
    fi
    device_menu "$1"
}

print_status() {
    if power_on; then
        printf ''
        mapfile -t paired < <(bluetoothctl paired-devices | awk '{print $2}')
        counter=0
        for dev in "${paired[@]}"; do
            if device_connected "$dev"; then
                alias=$(bluetoothctl info "$dev" | grep "Alias" | cut -d ' ' -f 2-)
                if [ $counter -gt 0 ]; then
                    printf ", %s" "$alias"
                else
                    printf " %s" "$alias"
                fi
                ((counter++))
            fi
        done
        printf "\n"
    else
        echo ""
    fi
}

device_menu() {
    mac=$1
    alias=$(bluetoothctl info "$mac" | grep "Alias" | cut -d ' ' -f 2-)
    conn="Connected: $(device_connected "$mac" && echo yes || echo no)"
    paired="Paired: $(device_paired "$mac" && echo yes || echo no)"
    trusted="Trusted: $(device_trusted "$mac" && echo yes || echo no)"

    options="$conn\n$paired\n$trusted\n$divider\n$goback\nExit"
    chosen=$(echo -e "$options" | wofi -d -p "$alias")
    case "$chosen" in
        "$conn") toggle_connection "$mac" ;;
        "$paired") toggle_paired "$mac" ;;
        "$trusted") toggle_trust "$mac" ;;
        "$goback") show_menu ;;
    esac
}

scan_and_add_device() {
    echo "Scanning for new devices..."
    bluetoothctl scan on &
    sleep 5
    bluetoothctl scan off
    devices=$(bluetoothctl devices | awk '{print $2, substr($0,index($0,$3))}')
    if [ -z "$devices" ]; then
        wofi -d -p "No devices found" <<< ""
        show_menu
    fi
    chosen=$(echo -e "$devices" | wofi -d -p "Select Device")
    mac=$(echo "$chosen" | awk '{print $1}')
    [ -n "$mac" ] && auto_pair "$mac"
    show_menu
}

show_menu() {
    if power_on; then
        power="Power: on"
        scan="Scan: $(scan_on && echo on || echo off)"
        pairable="Pairable: $(pairable_on && echo on || echo off)"
        discoverable="Discoverable: $(discoverable_on && echo on || echo off)"
        devices=$(bluetoothctl devices | awk '{print substr($0,index($0,$3))}')
        options="$devices\n$divider\n$power\n$scan\n$pairable\n$discoverable\nAdd new device\nExit"
    else
        power="Power: off"
        options="$power\nExit"
    fi

    chosen=$(echo -e "$options" | wofi -d -p "Bluetooth")
    case "$chosen" in
        "$power") toggle_power ;;
        "$scan") toggle_scan ;;
        "$pairable") toggle_pairable ;;
        "$discoverable") toggle_discoverable ;;
        "Add new device") scan_and_add_device ;;
        *) 
            mac=$(bluetoothctl devices | grep "$chosen" | awk '{print $2}')
            [ -n "$mac" ] && device_menu "$mac"
            ;;
    esac
}

# Run script
case "$1" in
    --status) print_status ;;
    *) show_menu ;;
esac
