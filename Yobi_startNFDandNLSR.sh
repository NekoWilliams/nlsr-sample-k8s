#!/bin/sh

# NLSR Log Level Configuration
# Set NLSR_LOG_LEVEL environment variable to change log level
# Available levels: FATAL, ERROR, WARN, INFO, DEBUG, TRACE
# Default: INFO
NLSR_LOG_LEVEL=${NLSR_LOG_LEVEL:-INFO}

echo "NLSR Log Level: $NLSR_LOG_LEVEL"

# Loop for node configurations
nodeNum=1
while [ $nodeNum -le 4 ]
do
  echo "== [$nodeNum] NFD & NLSR =="

  podName=$(kubectl get pods -o name | grep "ndn-node$nodeNum")
  if [ -n "$podName" ]; then
    # /run/nfd ディレクトリの作成
    kubectl exec "$podName" -- mkdir -p /run/nfd
    kubectl exec "$podName" -- chmod 755 /run/nfd

    kubectl cp nfd.conf "${podName#pod/}":/usr/local/etc/ndn/nfd.conf
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "ndnsec key-gen /node$nodeNum | ndnsec cert-install -"
    
    echo "start NFD"
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "nfd-start 2> /nfd.log"

    kubectl cp nlsr-node$nodeNum.conf "${podName#pod/}":/
        echo "start NLSR with logging (level: $NLSR_LOG_LEVEL)"
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "export NDN_LOG='nlsr.*=$NLSR_LOG_LEVEL'; nlsr -f /nlsr-node$nodeNum.conf > /nlsr.log 2>&1 &"
  else
    echo "Pod for node $nodeNum not found."
  fi
  echo "=======\n"

  nodeNum=$((nodeNum + 1))
done

# Loop for FACE CREATE
nodeNum=1
while [ $nodeNum -le 4 ]
do
  echo "== [$nodeNum] FACE CREATE =="
  kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c 'for neighbor in $NEIGHBORS; do nfdc face create tcp4://$neighbor; done'
  echo "=======\n"

  nodeNum=$((nodeNum + 1))
done

# Loop for LOG VERIFICATION
echo "== LOG VERIFICATION =="
nodeNum=1
while [ $nodeNum -le 4 ]
do
  echo "== [$nodeNum] Checking NLSR logs =="
  podName=$(kubectl get pods -o name | grep "ndn-node$nodeNum")
  if [ -n "$podName" ]; then
    echo "Waiting for NLSR to start..."
    sleep 3
    echo "NLSR log for node$nodeNum:"
    kubectl exec "$podName" -- tail -5 /nlsr.log 2>/dev/null || echo "No log file found or empty"
  else
    echo "Pod for node $nodeNum not found."
  fi
  echo "=======\n"
  nodeNum=$((nodeNum + 1))
done

