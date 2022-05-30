# ubnt-clash

English | [中文版](README.zh.md)

Clash config for Ubnt EdgeRouters

Only supports configuration from URL.

## Quick Start 

Download deb package from https://github.com/sskaje/ubnt-clash/releases

```
# Download deb package, copy URL from above
curl -OL https://github.com/sskaje/ubnt-clash/releases/download/x.y.z/ubnt-clash_x.y.z_all.deb
dpkg -i  ubnt-clash_x.y.z_all.deb

# Set config URL
configure
set interfaces clash utun config-url https://........
commit
save

# Install binary, GeoIP db, UI
clashctl.sh install
# Start Clash
clashctl.sh start

```


## Configuration

### EdgeOS Config

Tested under ubnt ER-X, ubnt ERLite, ubnt ER4 with latest firmware(Debian stretch based).

For USG devices, please make sure your [**config.gateway.json**](https://help.ui.com/hc/en-us/articles/215458888-UniFi-USG-Advanced-Configuration-Using-config-gateway-json) is properly configured on your controller.

```json
{
  "interface": {
    "clash": {
      "utun": {
        "config-url": "https://...."
      }
    }
  }
}
```


#### Configure Syntax



```
configure

# Your configuration commands here

commit
save
```


#### Create Interface

File is downloaded with cURL, `file:///` is supported by cURL but not tested here.

```
set interfaces clash utun config-url https://........
```

ubnt-clash downloads `Dreamacro/clash` by default, you can use `MetaCubeX/Clash.Meta` by setting: 

```
set interface clash utun executable meta
```

#### Update Clash Configuration

Update configuration from subscription URL.
```
set interface clash utun update-time 14400
```

#### PBR 

Router local IP 192.168.2.1, LAN interface eth1


```
# route table
set protocols static table 10 interface-route 0.0.0.0/0 next-hop-interface utun

# pbr rules
set firewall group address-group SRC_CLASH address 192.168.2.10-192.168.2.250
set firewall modify MCLASH rule 101 action modify
set firewall modify MCLASH rule 101 modify table 10
set firewall modify MCLASH rule 101 source group address-group SRC_CLASH

# apply pbr rules to eth1
set interfaces ethernet eth1 firewall in modify MCLASH

# Fake IP destination only if you need, NOT recommended
set firewall group network-group DST_CLASH_FAKEIP network 198.18.0.0/16
set firewall modify MCLASH rule 101 destination group network-group DST_CLASH_FAKEIP

```

#### DNS Hijack
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

## Config Files

Files are stored under **/config/clash**

* **/config/clash/templates**: template config files
* **/config/clash/templates/rulesets**: example config files
* **/config/clash/utun**: config files for utun

YAML files under *templates* will be copied to *utun* unless there is a same file under *utun*, files under *templates/rulesets* will NOT be copied.

### YAML File Loading Order 

1. utun/*.yaml
2. utun/rulesets/*.yaml
3. File downloaded from server 
4. utun/*.yaml.overwrite to overwrite settings, don't try to overwrite an array.

This loading order is designed because appending element to array is easier in YQ. 

#### Custom Entry 

Some custom config entry is used by YQ scripts.

##### Create A New Proxy Group

Example `templates/rulesets/tiktok.yaml`

```
proxy-groups:
  - name: "TIKTOK"
    type: select
    proxies: []

create-proxy-group:
  TIKTOK: "日本|韩国"
```

A new **proxy-group** named "*TIKTOK*" will be created before all `proxy-groups` and its `proxies` is filtered like 

```
yq '[.proxies[] | select( .name | test("日本|韩国") ) | .name]' download.yaml
```

#### 3rd Party Rule Providers

Examples `templates/rulesets/adblock.yaml`

```
rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://p.rst.im/q/raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt"
    path: ./reject.yaml
    interval: 86400

rules:
  - RULE-SET,reject,REJECT

```

A new rule provider will be added to clash config and a new `rule` will be insert before downloaded rules.

`p.rst.im` is recommended in `url`.

### Other Files

GeoIP database file willl be downloaded to */config/clash* and symlink to */run/clash/utun/*.

Dashboard files will be downloaded to */config/clash/dashboard*



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
clashctl.sh update

# proxied download
USE_PROXY=1 clashctl.sh update
```

#### Update Clash DashBoard UI


```
clashctl.sh update_ui

# proxied download
USE_PROXY=1 clashctl.sh update_ui
```

#### Update GeoIP Database


```
clashctl.sh update_db

# proxied download
USE_PROXY=1 clashctl.sh update_db
```

#### Update YQ


```
clashctl.sh update_yq

# proxied download
USE_PROXY=1 clashctl.sh update_yq
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

### About Proxy

Proxy is provided by https://p.rst.im/

You can either:
```
USE_PROXY=1 clashctl.sh ...
```
or

```
touch /config/clash/USE_PROXY
clashctl ...
```




## Cron 


### Via system/task-scheduler

```
# task scheduler, monitor, cron, etc.
set system task-scheduler task clash-cron crontab-spec "*/1 * * * *"
set system task-scheduler task clash-cron executable path "/config/scripts/clash-cron"

```

## Up/Down Scripts

Put `pre-up.sh`, `post-up.sh`, `pre-down.sh`, `post-down.sh` under /config/clash/utun/scripts/ and make them executable.


## Misc

### OpenClash Enhanced Mode

Add `allow-lan: true` to `misc.yaml.overwrite`

Run command

```
# redirect all TCP from SRC_CLASH to 7892
iptables -t nat -A PREROUTING -i wg1 -p tcp -m set --match-set SRC_CLASH src  -j REDIRECT --to-ports 7892

# redirect all TCP from SRC_CLASH and not to DST_NOCLASH to 7892
iptables -t nat -A PREROUTING -i wg1 -p tcp -m set --match-set SRC_CLASH src -m set ! --match-set DST_NOCLASH dst  -j REDIRECT --to-ports 7892

# redirect all TCP from SRC_CLASH and not to DST_NOCLASH and not to CHINA_IP to 7892
iptables -t nat -A PREROUTING -i wg1 -p tcp -m set --match-set SRC_CLASH src -m set ! --match-set DST_NOCLASH dst -m set ! --match-set CHINA_IP dst -j REDIRECT --to-ports 7892
```


No 'best practice' yet, you can try with up/down scripts.

## Test 

### Clash utun

Run on your Router to verify if clash tun is up and working.

```
curl https://rst.im/ip --interface utun -v
```

