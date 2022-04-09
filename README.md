# ubnt-clash

Clash config for Ubnt EdgeRouters

## Install 

Download deb package from https://github.com/sskaje/ubnt-clash/releases

```
dpkg -i  ubnt-clash_x.y.z_all.deb
```


## Configuration

### Create Interface

```
configure
set interfaces clash utun config-url https://........
commit
save

```

### PBR 

Router local IP 192.168.2.1, LAN interface eth1


```
set protocols static table 10 interface-route 0.0.0.0/0 next-hop-interface utun
set firewall group address-group SRC_CLASH address 192.168.2.10-192.168.2.250
set firewall modify MCLASH rule 101 action modify
set firewall modify MCLASH rule 101 modify table 10
set firewall modify MCLASH rule 101 source group address-group SRC_CLASH
set interfaces ethernet eth1 firewall in modify MCLASH

```

### DNS Hijack
Router local IP 192.168.2.1, LAN interface eth1


```
set service nat rule 4050 destination group address-group ADDRv4_eth1
set service nat rule 4050 destination port 53
set service nat rule 4050 inbound-interface eth1
set service nat rule 4050 inside-address address 192.168.2.1
set service nat rule 4050 inside-address port 7874
set service nat rule 4050 protocol udp
set service nat rule 4050 source group address-group SRC_CLASH
set service nat rule 4050 type destination

```



## Commands 

### Install 

Install Clash Premium Binary, YQ, GeoIP Database.

Proxy provided by p.rst.im

```
clashctl.sh install

# proxied download
USE_PROXY=1 clashctl.sh install
```

### Update  

#### Update Clash Binary

```
clashctl.sh install

# proxied download
USE_PROXY=1 clashctl.sh install
```

#### Update GeoIP Database


```
clashctl.sh download_db

# proxied download
USE_PROXY=1 clashctl.sh download_db
```

### Show Clash Binary Version 
```
clashctl.sh show_version
```

### Start/Stop/Restart Client 

```
clashctl.sh start
clashctl.sh stop
clashctl.sh restart
```

### Update Config And Restart
```
clashctl.sh rehash
```


### More

```
clashctl.sh help
```


## Cron Update Config


### Via system/task-scheduler

```
set system task-scheduler task update-clash-config crontab-spec "20 */4 * * *"
set system task-scheduler task update-clash-config executable path "/config/scripts/clash-cron"

```

## Test 

### Clash utun

```
curl https://rst.im/ip --interface utun -v
```





