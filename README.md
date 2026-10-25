# System Resource Monitor

A Bash script for monitoring system resources on Linux.

## Features
- Records the current timestamp.
- Displays system uptime.
- Records memory usage with `free -h`.
- Records root filesystem usage with `df -h /`.
- Appends results to `monitor.log`.

## Requirements
- Linux
- Bash

## Usage

Make the script executable:

    chmod +x script.sh

Run with the default 5-second interval:

    ./script.sh

Set a custom interval in seconds:

    ./script.sh 10

Press Ctrl+C to stop monitoring.

The generated `monitor.log` file contains the collected system information.
