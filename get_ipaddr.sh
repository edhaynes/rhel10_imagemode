#!/bin/bash
MAC="52:54:0:12:34:56"

# 1. Try the DHCP Lease file (Most reliable for vmnet-shared)
# We search the plist for the MAC and grab the IP address assigned to it
IP=$(virt-top -n 1 2>/dev/null | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b") # Backup check

# The "Golden" command for macOS DHCP leases:
IP=$(grep -B 1 "01:$(echo $MAC | tr '[:upper:]' '[:lower:]')" /var/db/dhcpd_leases | grep "ip_address" | awk -F'[<>]' '{print $3}')

# 2. Fallback to ARP if DHCP file is empty
if [ -z "$IP" ]; then
    IP=$(arp -an | grep -i "$MAC" | awk '{print $2}' | tr -d '()')
fi

if [ -z "$IP" ]; then
    echo "❌ Could not find IP. Is the VM finished booting?"
else
    echo "✅ Found IP: $IP"
fi
