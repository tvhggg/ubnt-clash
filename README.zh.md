# ubnt-clash

[English](README.md) | 中文版

Clash config for Ubnt EdgeRouters

只支持从订阅链接下载配置文件。

## 快速开始

从 https://github.com/sskaje/ubnt-clash/releases 下载 deb 包。

```
# 从上面链接里找到 deb 的下载链接，下载并安装
curl -OL https://github.com/sskaje/ubnt-clash/releases/download/x.y.z/ubnt-clash_x.y.z_all.deb
dpkg -i  ubnt-clash_x.y.z_all.deb

# 配置订阅 URL
configure
set interfaces clash utun config-url https://........
commit
save

# 安装 Clash 二进制、GeoIP 数据库、UI
clashctl.sh install
# 启动 Clash
clashctl.sh start

```


## 配置说明

### EdgeOS 配置

在下列设备上已验证均为最新的固件(Debian stretch).

* ubnt ER-X
* ubnt ERLite
* ubnt ER4

USG 设备需要自己配置 [**config.gateway.json**](https://help.ui.com/hc/en-us/articles/215458888-UniFi-USG-Advanced-Configuration-Using-config-gateway-json).

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


#### EdgeOS 配置语法



```
configure

# 在这里放配置命令

commit
save
```


#### 创建接口

配置文件是使用 cURL 下载的，所以理论上 `file:///` 也是可以用的，未验证.

```
set interfaces clash utun config-url https://........
```

ubnt-clash 默认下载 `Dreamacro/clash`，也可以切换成 `MetaCubeX/Clash.Meta`: 

```
set interface clash utun executable meta
```

#### 订阅自动更新

每 4 小时自动更新配置文件。
```
set interface clash utun update-interval 14400
```

#### 连接检查

每 5 分钟检查当前连接。
```
set interface clash utun check-interval 300
```
如果你想每分钟检查，请设置 `check-interval` 成 30。


#### PBR 策略路由

路由器 IP 192.168.2.1, LAN 接口 eth1


```
# 创建路由表
set protocols static table 10 interface-route 0.0.0.0/0 next-hop-interface utun

# pbr 规则
set firewall group address-group SRC_CLASH address 192.168.2.10-192.168.2.250
set firewall modify MCLASH rule 101 action modify
set firewall modify MCLASH rule 101 modify table 10
set firewall modify MCLASH rule 101 source group address-group SRC_CLASH

# 在 eth1 上应用 pbr 规则
set interfaces ethernet eth1 firewall in modify MCLASH

# 如果只想把 Fake IP 的目的地址转入utun，可以按这个配置，实际使用中不推荐，可以参考这个配置自己的 pbr 规则
set firewall group network-group DST_CLASH_FAKEIP network 198.18.0.0/16
set firewall modify MCLASH rule 101 destination group network-group DST_CLASH_FAKEIP

```

#### DNS 劫持
路由器 IP 192.168.2.1, LAN 接口 eth1


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

## 配置文件结构

配置文件都存放在 **/config/clash**

* **/config/clash/templates**: 模板配置
* **/config/clash/templates/rulesets**: 模板配置的子配置文件样例
* **/config/clash/utun**: utun的配置

*templates* 会被复制到 *utun* 除非 *utun* 已经有了同名文件。*templates/rulesets* 不会被复制.

### YAML 文件加载顺序

1. utun/*.yaml
2. utun/rulesets/*.yaml
3. 下载的配置文件
4. utun/*.yaml.overwrite 用于覆盖已有设置，不支持覆盖数组配置.

当前版本的 YQ 不支持 prepend 元素到数组里，所以只能按这个顺序来倒入配置。

#### 自定义配置项


##### 创建新的 proxy-group

参考 `templates/rulesets/tiktok.yaml`

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

#### 第三方 Rule Providers

样例 `templates/rulesets/adblock.yaml`

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

### 其他文件

GeoIP 数据库文件会被下载到 */config/clash* 并被 symlink 到 */run/clash/utun/*.

Dashboard UI 文件会被下载到 */config/clash/dashboard*



## 命令 

### 安装 

安装 Clash Premium 二进制文件, YQ, GeoIP 数据库.

Proxy provided by p.rst.im

```
clashctl.sh install

# proxied download
USE_PROXY=1 clashctl.sh install
```

### 更新  

#### 更新 Clash 二进制

```
clashctl.sh update

# proxied download
USE_PROXY=1 clashctl.sh update
```

#### 更新 Clash DashBoard UI


```
clashctl.sh update_ui

# proxied download
USE_PROXY=1 clashctl.sh update_ui
```

#### 更新 GeoIP 数据库


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

### 查看 Clash 版本
```
clashctl.sh show_version
```

### 启动/停止/重启 Clash

```
clashctl.sh start
clashctl.sh stop
clashctl.sh restart
```

### 更新订阅配置并重启
```
clashctl.sh rehash
```


### 更多命令

```
clashctl.sh help
```

### 关于代理

代理由 https://p.rst.im/ 提供

你可以:
```
USE_PROXY=1 clashctl.sh ...
```

或者
```
touch /config/clash/USE_PROXY
clashctl ...
```

## 计划任务


### 使用 system/task-scheduler

```
# 计划任务：定时更新, 监控
set system task-scheduler task clash-cron crontab-spec "*/1 * * * *"
set system task-scheduler task clash-cron executable path "/config/scripts/clash-cron"
```



## Up/Down 脚本

把 `pre-up.sh`, `post-up.sh`, `pre-down.sh`, `post-down.sh` 放在 /config/clash/utun/scripts/ 并加上可执行的权限.


## 杂项

### 中国 IP 直连

数据来源 [17mon/china_ip_list](https://github.com/17mon/china_ip_list)

为什么不直接导入到 configure 模式里？**因为启动太慢了**

实现方案: **PBR**

好处：管理简单

```
# 创建 ipset 并加入到 PBR 规则里，放在尽量靠前的位置，至少要比执行修改的 rule id 要小
configure 
set firewall group network-group CHINA_IP
set firewall modify MCLASH rule 100 action accept
set firewall modify MCLASH rule 100 destination group network-group CHINA_IP
commit
save

# 保存列表到本地
curl -q -s -o /config/china_ip_list.txt https://p.rst.im/q/raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt

# 创建启动脚本，也可以自己调用
cat > /config/scripts/post-config.d/import-china-ip-list <<'EOF'
#!/bin/bash 

for i in $(cat /config/china_ip_list.txt);
  do ipset add -! CHINA_IP $i;
done

EOF

chmod +x /config/scripts/post-config.d/import-china-ip-list 

# 上边脚本可以自己搞个crontab

```

实现方案：**路由表**

好处：理论上性能比 PBR 会好一点点
坏处：管理麻烦

** 未测试验证，仅仅是理论上的方案 **


```

# 保存列表到本地
curl -q -s -o /config/china_ip_list.txt https://p.rst.im/q/raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt

# 创建启动脚本，也可以自己调用
cat > /config/scripts/post-config.d/import-china-ip-list <<'EOF'
#!/bin/bash 

for i in $(cat /config/china_ip_list.txt); do
  # 假定本地默认设备 eth1 上行 ip 192.168.2.1 PBR 规则使用的路由表 10
  ip route add $i dev eth1 via 192.168.2.1 table 10;
  # 假定本地默认设备 pppoe0 PBR 规则使用的路由表 10
  #ip route add $i dev pppoe0 table 10;
done

EOF

chmod +x /config/scripts/post-config.d/import-china-ip-list 

# 上边脚本可以自己搞个crontab

```




### OpenClash 增强模式

添加 `allow-lan: true` 到 `misc.yaml.overwrite`

执行命令

```
# redirect all TCP from SRC_CLASH to 7892
iptables -t nat -A PREROUTING -i wg1 -p tcp -m set --match-set SRC_CLASH src  -j REDIRECT --to-ports 7892

# redirect all TCP from SRC_CLASH and not to DST_NOCLASH to 7892
iptables -t nat -A PREROUTING -i wg1 -p tcp -m set --match-set SRC_CLASH src -m set ! --match-set DST_NOCLASH dst  -j REDIRECT --to-ports 7892

# redirect all TCP from SRC_CLASH and not to DST_NOCLASH and not to CHINA_IP to 7892
iptables -t nat -A PREROUTING -i wg1 -p tcp -m set --match-set SRC_CLASH src -m set ! --match-set DST_NOCLASH dst -m set ! --match-set CHINA_IP dst -j REDIRECT --to-ports 7892
```


没有符合 EdgeOS 的最佳实践，推荐使用 Up/Down 脚本.


## 测试 

### 验证 Clash utun

在路由器上执行下列命令，来验证 clash tun 是否正常工作

```
curl https://rst.im/ip --interface utun -v
```

