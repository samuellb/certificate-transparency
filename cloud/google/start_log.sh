#!/bin/bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
source ${DIR}/util.sh
source ${DIR}/config.sh

set -e
GCLOUD="gcloud"

Header "Creating log persistent disks..."
for i in `seq 0 $((${LOG_NUM_REPLICAS} - 1))`; do
  echo "Creating disk ${LOG_DISKS[${i}]}..."
  ${GCLOUD} compute disks create -q ${LOG_DISKS[${i}]} \
      --zone=${LOG_ZONES[${i}]} \
      --size=${LOG_DISK_SIZE} &
done
wait

for i in `seq 0 $((${LOG_NUM_REPLICAS} - 1))`; do
  echo "Waiting for disk ${LOG_DISKS[${i}]}..."
  WaitForStatus disks ${LOG_DISKS[${i}]} ${LOG_ZONES[${i}]} READY &
done
wait

MANIFEST=/tmp/log_container.yaml

Header "Creating log instances..."
for i in `seq 0 $((${LOG_NUM_REPLICAS} - 1))`; do
  echo "Creating instance ${LOG_MACHINES[$i]}"

  sed --e "s^@@PROJECT@@^${PROJECT}^
           s^@@ETCD_HOST@@^${ETCD_MACHINES[1]}^
           s^@@ETCD_PORT@@^4001^
           s^@@CONTAINER_HOST@@^${LOG_MACHINES[$i]}^" \
          < ${DIR}/log_container.yaml  > ${MANIFEST}.${i}

  ${GCLOUD} compute instances create -q ${LOG_MACHINES[${i}]} \
      --zone=${LOG_ZONES[${i}]} \
      --machine-type ${LOG_MACHINE_TYPE} \
      --image container-vm \
      --disk name=${LOG_DISKS[${i}]},mode=rw,boot=no,auto-delete=yes \
      --tags log-node \
      --metadata-from-file startup-script=${DIR}/node_init.sh,google-container-manifest=${MANIFEST}.${i} &
done
wait

for i in `seq 0 $((${LOG_NUM_REPLICAS} - 1))`; do
  echo "Waiting for instance ${LOG_MACHINES[${i}]}..."
  WaitForStatus instances ${LOG_MACHINES[${i}]} ${LOG_ZONES[${i}]} RUNNING &
done
wait


