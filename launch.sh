#!/bin/bash

# 1. Define your VM settings
MAC_ADDR="52:54:0:12:34:56"
QEMU_CMD="sudo qemu-system-aarch64 \
  -m 2G -smp 2 -cpu host -M virt,highmem=on -accel hvf \
  -drive if=pflash,format=raw,readonly=on,file=edk2-aarch64-code.fd \
  -drive if=virtio,format=qcow2,file=disk.qcow2 \
  -netdev vmnet-shared,id=net0 \
  -device virtio-net-pci,netdev=net0,mac=$MAC_ADDR \
  -nographic"

# 2. Launch QEMU in a new Terminal window
echo "🚀 Launching VM in a new window..."
osascript -e "tell app \"Terminal\" to do script \"cd $(pwd) && $QEMU_CMD\""

# 3. Wait and find the IP address
echo "🔍 Waiting for VM to acquire an IP (this may take 20-30 seconds)..."
IP=""
while [ -z "$IP" ]; do
    # Scrape the ARP table for the MAC address
    IP=$(arp -an | grep -i "$MAC_ADDR" | awk '{print $2}' | tr -d '()')
    sleep 2
done

echo "✅ VM is up! IP Address: $IP"
echo "🔗 To run Ansible: ansible-playbook -i $IP, playbook.yml"
