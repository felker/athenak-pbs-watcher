#!/bin/bash

NUM_NODES=48
PPN=12
INP="-i ../../inputs/tests/linear_wave_hydro.athinput"

for key in "$@"
do
case $key in
   --ppn=*)
   PPN="${key#*=}"
   shift
   ;;

   -n=*|--nodes=*)
   NUM_NODES="${key#*=}"
   shift #past argument=value
   ;;

   --inp=*)
   INP="${key#*=}"
   shift
   ;;
esac
done

echo "NUM_NODES: " $NUM_NODES
echo "PPN: " $PPN
echo "INP: " $INP

echo ${PWD}
echo "mpiexec --np $NUM_NODES --ppn $PPN gpu_tile_compact.sh ./amr_wind $INP"

cd build
echo ${PWD}

# MAKE SURE VARS ARE SET FOR MONITOR SCRIPT
log_file="log_mpiexec.log"
BINARY_NAME="./athenak"
HOSTFILE=

echo "$log_file"
echo "BINARY_NAME = $BINARY_NAME"

# start log monitor
export log_file
export BINARY_NAME
export NUM_NODES
export HOSTFILE
# Launch log monitor
export GSTACK_WRAPPER_LOC="/soft/tools/gstack-gdb-oneapi/bin/gstack-gdb-oneapi-cpu.sh"
../amrwind_log_monitor.sh &
LOGMON_PID=$!


mpiexec -np $NUM_NODES -ppn $PPN gpu_tile_compact.sh $BINARY_NAME $INP |& tee $log_file
echo "youve reached the end of run_mpiexec\n"


# Kill log monitor
kill $LOGMON_PID
sleep 5
if (( `ps -p $LOGMON_PID | wc -l` == 2 )); then
  kill -9 $LOGMON_PID
fi


#cat foo.txt
