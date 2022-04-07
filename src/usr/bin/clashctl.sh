#!/bin/sh
# 
# Clash Control Script 
# 
# Author: sskaje (https://sskaje.me/ https://github.com/sskaje/ubnt-clash)
# Version: 0.1.0
# 
# Required commands:
#    curl
#    jq
# 

RELEASE_URL=https://api.github.com/repos/Dreamacro/clash/releases/tags/premium 
GEOIP_DB_RELEASE_URL=https://api.github.com/repos/Dreamacro/maxmind-geoip/releases/latest

CLASH_BINARY=/usr/sbin/clashd
CLASH_RUN_ROOT=/var/run/clash
CLASH_SUFFIX=

DEFAULT_CLASH_CONFIG_ROOT=/config/clash

# Clash premium only support 1 single tun interface named utun.
DEV=utun

hwtype=$(uname -m)   
if [[ "$hwtype" == "mips64" ]]; then
    CLASH_SUFFIX="mips64-"
elif [[ "$hwtype" == "mips" ]]; then
    CLASH_SUFFIX="mipsle-hardfloat-"
else
    echo "Unknown Arch"
    exit -1
fi

mkdir -p $CLASH_RUN_ROOT/$DEV $DEFAULT_CLASH_CONFIG_ROOT/$DEV

function check_patch_vyatta()
{
  if [ -z "$(grep 'utun' /opt/vyatta/share/perl5/Vyatta/Interface.pm | grep clash)" ]; then
    # find line with %net_prefix = (
    # insert the "'^utun$' => { path => 'clash' },"

    sed -i.bak "/%net_prefix =/a     '^utun\$' => { path => 'clash' }," /opt/vyatta/share/perl5/Vyatta/Interface.pm
  fi
}

check_patch_vyatta

function help()
{
  cat <<USAGE

Clashctl for UBNT EdgeRouter by sskaje


Usage: 
  clashctl.sh command [options]
  

Commands:
  start [utun]           Start an instance
  stop [utun]            Stop an instance
  restart [utun]         Restart an instance
  delete [utun]          Delete an instance
  status [utun]          Show instance status
  rehash [utun]          Reload instance config
  download_db [utun]     Download GeoIP Database
  check_config [utun]    Check instance configuration
  show_config [utun]     Show instance configuration
  cron                   Run cron
  check_update           Check clash binary version
  check_version          Check clash binary version 
  update                 Update clash binary
  show_version           Show clash binary version
  help                   Show this message
  

USAGE


}

function check_version()
{
  echo "Checking latest premium binary... "

  PACKAGE_NAME=$(curl -q -s $RELEASE_URL | jq -r  '.assets[] | select(.name | contains("'$CLASH_SUFFIX'")) | .name')
  echo "Latest version: " $PACKAGE_NAME

}

function download_binary()
{
  echo "Getting asset download URL..."
  DOWNLOAD_URL=$(curl -q -s $RELEASE_URL | jq -r '.assets[] | select(.name | contains("'$CLASH_SUFFIX'")) | .browser_download_url')

  if [ "$USE_PROXY" == "1" ]; then
    echo "Download will be proxied via p.rst.im"
    DOWNLOAD_URL=$(echo $DOWNLOAD_URL | sed -e 's#github.com#p.rst.im/q/github.com#')
  fi 

  echo "Download URL: $DOWNLOAD_URL"
  echo "Extract to: $CLASH_BINARY"

  TMPFILE=$(mktemp)

  curl -o - -L  $DOWNLOAD_URL | gunzip  > $TMPFILE

  chmod +x $TMPFILE

  $TMPFILE -v | grep "Clash" > /dev/null 2>&1 && mv $TMPFILE $CLASH_BINARY
  rm -f $TMPFILE

}

function clash_version()
{
  test -x $CLASH_BINARY && $CLASH_BINARY -v
}


function download_config()
{
  echo "Download Config"

  if [ ! -x $CLASH_BINARY ]; then
    echo "You need to download clash binary first"
    exit 1
  fi

  CONFIG_URL=$(cli-shell-api returnEffectiveValue interfaces clash $DEV config-url)

  TMPFILE=$DEFAULT_CLASH_CONFIG_ROOT/$DEV/config.yaml
  
  curl -q -s -o $TMPFILE $CONFIG_URL

  # test config and install 
  $CLASH_BINARY -d $DEFAULT_CLASH_CONFIG_ROOT/$DEV -t | grep 'test is successful' >/dev/null 2>&1 &&  mv $TMPFILE $CLASH_RUN_ROOT/$DEV/clash.yaml
}

function generate_utun_config()
{
  cat > $CLASH_RUN_ROOT/$DEV/tun.yaml <<'EOF'
tun: 
  enable: true
  stack: system

EOF

}

function download_geoip_db()
{
  DB_PATH=$(cli-shell-api returnEffectiveValue interfaces clash $DEV geoip-db)
  if [ -z "$DB_PATH" ]; then
    echo "geoip-db not set in configuration mode. Using default clash config dir";
    DB_PATH=$DEFAULT_CLASH_CONFIG_ROOT/$DEV/Country.mmdb
  fi

  mkdir -p $(dirname $DB_PATH)
  
  echo "Downloading DB..."
  
  GEOIP_DB_URL=$(curl -q -s $GEOIP_DB_RELEASE_URL | jq -r '.assets[0].browser_download_url')

  if [ "$USE_PROXY" == "1" ]; then
    echo "Download will be proxied via p.rst.im"
    GEOIP_DB_URL=$(echo $GEOIP_DB_URL | sed -e 's#github.com#p.rst.im/q/github.com#')
  fi 

  TMPFILE=$(mktemp)
  echo curl -L -o $TMPFILE $GEOIP_DB_URL
  curl -L -o $TMPFILE $GEOIP_DB_URL
  
  if [ $? -eq 0 ]; then 
    sudo mv $TMPFILE $DB_PATH 
  fi
  rm -f $TMPFILE
}

# If 
function copy_geoip_db()
{
  echo "Installing GeoIP DB..."

  DB_PATH=$(cli-shell-api returnEffectiveValue interfaces clash $DEV geoip-db)
  if [ -z "$DB_PATH" ]; then
    echo "Please set geoip-db in configuration mode.";
    DB_PATH=$DEFAULT_CLASH_CONFIG_ROOT/$DEV/Country.mmdb
  fi
  if [ -f $DB_PATH ]; then 
    cp $DB_PATH $CLASH_RUN_ROOT/$DEV/Country.mmdb
  else 
    echo "GeoIP DB Not found, clash will download it, if it's too slow, try USE_PROXY=1 $0 download_db "
  fi
}

function check_copy_geoip_db()
{
  if [ ! -f $CLASH_RUN_ROOT/$DEV/Country.mmdb ]; then
    copy_geoip_db
  fi
}

function generate_config()
{
  if [ ! -f $CLASH_RUN_ROOT/$DEV/clash.yaml ]; then
    download_config 
  fi 

  generate_utun_config

  cat $CLASH_RUN_ROOT/$DEV/clash.yaml  $CLASH_RUN_ROOT/$DEV/tun.yaml >  $CLASH_RUN_ROOT/$DEV/config.yaml
}

function show_config()
{
  cli-shell-api showCfg interfaces clash $DEV 
}

function start()
{
  if [ -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then 
    if read pid < "$CLASH_RUN_ROOT/$DEV/clash.pid" && ps -p "$pid" > /dev/null 2>&1; then
      echo "Clash $DEV is running."
      return 0
    else
      rm -f $CLASH_RUN_ROOT/$DEV/clash.pid 
    fi
  fi

  check_copy_geoip_db
  
  generate_config 

  ( umask 0; sudo setsid sh -c "$CLASH_BINARY -d $CLASH_RUN_ROOT/$DEV > /tmp/clash_$DEV.log 2>&1 & echo \$! > $CLASH_RUN_ROOT/$DEV/clash.pid" )
}


function stop()
{
  if [ -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then
    sudo kill $(cat $CLASH_RUN_ROOT/$DEV/clash.pid)
    rm -f $CLASH_RUN_ROOT/$DEV/clash.pid 
  fi
}

function delete()
{
  stop
  sudo rm -rf $CLASH_RUN_ROOT/$DEV $DEFAULT_CLASH_CONFIG_ROOT/$DEV
}

function check_status()
{
  if [ ! -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then
    echo "Clash $DEV is not running".
    return 2
  fi

  if read pid < "$CLASH_RUN_ROOT/$DEV/clash.pid" && ps -p "$pid" > /dev/null 2>&1; then
    echo "Clash $DEV is running."
    return 0
  else
    echo "Clash $DEV is not running but $CLASH_RUN_ROOT/$DEV/clash.pid exists."
    return 1 
  fi
}


function run_cron()
{
  # read device config
  for i in $(cli-shell-api listActiveNodes interfaces clash); do 
    eval "device=($i)"

    echo "Processing Device $device"

    config_mtime=$(stat -c %Y $CLASH_RUN_ROOT/$DEV/config.yaml)
    now_time=$(date +'%s')
    diff_in_seconds=$(expr $now_time - $config_mtime)
    if [ $diff_in_seconds -gt 86400 ];then 
      rehash $i
      stop $i
      start $i
    fi 
  done
}




case $1 in
  start)
    start
    ;;

  delaystart)
    sleep 5;
    start
    ;;

  stop)
    stop
    ;;  

  delete)
    delete
    ;;  


  restart)
    stop
  sleep 1
    start
    ;;

  download_db)
    download_geoip_db
    ;;  


  status)
    check_status
    ;;  

  check_update | check_version)
    clash_version
    check_version
    ;;

  show_version)
    clash_version
    ;;
  
  update)
    download_binary
    ;;

  check_config)
    
    ;;

  show_config)
    show_config
    ;;

  rehash)
    download_config 

  echo "Restarting clash..."
    stop
    sleep 1
    start
    ;;


  cron)
    run_cron 
    ;;

  help)
    help
    ;;

  *)
    echo "Invalid Command"
    help
    exit 1
    ;;
esac


