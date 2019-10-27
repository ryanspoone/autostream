#!/bin/bash

##############################################################################
#  system_info.sh - This script handles the gathering the system information
##############################################################################

# The default way stream is compiled, it operates on a array of
# 2,000,000 elements taking up approximately 46MB of RAM.  If the
# total amount of processor cache on your system exceeds this amount,
# that means more of the data will fit in cache than intended, and
# the results will be inflated.  Accordingly, this cache size is
# estimated (in a way that only works on Linux), and the size of
# the array used is increased to be 10X as large as that total.
# The STREAM source code itself suggests a 4X multiplier should
# be enough.
STREAM_MIN=10000000
export STREAM_MIN

# Limit the maximum array sized used so that the data structure fits
# into a memory block without overflow.  This makes for about 3GB
# of memory just for the main array, plus some other structures,
# and just fits on most 64-bit systems.  A lower limit may
# be needed on some systems.
MAX_ARRAY_SIZE=130000000
export MAX_ARRAY_SIZE


##############################################################################
# Will display make, type, and model number
# ARM64 X-Gene1 Example: AArch64 Processor rev 0 (aarch64)
# Intel Example: Intel(R) Xeon(R) CPU D-1540 @ 2.00GHz
# Power8 Example: ppc64le
##############################################################################
function getCPU {
  local arch

  CPU=$(grep -m 1 'model name' /proc/cpuinfo | sed 's/model name\s*\:\s*//g;s/(R)//g;s/ @.*//g;s/CPU //g;s/Genuine //g')

  if [ -z "$CPU" ]; then
    CPU=$(lscpu | grep -m 1 "Model name:" | sed 's/Model name:\s*//g;s/(R)//g;s/ @.*//g;s/CPU //g;s/Genuine //g')
  fi

  if [ -z "$CPU" ]; then
    CPU=$(lscpu | grep -m 1 "CPU:" | sed 's/CPU:\s*//g;s/(R)//g;s/ @.*//g;s/CPU //g;s/Genuine //g')
  fi

  if [ -z "$CPU" ]; then
    arch=$(lscpu | grep -m 1 "Architecture:" | sed 's/Architecture:\s*//g;s/x86_//;s/i[3-6]86/32/')

    if [[ $arch == *'aarch64'* || $arch == *'arm'* ]]; then
      CPU='Unknown ARM'
    elif [[ $arch == *'ppc'* ]]; then
      CPU='Unknown PowerPC'
    elif [[ $arch == *'x86_64'* || $arch == *'32'* ]]; then
      CPU='Unknown Intel'
    else
      CPU='Unknown CPU'
    fi
  fi

  export CPU
}


##############################################################################
# Get OS and version
# Example OS: Ubuntu
# Example VER: 14.04
##############################################################################
function getOS {
  if [ -f /etc/lsb-release ]; then
    # shellcheck disable=SC1091,SC1090
    source /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS='Debian'
    VER=$(cat /etc/debian_version)
  elif [ -f /etc/redhat-release ]; then
    OS='Redhat'
    VER=$(cat /etc/redhat-release)
  else
    OS=$(uname -s)
    VER=$(uname -r)
  fi

  export OS
  export VER
}


##############################################################################
# Detect os architecture, os distribution, and os version
# Displays bits, either 64 or 32
##############################################################################
function getArch {
  ARCH=$(lscpu | grep -m 1 "Architecture:" | sed 's/Architecture:\s*//g;s/x86_//;s/i[3-6]86/32/')

  # If it is an ARM system
  if [[ $ARCH == *'arm'* ]]; then
    # Get the ARM version number
    ARM_V=$(echo "$ARCH" | sed 's/armv//g' | head -c1)
    # If ARMv8 or greater, set to 62 bit
    if [[ "$ARM_V" -ge 8 ]]; then
      ARCH='64'
    else
      ARCH='32'
    fi
  fi
  if [[ $ARCH == *'aarch64'* || $ARCH == *'ppc64le'* ]]; then
    ARCH='64'
  fi

  export ARCH
}


##############################################################################
# Virtual cores / logical cores / threads
##############################################################################
function getThreads {
  if hash lscpu &>/dev/null; then
    PHYSICAL_PROCESSORS=$(lscpu | grep -m 1 "Socket(s):" | sed 's/Socket(s):\s*//g')
    THREADS_PER_CORE=$(lscpu | grep -m 1 "Thread(s) per core:" | sed 's/Thread(s) per core:\s*//g')
    CORES=$(lscpu | grep -m 1 "Core(s) per socket:" | sed 's/Core(s) per socket:\s*//g')
  else
    echo
    echo -n "How many threads per core? "
    read -r THREADS_PER_CORE
    echo
    echo
    echo -n "How many sockets (physical processors)? "
    read -r PHYSICAL_PROCESSORS
    echo
    echo
    echo -n "How many cores per socket? "
    read -r CORES
    echo
  fi

  TOTAL_CORES=$((PHYSICAL_PROCESSORS * CORES))
  LOGICAL_CORES=$((THREADS_PER_CORE * TOTAL_CORES))

  export PHYSICAL_PROCESSORS
  export THREADS_PER_CORE
  export CORES
  export TOTAL_CORES
  export LOGICAL_CORES
}


############################################################
# Get the machine's RAM amount
############################################################
function getMachineRAM {
  local all_dimm_sizes
  unset RAM_GB

  if hash lshw &>/dev/null; then
    all_dimm_sizes=($(lshw -class memory | awk '/bank/ {seen = 1} seen {print}' | grep size | sed 's/\s*size://g;s/GiB//g'))

    for i in "${all_dimm_sizes[@]}"; do
      if [[ "$i" != *'MiB'* ]] && [[ "$i" != *'KiB'* ]]; then
        let RAM_GB+=$i
      fi
    done

    if [[ "$RAM_GB" =~ [a-zA-Z]+ ]]; then
      unset RAM_GB
    elif [ ! -z "$RAM_GB" ]; then
      # convert using 1024 instead of 1000 because it's in GigaByte
      RAM_KB=$((RAM_GB * 1024 * 1024))
      RAM_B=$((RAM_GB * 1024 * 1024 * 1024))
    fi
  else
    # Get RAM in KB
    RAM_KB=$(grep -m 1 "MemTotal: " /proc/meminfo | sed "s/MemTotal:\s*//g;s/kB//g" | tr -d "\t\n\r[:space:]")

    if [ ! -z "$RAM_KB" ]; then
      # convert using 1000 instead of 1024 because it's in kilo bits
      RAM_GB=$((RAM_KB / 1000 / 1000))
      RAM_B=$((RAM_KB * 1000))
    fi
  fi

  if [[ "$RAM_B" =~ [a-zA-Z]+ ]] || [[ "$RAM_KB" =~ [a-zA-Z]+ ]] || [[ "$RAM_GB" =~ [a-zA-Z]+ ]]; then
    echo
    echo "ERROR: Memory string contains $?"
    echo
    unset RAM_B
  fi

  if [ -z "$RAM_B" ]; then
    echo
    echo -n "What is the total amount of RAM (in GigaBytes [GB])? "
    read -r RAM_GB
    echo
    RAM_KB=$((RAM_GB * 1024 * 1024))
    RAM_B=$((RAM_GB * 1024 * 1024 * 1024))
  fi

  export RAM_KB
  export RAM_GB
  export RAM_B
}


############################################################
# Get Cache
############################################################
function getCache {
  local level_one_instruction
  local level_one_data
  local total_cache_kb
  local level_two
  local level_three

  cd "$AUTO_SRM_DIR" || exit

  total_cache_kb=0

  if hash lscpu &>/dev/null; then

    # L1 data cache
    level_one_data=$(lscpu | grep "L1d cache" | sed 's/L1d cache:\s*//g' | tr -d " \t\r\n")

    if [[ "$level_one_data" != "" ]]; then
      # K to KB
      if [[ "$level_one_data" == *"K" ]]; then
        # shellcheck disable=SC2116
        level_one_data=$(echo "${level_one_data//K/}")
      fi
    else
      level_one_data=""
    fi

    # L1 instruction cache
    level_one_instruction=$(lscpu | grep "L1i cache" | sed 's/L1i cache:\s*//g' | tr -d " \t\r\n")

    if [[ "$level_one_instruction" != "" ]]; then
      # K to KB
      if [[ "$level_one_instruction" == *"K" ]]; then
        # shellcheck disable=SC2116
        level_one_instruction=$(echo "${level_one_instruction//K/}")
      fi
    else
      level_one_instruction=""
    fi
  fi

  # L2 cache
  level_two=$(lscpu | grep "L2 cache" | sed 's/L2 cache:\s*//g' | tr -d " \t\r\n")

  if [[ "$level_two" != "" ]]; then
    # K to KB
    if [[ "$level_two" == *"K" ]]; then
      # shellcheck disable=SC2116
      level_two=$(echo "${level_two//K/}")
    elif  [[ "$level_two" == *"M" ]]; then
      # shellcheck disable=SC2116
      level_two=$(echo "${level_two//M/}")
      level_two=$((level_two * 1024))
    fi
  else
    level_two=0
  fi

  # L3 cache
  level_three=$(lscpu | grep "L3 cache" | sed 's/L3 cache:\s*//g' | tr -d " \t\r\n")

  if [[ "$level_three" != "" ]]; then
    # K to KB
    if [[ "$level_three" == *"K" ]]; then
      # shellcheck disable=SC2116
      level_three=$(echo "${level_three//K/}")
    elif  [[ "$level_three" == *"M" ]]; then
      # shellcheck disable=SC2116
      level_three=$(echo "${level_three//M/}")
      level_three=$((level_three * 1024))
    fi
  else
    level_three=0
  fi

  if [ -z "$level_one_instruction" ]; then
    echo
    echo "We cannot determine the cache size."
    echo
    echo -n "What is the Level 1 Instruction cache size (in KB)? "
    read -r level_one_instruction
  fi

  if [ -z "$level_one_data" ]; then
    echo
    echo "We cannot determine the cache size."
    echo
    echo -n "What is the Level 1 Data cache size (in KB)? "
    read -r level_one_data
    echo
  fi

  if [ -z "$level_two" ]; then
    echo
    echo "We cannot determine the cache size."
    echo
    echo -n "What is the Level 2 cache size (in KB)? "
    read -r level_two
    echo
  fi

  if [ -z "$level_three" ]; then
    echo
    echo "We cannot determine the cache size."
    echo
    echo -n "What is the Level 3 cache size (in KB)? "
    read -r level_three
    echo
  fi


  for cpu in /sys/devices/system/cpu/cpu*; do
    if [[ $cpu != "/sys/devices/system/cpu/cpuidle" ]]; then
      ((total_cache_kb = total_cache_kb + level_one_data + level_one_instruction + level_two + level_three))
    fi
  done


  # to Bytes
  ((TOTAL_CACHE = total_cache_kb * 1024))

  export TOTAL_CACHE
}


##############################################################################
#
#  'STREAM_ARRAY_SIZE' to meet *both* of the following
#  criteria:
#
#  (a) Each array must be at least 4 times the size of the
#      available cache memory. I don't worry about the
#      difference between 10^6 and 2^20, so in practice the
#      minimum array size is about 3.8 times the cache size.
#
#      Example 1: One Xeon E3 with 8 MB L3 cache
#      STREAM_ARRAY_SIZE should be >= 4 million, giving an
#      array size of 30.5 MB and a total memory requirement
#      of 91.5 MB.
#
#      Example 2: Two Xeon E5's with 20 MB L3 cache each
#      (using OpenMP) STREAM_ARRAY_SIZE should be >= 20
#      million, giving an array size of 153 MB and a
#      total memory requirement of 458 MB.
#
#  (b) The size should be large enough so that the 'timing calibration'
#      output by the program is at least 20 clock-ticks.
#
#      Example: most versions of Windows have a 10
#      millisecond timer granularity.  20 "ticks" at 10
#      ms/tic is 200 milliseconds. If the chip is capable of
#      10 GB/s, it moves 2 GB in 200 msec. This means the
#      each array must be at least 1 GB, or 128M elements.
#
##############################################################################
##############################################################################
#
# setStreamArraySize determines how large the array stream
# runs against needs to be to avoid caching effects.
#
###############################################################################
function setStreamArraySize {
  local BYTES_PER_ARRAY_ENTRY

  # We know that every 1 million array entries in stream produces approximately
  # 22 million bytes (not megabytes!) of data.  Round that down to make more
  # entries required.  And then increase the estimated sum of cache sizes by
  # an order of magnitude to compute how large the array should be, to make
  # sure cache effects are minimized.

  BYTES_PER_ARRAY_ENTRY=22
  ((STREAM_ARRAY_SIZE = 10 * TOTAL_CACHE / BYTES_PER_ARRAY_ENTRY))

  if [ $STREAM_ARRAY_SIZE -lt $STREAM_MIN ] ; then
    STREAM_ARRAY_SIZE=$STREAM_MIN
  fi

  # The array sizing code will overflow 32 bits on systems with many
  # processors having lots of cache.
  #
  # Warn about this issue, and provide a way to clamp the upper value to a smaller
  # maximum size to try and avoid this error.  130,000,000 makes for approximately
  # a 3GB array.  The large memory model compiler option will avoid this issue
  # if a gcc version that supports it is available.
  if [ $STREAM_ARRAY_SIZE -gt $MAX_ARRAY_SIZE ] ; then
    #
    # Size clamp code
    #
    # Uncomment this line if stream-scaling fails to work on your system with
    # "relocation truncated to fit" errors.  Note that results generated in
    # this case may not be reliable.  Be suspicious of them if the speed
    # results at the upper-end of the processor count seem extremely large
    # relative to similar systems.

    #STREAM_ARRAY_SIZE=$MAX_ARRAY_SIZE

    MAX_ARRAY_SIZE_WARNING=true
    export MAX_ARRAY_SIZE_WARNING
  fi

  # Given the sizing above uses a factor of 10X cache size, this reduced size
  # might still be large enough for current generation procesors up to the 48 core
  # range.  For example, a system containing 8 Intel Xeon L7555 processors with
  # 4 cores having 24576 KB cache each will suggest:
  #
  # Total CPU system cache: 814743552 bytes
  # Computed minimum array elements needed: 370337978
  #
  # So using 130,000,000 instead of 370,337,978 still be an array >3X the
  # size of the cache sum in this case.  Really large systems with >48 processors
  # might overflow this still.

  STREAM_ARRAY_SIZE=$STREAM_ARRAY_SIZE
  export STREAM_ARRAY_SIZE
}


############################################################
# Get the appropriate GCC flags
############################################################
function getCompilerInfo {
  local march_cpu
  local cpu_lower

  march_cpu='march'
  cpu_lower=$(echo -n "$CPU" | tr '[:upper:]' '[:lower:]')

  GCC_VER=$(gcc --version | sed -rn 's/gcc\s\(.*\)\s([0-9]*\.[0-9]*\.[0-9]*)/\1/p')

  if [[ $OVERRIDE_MARCH == false ]]; then
    if [[ "$cpu_lower" == *'power'* || "$cpu_lower" == *'ppc'* ]]; then
      march_cpu='mcpu'
    fi

    MARCH=$(gcc -"$march_cpu"=native -Q --help=target 2> /dev/null | grep '\-march=' | head -n 1 | sed "s/-march=//g;s/ARCH//g;s/arch//g" | tr -d "\t\n\r[:space:]")

    # shellcheck disable=SC2181
    if [ $? -ne 0 ] || [[ "$MARCH" == *"native"* ]] || [ -z "$MARCH" ]; then
      echo
      echo "The system couldn't detect the compiler machine architecture."
      echo
      echo -n "What is the appropriate '-march=' flag (answer 'native' if you do not know)? "
      read -r MARCH
      echo
    fi

    MTUNE=$(gcc -"$march_cpu"="$MARCH" -mtune=native -Q --help=target 2> /dev/null | grep '\-mtune=' | head -n 1 | sed "s/-mtune=//g;s/CPU//g;s/cpu//g" | tr -d "\t\n\r[:space:]")

    # shellcheck disable=SC2181
    if [ $? -ne 0 ] || [[ "$MTUNE" == *"native"* ]] || [ -z "$MTUNE" ]; then
      echo
      echo "The system couldn't detect the compiler machine tuning."
      echo
      echo -n "What is the appropriate '-mtune=' flag (answer 'native' if you do not know)? "
      read -r MTUNE
      echo
    fi

    export MARCH
    export MTUNE
  fi

  export GCC_VER
}


############################################################
# Function to get all system information
############################################################
function getSystemInfo {
  getCPU
  getOS
  getArch
  getThreads
  getMachineRAM
  getCache
  setStreamArraySize
  getCompilerInfo
}
