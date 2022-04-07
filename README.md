# ubnt-clash

Clash config for Ubnt EdgeRouters


## Configuration

### Create Interface

```
configure
set interfaces clash utun config-url https://........
commit
save

```

### PBR 

Tested on ER-X

```
set protocols static table 10 interface-route 0.0.0.0/0 next-hop-interface utun
set firewall group address-group SRC_CLASH address 192.168.8.10-192.168.8.250
set firewall modify MCLASH rule 101 action modify
set firewall modify MCLASH rule 101 modify table 10
set firewall modify MCLASH rule 101 source group address-group SRC_CLASH
set interfaces ethernet eth1 firewall in modify MCLASH

```

## Commands 

### Install Clash Premium Binary

Proxy provided by p.rst.im

```
clashctl.sh update

# proxied download
USE_PROXY=1 clashctl.sh update
```

### Download GeoIP Database

Proxy provided by p.rst.im

It's recommended to download manually instead of letting clash download it.

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


