#!/bin/bash

##############################################################################
#  gcc_setup.sh - This script handles the installation of needed prerequisites
#  and STREAM for GCC.
#
##############################################################################


############################################################
# Install prerequisites if needed
############################################################
function gccPrerequisites {
  echo
  echo 'Checking if prerequisites need to be installed and installing if necessary...'
  echo

  # If apt-get is installed
  if hash apt-get &>/dev/null; then
    sudo -E apt-get update -y

    # make sure that aptitude is installed
    # "aptitude safe-upgrade" will upgrade the kernel
    if hash aptitude &>/dev/null; then
      sudo -E aptitude safe-upgrade
    else
      sudo -E apt-get aptitude -y
      sudo -E aptitude safe-upgrade
    fi

    sudo -E apt-get build-dep gcc -y
    sudo -E apt-get install gcc -y

    sudo -E apt-get install build-essential -y
    sudo -E apt-get install util-linux -y
    # double check
    sudo -E apt-get install openmpi-bin -y
    sudo -E apt-get install openmpi-common -y
    sudo -E apt-get install libopenmpi-dbg -y

    if ! sudo -E apt-get install libopenmpi-dbg; then
      sudo -E apt-get install libopenmpi1.6 -y
      sudo -E apt-get install libopenmpi1.6-dbg -y
    fi

    sudo -E apt-get install libopenmpi-dev -y

  # If yum is installed
  elif hash yum &>/dev/null; then
    sudo -E yum check-update -y
    sudo -E yum update -y
    sudo -E yum groupinstall "Development Tools" "Development Libraries" -y
    sudo -E yum-builddep gcc -y
    sudo -E yum install gcc -y
    sudo -E yum install util-linux -y
    sudo -E yum install openmpi -y
    sudo -E yum install openmpi-devel -y

  # if zypper is installed
  elif hash zypper &>/dev/null; then
    sudo -E zypper -n install -t pattern devel_basis
    sudo -E zypper -n install gcc
    sudo -E zypper -n install openmpi
    sudo -E zypper -n install openmpi-devel
    sudo -E zypper -n install util-linux

  # If no supported package manager or no package manager
  else
    echo
    echo "*************************************************************************"
    echo "We couldn't find the appropriate package manager for your system. Please"
    echo "try manually installing the following and rerun this script:"
    echo
    echo "gcc"
    echo "openmpi"
    echo "*************************************************************************"
    echo
  fi
  echo
}


############################################################
# Rebuilding and installing STREAM
############################################################
function gccRebuild {
  echo
  echo '=== Rebuilding STREAM ==='
  echo

  if [ -d "$AUTO_SRM_DIR/gcc_src" ]; then
    rm -rf "$AUTO_SRM_DIR/gcc_src"
  fi

  gccBuild
}


############################################################
# Setup function to build and install STREAM if needed
############################################################
function gccBuild {
  local cpu_lower
  local march_cpu
  local current_stream_array_size

  march_cpu='march'


  cpu_lower=$(echo "$CPU" | tr '[:upper:]' '[:lower:]')

  if [[ $cpu_lower == *'power'* || $cpu_lower == *'ppc'* ]]; then
    march_cpu='mcpu'
  fi

  echo
  echo "=== Check and build stream ==="
  echo

  cd "$AUTO_SRM_DIR/gcc_src" || exit

  if [ ! -f "$AUTO_SRM_DIR/gcc_src/stream_omp.c" ]; then
    wget --no-check-certificate "https://www.cs.virginia.edu/stream/FTP/Code/Versions/stream_omp.c"
  fi

  if [ -f "$AUTO_SRM_DIR/gcc_src/stream_omp.c" ]; then

    cd "$AUTO_SRM_DIR/gcc_src/" || exit

    # Set STREAM_ARRAY_SIZE in stream_omp.c
    current_stream_array_size=$(grep '^# define N\s' "$AUTO_SRM_DIR/gcc_src/stream_omp.c" | sed 's/^# define N\s//g')

    if [[ "$current_stream_array_size" != "$STREAM_ARRAY_SIZE" ]]; then
      sed -i "s/^# define N\s*$current_stream_array_size/# define N $STREAM_ARRAY_SIZE/g" "$AUTO_SRM_DIR/gcc_src/stream_omp.c"
    fi

    if [ -z "$MTUNE" ]; then
      gcc -O3 -fopenmp -"$march_cpu"="$MARCH" stream_omp.c -o stream_omp
    else
      gcc -O3 -fopenmp -"$march_cpu"="$MARCH" -mtune="$MTUNE" stream_omp.c -o stream_omp
    fi

    # shellcheck disable=SC2181
    if [ $? -ne 0 ] ; then
      # The most likely way the program will fail to compile is if it's
      # trying to use more memory than will fit on the standard gcc memory
      # model.  Try the large one instead.  This will only work on newer
      # gcc versions (it works on at least>=4.4), so there's no single
      # compile option set here that will support older gcc versions
      # and the large memory model.  Just trying both ways seems both
      # simpler and more definitive than something like checking the
      # gcc version.

      echo
      echo "=== Trying large memory model ==="
      echo "(this can take a while to compile)"
      echo

      # if MTUNE is unset
      if [ -z "$MTUNE" ]; then
        gcc -O3 -fopenmp -"$march_cpu"="$MARCH" stream_omp.c -o stream_omp -mcmodel=large
      else
        gcc -O3 -fopenmp -"$march_cpu"="$MARCH" -mtune="$MTUNE" stream_omp.c -o stream_omp -mcmodel=large
      fi
    fi

    # shellcheck disable=SC2181
    if [ $? -ne 0 ] ; then
      if [[ $MAX_ARRAY_SIZE_WARNING == true ]] ; then
        echo
        echo "Error:  Array size may not fit into a 32-bit structure."
        echo "You may need to uncomment the line in the script labeled"
        echo "and described by the \"Size clamp code\" comments in the"
        echo "system_information.sh script and try again."
        echo
      else
        echo
        echo "Error:  Did not find valid stream program compiled, aborting..."
        echo
      fi

      exit 1
    fi

    sudo chmod +x "stream_omp"
  else
    echo
    echo "No file $AUTO_SRM_DIR/gcc_src/stream_omp.c found. Exiting now." && exit
    exit 1
  fi
  echo
}


function gccRun {
  local core
  local iteration
  local core_id
  local taskset_clean

  taskset_clean="${TASKSET_RANGE//,/and/}"

  if [[ $SCALE == true ]]; then
    core=1
  elif [[ $OVERRIDE_THREADS == true ]]; then
    core="$THREADS"
  else
    core="$LOGICAL_CORES"
  fi

  iteration=1
  core_id=0

  echo
  echo "=== Running STREAM for GCC OMP ==="
  echo

  cd "$AUTO_SRM_DIR/gcc_src/" || exit

  echo
  echo "=== Testing up to $LOGICAL_CORES cores ==="
  echo

  while [[ $core -le $LOGICAL_CORES ]]; do
    export OMP_NUM_THREADS="$core"

    echo "Number of OMP Threads requested = $core"

    while [[ $iteration -le $ITERATIONS ]]; do
      if [[ $TASKSET_ENABLED == true ]]; then
        echo "Taskset range = $TASKSET_RANGE"
        taskset -c "$TASKSET_RANGE" ./stream_omp | tee -a stream_omp_"$OMP_NUM_THREADS"t_taskset_"$taskset_clean".txt | grep -E "Triad"
      elif [[ $TASKSET_AUTO == true ]]; then
        if [ $core_id -eq 0 ]; then
          echo "Taskset range = $core_id"
          taskset -c "$core_id" ./stream_omp | tee -a stream_omp_"$OMP_NUM_THREADS"t_taskset_"$core_id".txt | grep -E "Triad"
        else
          echo "Taskset range = 0-""$core_id"
          taskset -c "0-$core_id" ./stream_omp | tee -a stream_omp_"$OMP_NUM_THREADS"t_taskset_0-"$core_id".txt | grep -E "Triad"
        fi
      else
        ./stream_omp | tee -a stream_omp_"$OMP_NUM_THREADS"t.txt | grep -E "Triad"
      fi
      sleep 10
      ((iteration++))
    done
    iteration=1

    ((core_id++))
    ((core++))
    echo
  done

  echo
  echo "Results can be found at: $AUTO_SRM_DIR/gcc_src/"
  echo
}
