#!/bin/bash

# for consistent date formatting
function date_ () {
  TZ="UTC" \date +"%a %b %d %T UTC %Y"
}

# declare a function to wait for pid on each line of an input file
function wait_on_processes () {

    while IFS="" read -r p || [ -n "$p" ]
    do
        wait $p
    done < $1
}

if [[ -z ${log_file+x} ]] || [[ -z ${NUM_NODES+x} ]] || [[ -z ${HOSTFILE+x} ]] || [[ -z ${BINARY_NAME+x} ]]; then
  echo "[LOG MONITOR, $(date_)] ERROR: required envvars not set, this script must be called from inside run_mpiexec.sh!"
  exit 1
fi

if [[ ! -f $HOSTFILE ]]; then
  HOSTFILE=$PBS_NODEFILE
fi
if [[ ! -f $HOSTFILE ]]; then
  echo "[LOG MONITOR, $(date_)] ERROR: hostfile $HOSTFILE not found!"
  exit 1
fi

MY_PARENT=`ps -o ppid -p $$ | tail -1 | xargs`

# Set the default start delay and monitor frequency (both in minutes)
if [[ -z ${ATHENAK_LOGMON_START_DELAY+x} ]]; then
  ATHENAK_LOGMON_START_DELAY=5
fi
if [[ -z ${ATHENAK_LOGMON_MONFREQ+x} ]]; then
  ATHENAK_LOGMON_MONFREQ=5
fi

# Enable gstack if available
ENABLE_GSTACK=0
if [[ -n ${GSTACK_WRAPPER_LOC} ]]; then
  if [[ -f $GSTACK_WRAPPER_LOC ]]; then
    ENABLE_GSTACK=1
    gstack="$GSTACK_WRAPPER_LOC"
  fi
elif command -v gstack &> /dev/null; then
  ENABLE_GSTACK=1
  gstack=$(which gstack)
fi

# Initial wait
sleep $(($ATHENAK_LOGMON_START_DELAY * 60))

# Check if LOGF is now available
LOGF=$log_file
if [ ! -f $LOGF ]; then
  echo "[LOG MONITOR, $(date_)] ERROR: Log file $log_file is still not available! Exiting .."
  exit 1
fi

# Record main mpiexec process ID for the run
MPIEXEC_PROC=$MY_PARENT #`ps -o pid,ppid,cmd --no-headers | grep -e "$MY_PARENT" -e "run_aurora_po_Nnode_2T.sh" | awk '{print $1}' | xargs`
NLINES_OLD=`wc -l $LOGF | awk '{print $1}'`

# Do this till the calling script kills the current process and while the calling script is still running...
while (( `ps -p $MY_PARENT | wc -l` == 2 )); do

  KILL_NOW=0
  sleep $(($ATHENAK_LOGMON_MONFREQ * 60))

  NLINES_NEW=`wc -l $LOGF | awk '{print $1}'`

  # Check if no update to log since last check
  if (( $NLINES_NEW == $NLINES_OLD )) && (( `ps -p $MY_PARENT | wc -l` == 2 )); then
    echo "[LOG MONITOR, $(date_)] ERROR: Log file $LOGF has not been updated in the last $ATHENAK_LOGMON_MONFREQ minutes!" | tee -a $LOGF
    KILL_NOW=1

    if  (( $ENABLE_GSTACK == 0 )); then
      echo "[LOG MONITOR, $(date_)] WARNING: gstack or gstack wrapper not found! No callstack will be dumped" | tee -a $LOGF
    else
      echo "[LOG MONITOR, $(date_)] WARNING: collecting callstacks ..." | tee -a $LOGF
      \rm -rf ./callstacks_at_hang_point/
      # collect call stacks at the hang point
      split -l 1024 $HOSTFILE $(basename ${HOSTFILE})_split_
      for i in $(basename ${HOSTFILE})_split_*; do
        clush -f 1024 -S -t 30 -u 420 --hostfile ${i} "pidof $(basename ${BINARY_NAME}) | xargs -n 1 $gstack | gzip | base64 -w0" | dshbak -d ./callstacks_at_hang_point/ -f
      done
      \rm -f $(basename ${HOSTFILE})_split_*
      # uncompress
   #  for j in callstacks_at_hang_point/x4*b0n0; do
   #    mv $j ${j}_compressed
   #    cat ${j}_compressed | base64 -d | gunzip > ${j}
   #  done
    fi
  fi

  if (( $KILL_NOW == 1 )); then

    echo "[LOG MONITOR, $(date_)] Issuing a kill of AthenaK processes across all nodes!" | tee -a $LOGF

    # Kill
    clush -f 1024 -S -t 30 -u 60 --hostfile $HOSTFILE "ps -ef | grep -e 'athenak' | awk '{print \$2}' | xargs kill -9"

    sleep 5
    kill $MPIEXEC_PROC
    sleep 10
    if (( `ps -p $MPIEXEC_PROC | wc -l` == 2 )); then
      kill -9 $MPIEXEC_PROC
    fi

  fi

  NLINES_OLD=$NLINES_NEW

done
