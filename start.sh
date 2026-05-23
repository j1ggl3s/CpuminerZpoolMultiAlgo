#!/bin/bash

# ==============================================================================
# HELP FUNCTION
# ==============================================================================
# Displays script usage guidelines if the user passes the -h flag or invalid options.
function help {
 echo "Script to perform MultiAlgo CPU mining on Zpool.ca
laurence.baldwin@gmail.com April 2021.
==================================================
-c Coin to be paid in 
-w Wallet address for payments
-h help" 
 exit 1
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================
# Checks command-line flags. 
# -w sets the WALLET variable, -c sets the target payout COIN.
while getopts ':c:w:h' opt; do
    case $opt in
      (h)   help;;
      (w)   WALLET=$OPTARG;;
      (c)   COIN=$OPTARG;;
    esac
done

# ==============================================================================
# DEFAULT SETTINGS
# ==============================================================================
# If the user didn't provide a wallet or coin via flags, use these defaults:
if [  -z "$WALLET" ]; then WALLET="DJhaC9jPxWw2M1iAjSE2dsYaL7a6vcYYg8"; fi
if [  -z "$COIN" ]; then COIN="DGB"; fi 

BMSEC=60     # Duration for each algorithm benchmark (60 seconds)
BMRETRY=5    # Number of times to retry a benchmark if it fails/returns 0

echo "Payments will be sent to $COIN $WALLET"
echo "Starting Benchmarks"

# ==============================================================================
# BENCHMARKING SECTION
# ==============================================================================
# For each algorithm, the script runs the miner in benchmark mode for 60 seconds.
# It redirects errors to standard output (2>&1), throws away standard miner outputs (> /dev/null),
# takes the very last line of text (tail -1), and passes it to 'bc' to convert to Megahashes (MH/s) or Gigahashes (GH/s).
#
# NOTE: If cpuminer crashes, isn't installed, or outputs a blank line, 'tail -1' sends nothing 
# or text to 'bc', which triggers the "(standard_in) 1: syntax error" you are seeing.

# --- Allium ---
#HASH=$(echo "$(/cpuminer-opt/cpuminer -a allium --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
HASH=$(/cpuminer-opt/cpuminer -a allium --benchmark --time-limit=$BMSEC --no-color 2>&1 | awk '/Benchmark:/ {v=$4; u=$5; if(u~/kH/)v*=1000; if(u~/MH/)v*=1000000; if(u~/GH/)v*=1000000000; printf "%.8f\n", v/1000000; found=1; exit} END {if(!found) print "0.00000000"}')
echo "allium $HASH MH/s"
# Creates/appends to the FACTOR variable which Zpool uses to calibrate profitability for your specific CPU.
FACTOR="allium=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH # Clears the variable for the next calculation

# --- Argon2d4096 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a argon2d4096 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "argon2d4096 $HASH MH/s"
FACTOR="$FACTOR,argon2d4096=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Argon2d500 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a argon2d500 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "argon2d500 $HASH MH/s"
FACTOR="$FACTOR,argon2d500=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Binarium Hash v1 (Uses a different miner folder) ---
HASH=$(echo "$(/cpuminer-easy-binarium/cpuminer -a Binarium_hash_v1 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "binarium $HASH MH/s"
FACTOR="$FACTOR,binarium-v1=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- BMW512 (Result divided an extra time by 1000 to measure in GH/s) ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a bmw512 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 /1000" | bc -l | awk '{printf "%.8f", $0}')
echo "bmw512 $HASH GH/s"
FACTOR="$FACTOR,bmw512=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Cpupower (Includes a retry loop because this specific algorithm benchmark is glitchy) ---
for i in {1..$BMRETRY}; do 
  # Note: The loop syntax {1..$BMRETRY} doesn't work natively in standard bash variables, 
  # which means this loop likely only runs once or throws a minor error.
  HASH=$(echo "$(/cpuminer-opt-cpupower/cpuminer -a cpupower --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
  if [ $HASH != "0.00000000" ]; then break; fi # If we get a real speed, break the loop
  echo "cpupower benchmark failed: Attempt $i" 
done
echo "cpupower $HASH KH/s"
FACTOR="$FACTOR,cpupower=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Curvehash (Does live mining to benchmark because internal benchmark is broken) ---
# It mines for 60 seconds, grabs the last accepted share log line, and extracts the speed.
HASH=$(/cpuminer-curvehash/cpuminer -a curvehash -f 0x10000 -o stratum+tcp://curve.na.mine.zpool.ca:4633 --time-limit=$BMSEC -u $WALLET -p c=$COIN  --no-color -q | grep "accepted: " | tail -1  | cut -f7 -d" ")
echo "curve $HASH KH/s"
FACTOR="$FACTOR,curve=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

 #--- Ghostrider ---
for i in {1..$BMRETRY}; do
  HASH=$(echo "$(/cpuminer-gr/cpuminer -a gr --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 " | bc -l | awk '{printf "%.8f", $0}')
  if [ $HASH != "0.00000000" ]; then break; fi
  echo "ghostrider benchmark failed: Attempt $i"
done
echo "ghostrider $HASH KH/s"
FACTOR="$FACTOR,ghostrider=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Keccakc ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a keccakc --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 /1000" | bc -l | awk '{printf "%.8f", $0}')
echo "keccakc $HASH GH/s"
FACTOR="$FACTOR,keccakc=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Lyra2rev3 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a lyra2rev3 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 /1000" | bc -l | awk '{printf "%.8f", $0}')
echo "lyra2v3 $HASH GH/s"
FACTOR="$FACTOR,lyra2v3=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Lyra2z ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a lyra2z --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 /1000" | bc -l | awk '{printf "%.8f", $0}')
echo "lyra2z $HASH GH/s"
FACTOR="$FACTOR,lyra2z=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Lyra2z330 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a lyra2z330 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "lyra2z330 $HASH MH/s"
FACTOR="$FACTOR,lyra2z330=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- M7M ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a m7m --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "m7m $HASH MH/s"
FACTOR="$FACTOR,m7m=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Power2b ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a power2b --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "power2b $HASH KH/s"
FACTOR="$FACTOR,power2b=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Phi2 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a phi2 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "phi2 $HASH MH/s"
FACTOR="$FACTOR,phi2=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- X11gost (Sib) ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a x11gost --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "sib $HASH GH/s"
FACTOR="$FACTOR,sib=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- X14 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a x14 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "x14 $HASH GH/s"
FACTOR="$FACTOR,x14=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- X21s ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a x21s --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "x21s $HASH MH/s"
FACTOR="$FACTOR,x21s=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- X16r ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a x16r --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "x16r $HASH GH/s"
FACTOR="$FACTOR,x16r=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- X25x ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a x25x --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000 / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "x25x $HASH MH/s"
FACTOR="$FACTOR,x25x=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Yescrypt ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a yescrypt --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "yescrypt $HASH KH/s"
FACTOR="$FACTOR,yescrypt=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Yescryptr32 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a yescryptr32 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "yescryptr32 $HASH KH/s"
FACTOR="$FACTOR,yescryptR32=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Yespower ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a yespower --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "yespower $HASH KH/s"
FACTOR="$FACTOR,yespower=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- YespowerIC (Uses specialized IsotopeC miner build; includes buggy benchmark retry loop) ---
for i in {1..$BMRETRY}; do
  HASH=$(echo "$(/isotopec-cpuminer/cpuminer -a yespowerIC --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
  if [ $HASH != "0.00000000" ]; then break; fi
  echo "yespowerIC benchmark failed: Attempt $i"
done
echo "yespowerIC $HASH KH/s"
FACTOR="$FACTOR,yespowerIC=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Yespowerltncg (Uses specialized IsotopeC miner build; includes buggy benchmark retry loop) ---
for i in {1..$BMRETRY}; do
  HASH=$(echo "$(/isotopec-cpuminer/cpuminer -a yespowerltncg --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
  if [ $HASH != "0.00000000" ]; then break; fi
  echo "yespowerltncg  benchmark failed: Attempt $i"
done
echo "yespowerLNC $HASH KH/s"
FACTOR="$FACTOR,yespowerLNC=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# --- Yespowerr16 ---
HASH=$(echo "$(/cpuminer-opt/cpuminer -a yespowerr16 --benchmark --time-limit=$BMSEC 2>&1 > /dev/null | tail -1) / 1000" | bc -l | awk '{printf "%.8f", $0}')
echo "yespowerr16 $HASH KH/s"
FACTOR="$FACTOR,yespowerR16=$(echo $HASH \* 1000 | bc -l | awk '{printf "%.2f", $0}')"
unset HASH

# Print the massive comma-separated string containing your chip's speed values for Zpool.
echo "Factor settings to be used: $FACTOR"


# ==============================================================================
# MAIN MINING LOOP
# ==============================================================================
# An infinite loop (`while true`) that sequences through every single algorithm.
# 
# The flag `-r 0` tells cpuminer to retry infinitely if it disconnects, BUT because 
# these lines run sequentially, standard behavior would mean it hangs on line 1 forever.
# However, Zpool profit-switching relies on the pool forcefully disconnecting you (sending a "clean jobs" close)
# when an algorithm is no longer the most profitable, pushing the script to the next line.
while true; 
do
 /cpuminer-opt/cpuminer -r 0 -a allium -o stratum+tcp://allium.na.mine.zpool.ca:6433 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a argon2d4096 -o stratum+tcp://argon2d4096.na.mine.zpool.ca:4240 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a argon2d500 -o stratum+tcp://argon2d500.na.mine.zpool.ca:4239 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-easy-binarium/cpuminer -r 0 -a Binarium_hash_v1 -o stratum+tcp://binarium-v1.na.mine.zpool.ca:6666 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a bmw512 -o stratum+tcp://bmw512.na.mine.zpool.ca:5787 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt-cpupower/cpuminer -r 0 -a cpupower -o stratum+tcp://cpupower.na.mine.zpool.ca:6240 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-curvehash/cpuminer -r 0 -a curvehash -f 0x10000 -o stratum+tcp://curve.na.mine.zpool.ca:4633 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-gr/cpuminer -r 0 -a gr -o stratum+tcp://ghostrider.na.mine.zpool.ca:5354 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a keccakc -o stratum+tcp://keccakc.na.mine.zpool.ca:5134 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a lyra2rev3 -o stratum+tcp://lyra2v3.na.mine.zpool.ca:4550 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a lyra2z -o stratum+tcp://lyra2z.na.mine.zpool.ca:4553 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a lyra2z330 -o stratum+tcp://lyra2z330.na.mine.zpool.ca:4563 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a m7m -o stratum+tcp://m7m.na.mine.zpool.ca:6033 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN 
 /cpuminer-opt/cpuminer -r 0 -a power2b -o stratum+tcp://power2b.na.mine.zpool.ca:6242 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN 
 /cpuminer-opt/cpuminer -r 0 -a phi2 -o stratum+tcp://phi2.na.mine.zpool.ca:8332 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a x11gost -o stratum+tcp://sib.na.mine.zpool.ca:5033 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a x14 -o stratum+tcp://x14.na.mine.zpool.ca:3933 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a x21s  -o stratum+tcp://x21s.na.mine.zpool.ca:3224-u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a x16r -o stratum+tcp://x16r.na.mine.zpool.ca:3636 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a x25x -o stratum+tcp://x25x.na.mine.zpool.ca:3423 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /cpuminer-opt/cpuminer -r 0 -a yescrypt -o stratum+tcp://yescrypt.na.mine.zpool.ca:6233 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN 
 /cpuminer-opt/cpuminer -r 0 -a yescryptr32 -o stratum+tcp://yescryptr32.na.mine.zpool.ca:6343 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN 
 /cpuminer-opt/cpuminer -r 0 -a yespower -o stratum+tcp://yespower.na.mine.zpool.ca:6234 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN 
 /isotopec-cpuminer/cpuminer -r 0 -a yespowerIC -o stratum+tcp://yespowerIC.na.mine.zpool.ca:6243 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN
 /isotopec-cpuminer/cpuminer -r 0 -a yespowerltncg -o stratum+tcp://yespowerLNC.na.mine.zpool.ca:6245 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN 
 /cpuminer-opt/cpuminer -r 0 -a yespowerr16 -o stratum+tcp://yespowerr16.na.mine.zpool.ca:6534 -u $WALLET -p $HOSTNAME,$FACTOR,c=$COIN

 sleep 5 # Cooldown period before starting the loop over again if the whole pool infrastructure drops.
done
