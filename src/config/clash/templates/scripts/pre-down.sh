#!/bin/sh

# 
iptables -t nat -D PREROUTING -i wg1 -p tcp \
  -m set --match-set SRC_CLASH src \
  -m set ! --match-set LOCAL_IP dst \
  -m set ! --match-set CHINA_IP dst \
  -j REDIRECT --to-ports 7892

