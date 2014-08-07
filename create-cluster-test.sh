#! /bin/bash
# Copyleft (C) KRT, 2014 by kiterunner_t


# set -x
# pkill redis-server
# ps -fC redis-server

# ruby redis-trib.rb create --replicas 1 127.0.0.1:7001 127.0.0.1:7003 127.0.0.1:7005 127.0.0.1:7002 127.0.0.1:7004 127.0.0.1:7006


_DEBUG_LEVEL=$1
test -z $_DEBUG_LEVEL && _DEBUG_LEVEL=notice

_redis_version=$(redis-server -v 2>/dev/null)
_ret=$?
if [ $_ret -eq 127 ]; then
  echo "redis-server is not exist"
  exit 127
elif [ $_ret -ne 0 ]; then
  echo "redis-server error: $!"
  exit 1
fi

_version=$(echo $_redis_version | \
  perl -e 'while (<>) { print $1 if /^Redis server v=(\d+\.\d+\.\d+)\s+/; }')

_major=$(echo $_version | cut -d. -f1)
_minor=$(echo $_version | cut -d. -f2)
if [ $_major -lt 2 -o $_major -eq 2 -a $_minor -lt 9 ]; then
  echo "require redis-server 2.9"
  exit 1
fi

# 1) create cluster nodes [7001-7006]
echo "create cluster nodes 7001..7006 ..."
for _port in $(seq 7001 7006); do
  echo "starting $_port ..."

  if [ ! -d $_port ]; then
    mkdir $_port
    test $? -ne 0 && echo "mkdir $_port error: $!" && exit 1
  fi

  _conf=redis.$_port.conf

  cat >$_port/$_conf <<EOF
port $_port
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly yes
daemonize yes
logfile cluster.${_port}.log
loglevel $_DEBUG_LEVEL
latency-monitor-threshold 2
EOF

  cd $_port
  test $? -ne 0 && echo "cd $_port error: $!" && exit 1

  test -f nodes.conf && rm -f nodes.conf
  test -f appendonly.aof && rm -f appendonly.aof
  test -f dump.rdb && rm -f dump.rdb
  test -f cluster.$_port.log && rm -f cluster.$_port.log

  redis-server ./$_conf
  test $? -ne 0 && echo "start redis-server in port $_port error: $!" && exit 1

  cd ..
  test $? -ne 0 && echo "cd .. error: $!" && exit 1
done


# 2) alloc slots for master nodes
echo
echo "alloc slots for master nodes, 7001 7003 7005 ..."

_line1=$(seq 0 5000 | perl -e 'while (<>) { s/\n/ /g; print; }')
_line3=$(seq 5001 10000 | perl -e 'while (<>) { s/\n/ /g; print; }')
_line5=$(seq 10001 16383 | perl -e 'while (<>) { s/\n/ /g; print; }')

redis-cli -p 7001 cluster addslots $_line1
redis-cli -p 7003 cluster addslots $_line3
redis-cli -p 7005 cluster addslots $_line5
sleep 1


# 3) set epoch
echo
echo "set epoch ..."
redis-cli -p 7001 cluster set-config-epoch 1
redis-cli -p 7002 cluster set-config-epoch 2
redis-cli -p 7003 cluster set-config-epoch 3
redis-cli -p 7004 cluster set-config-epoch 4
redis-cli -p 7005 cluster set-config-epoch 5
redis-cli -p 7006 cluster set-config-epoch 6


# 4) join clusters
echo
echo "join clusters ..."
redis-cli -p 7002 cluster meet 127.0.0.1 7001
redis-cli -p 7003 cluster meet 127.0.0.1 7001
redis-cli -p 7004 cluster meet 127.0.0.1 7001
redis-cli -p 7005 cluster meet 127.0.0.1 7001
redis-cli -p 7006 cluster meet 127.0.0.1 7001
sleep 3


# 5) replicate nodes
echo
echo "replicate ndoes ..."
_clusterid_7001=$(redis-cli -p 7001 cluster nodes | grep myself | awk '{ print $1 }')
_clusterid_7003=$(redis-cli -p 7003 cluster nodes | grep myself | awk '{ print $1 }')
_clusterid_7005=$(redis-cli -p 7005 cluster nodes | grep myself | awk '{ print $1 }')

redis-cli -p 7002 cluster replicate $_clusterid_7001
redis-cli -p 7004 cluster replicate $_clusterid_7003
redis-cli -p 7006 cluster replicate $_clusterid_7005

# the cluster state may not be changed between 0.5s and 5s
sleep 6

echo
echo
echo "display info about nodes ..."
for _port in $(seq 7001 7006); do
  echo "-------$_port-------"
  redis-cli -p $_port cluster nodes
  redis-cli -p $_port cluster info
  echo
done

