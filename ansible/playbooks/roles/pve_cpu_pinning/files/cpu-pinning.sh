#!/bin/bash
VMID=$1
PHASE=$2

if [ "$PHASE" == "post-start" ]; then
    # Get the PID of the VM
    MAIN_PID=$(cat /var/run/qemu-server/$VMID.pid)

    # Target physical cores (Matches your previous intent)
    CORES=(4 5 6 7)

    # Find TIDs for threads named "CPU 0/KVM", "CPU 1/KVM", etc.
    # We use a loop to ensure vCPU 0 goes to CORES[0], vCPU 1 to CORES[1]
    for i in {0..3}; do
        TID=$(ps -T -p $MAIN_PID -o tid,comm | grep -i "CPU $i/KVM" | awk '{print $1}')
        if [ ! -z "$TID" ]; then
            taskset -pc ${CORES[$i]} $TID
        fi
    done
fi