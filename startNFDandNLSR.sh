#!/bin/sh

# NLSR Log Level Configuration
# Set NLSR_LOG_LEVEL environment variable to change log level
# Or pass it as the first script argument (e.g., ./startNFDandNLSR.sh DEBUG)
# Available levels: FATAL, ERROR, WARN, INFO, DEBUG, TRACE
# Default: INFO
NLSR_LOG_LEVEL=${NLSR_LOG_LEVEL:-INFO}

# Allow runtime override via first positional argument
if [ -n "$1" ]; then
  case "$1" in
    FATAL|ERROR|WARN|INFO|DEBUG|TRACE)
      NLSR_LOG_LEVEL="$1"
      ;;
    *)
      echo "Invalid NLSR_LOG_LEVEL: $1"
      echo "Use one of: FATAL ERROR WARN INFO DEBUG TRACE"
      exit 2
      ;;
  esac
fi

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
    
    # NLSR状態ディレクトリの作成
    kubectl exec "$podName" -- mkdir -p /var/lib/nlsr/node$nodeNum
    kubectl exec "$podName" -- chmod 755 /var/lib/nlsr/node$nodeNum

    kubectl cp nfd.conf "${podName#pod/}":/usr/local/etc/ndn/nfd.conf
    # ルータIDに一致する証明書/鍵を作成しデフォルトに設定
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "ndnsec key-gen /ndn/jp/%C1.Router/node$nodeNum | ndnsec cert-install - && ndnsec set-default -n /ndn/jp/%C1.Router/node$nodeNum"
    
    echo "start NFD"
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "nfd > /nfd.log 2>&1 &"

    kubectl cp nlsr-node$nodeNum.conf "${podName#pod/}":/
    
    # Dynamic Face URI resolution
    echo "Resolving Face URIs for node$nodeNum..."
    kubectl exec "$podName" -- /bin/sh -c "
      # Get neighbor IPs dynamically
      if [ $nodeNum -eq 1 ]; then
        NODE2_IP=\$(getent hosts ndn-node2 | awk '{ print \$1 }')
        NODE4_IP=\$(getent hosts ndn-node4 | awk '{ print \$1 }')
        echo \"Node2 IP: \$NODE2_IP, Node4 IP: \$NODE4_IP\"
        sed -i \"s/tcp4:\/\/ndn-node2:6363/tcp4:\/\/\$NODE2_IP:6363/g\" /nlsr-node$nodeNum.conf
        sed -i \"s/tcp4:\/\/ndn-node4:6363/tcp4:\/\/\$NODE4_IP:6363/g\" /nlsr-node$nodeNum.conf
      elif [ $nodeNum -eq 2 ]; then
        NODE1_IP=\$(getent hosts ndn-node1 | awk '{ print \$1 }')
        NODE3_IP=\$(getent hosts ndn-node3 | awk '{ print \$1 }')
        echo \"Node1 IP: \$NODE1_IP, Node3 IP: \$NODE3_IP\"
        sed -i \"s/tcp4:\/\/ndn-node1:6363/tcp4:\/\/\$NODE1_IP:6363/g\" /nlsr-node$nodeNum.conf
        sed -i \"s/tcp4:\/\/ndn-node3:6363/tcp4:\/\/\$NODE3_IP:6363/g\" /nlsr-node$nodeNum.conf
      elif [ $nodeNum -eq 3 ]; then
        NODE2_IP=\$(getent hosts ndn-node2 | awk '{ print \$1 }')
        NODE4_IP=\$(getent hosts ndn-node4 | awk '{ print \$1 }')
        echo \"Node2 IP: \$NODE2_IP, Node4 IP: \$NODE4_IP\"
        sed -i \"s/tcp4:\/\/ndn-node2:6363/tcp4:\/\/\$NODE2_IP:6363/g\" /nlsr-node$nodeNum.conf
        sed -i \"s/tcp4:\/\/ndn-node4:6363/tcp4:\/\/\$NODE4_IP:6363/g\" /nlsr-node$nodeNum.conf
      elif [ $nodeNum -eq 4 ]; then
        NODE1_IP=\$(getent hosts ndn-node1 | awk '{ print \$1 }')
        NODE3_IP=\$(getent hosts ndn-node3 | awk '{ print \$1 }')
        echo \"Node1 IP: \$NODE1_IP, Node3 IP: \$NODE3_IP\"
        sed -i \"s/tcp4:\/\/ndn-node1:6363/tcp4:\/\/\$NODE1_IP:6363/g\" /nlsr-node$nodeNum.conf
        sed -i \"s/tcp4:\/\/ndn-node3:6363/tcp4:\/\/\$NODE3_IP:6363/g\" /nlsr-node$nodeNum.conf
      fi
    "
  else
    echo "Pod for node $nodeNum not found."
  fi
  echo "=======\n"

  nodeNum=$((nodeNum + 1))
done

# Loop for FACE CREATE (before NLSR start)
nodeNum=1
while [ $nodeNum -le 4 ]
do
  echo "== [$nodeNum] FACE CREATE =="
  kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c 'for neighbor in $NEIGHBORS; do nfdc face create tcp4://$neighbor; done'
  echo "=======\n"

  nodeNum=$((nodeNum + 1))
done

# Wait for faces to be established
echo "Waiting for faces to be established..."
sleep 5

# Loop for NLSR start (after faces are created)
nodeNum=1
while [ $nodeNum -le 4 ]
do
  echo "== [$nodeNum] NLSR START =="
  podName=$(kubectl get pods -o name | grep "ndn-node$nodeNum")
  if [ -n "$podName" ]; then
    echo "start NLSR with logging (level: $NLSR_LOG_LEVEL)"
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "export NDN_LOG='nlsr.*=$NLSR_LOG_LEVEL'; nlsr -f /nlsr-node$nodeNum.conf > /nlsr.log 2>&1 &"
  else
    echo "Pod for node $nodeNum not found."
  fi
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

