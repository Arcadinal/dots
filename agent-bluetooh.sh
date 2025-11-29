#!/usr/bin/env bash

bluetoothctl power on
bluetoothctl agent KeyboardDisplay
bluetoothctl default-agent

# Keep running
while true; do sleep 3600; done
