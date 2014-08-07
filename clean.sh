#! /bin/bash

pkill redis-server

_NAMES=$(find . -name "*.aof" -o -name *.rdb -o -name cluster*.log -o -name nodes.conf)

test -n "$_NAMES" && rm -f $_NAMES

