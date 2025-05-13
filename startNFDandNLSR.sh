#!/bin/sh
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
    echo "start NLSR"
    kubectl exec deployment/ndn-node$nodeNum -- /bin/sh -c "nlsr -f /nlsr-node$nodeNum.conf &"
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