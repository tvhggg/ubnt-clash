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

CLASH_BINARY=/usr/sbin/clashd
CLASH_RUN_ROOT=/run/clash
CLASH_SUFFIX=
YQ_BINARY=/usr/bin/yq
YQ_SUFFIX=
UI_PATH=/config/clash/dashboard
CLASH_DASHBOARD_URL=https://github.com/Dreamacro/clash-dashboard/archive/refs/heads/gh-pages.tar.gz

CLASH_CONFIG_ROOT=/config/clash

CLASH_DOWNLOAD_NAME=clash.config

# Clash premium only support 1 single tun interface named utun.
DEV=utun

CLASH_REPO=Dreamacro/clash
CLASH_REPO_TAG=tags/premium

CLASH_EXECUTABLE=$(cli-shell-api returnEffectiveValue interfaces clash $DEV executable)

if [ "$CLASH_EXECUTABLE" == "meta" ]; then
  CLASH_REPO=MetaCubeX/Clash.Meta
  CLASH_REPO_TAG=latest
fi 

hwtype=$(uname -m)   
if [[ "$hwtype" == "mips64" ]]; then
  CLASH_SUFFIX="mips64-"
  YQ_SUFFIX="mips64"
elif [[ "$hwtype" == "mips" ]]; then
  CLASH_SUFFIX="mipsle-hardfloat-"
  YQ_SUFFIX="mipsle"
else
  echo "Unknown Arch"
  exit -1
fi

mkdir -p $CLASH_RUN_ROOT/$DEV $CLASH_CONFIG_ROOT/$DEV

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
  check_config [utun]    Check instance configuration
  show_config [utun]     Show instance configuration
  install                Install
  check_update           Check clash binary version
  check_version          Check clash binary version 
  update                 Update clash binary
  update_ui              Download Dashboard UI
  update_db              Download GeoIP Database
  update_yq              Download YQ binary
  cron                   Run cron
  show_version           Show clash binary version
  help                   Show this message
  

USAGE


}

function http_download()
{
  ASSET_URL=$1

  if [ "$USE_PROXY" == "1" ]; then
    echo "Download will be proxied via p.rst.im" 1>&2
    ASSET_URL=$(echo $ASSET_URL | sed -e 's#github.com#p.rst.im/q/github.com#')
  fi 

  TMPFILE=$(mktemp)
  echo curl -L -o "$TMPFILE" $ASSET_URL 1>&2
  curl -L -o "$TMPFILE" $ASSET_URL

  echo "$TMPFILE"
}

function github_download()
{
  REPO=$1
  TAG=${2:-latest}

  API_URL=https://api.github.com/repos/$REPO/releases/$TAG

  ASSET_URL=$(curl -q -s $API_URL | jq -r '.assets[0].browser_download_url')

  http_download $ASSET_URL
}


function github_releases()
{
  REPO=$1
  TAG=${2:-latest}

  API_URL=https://api.github.com/repos/$REPO/releases/$TAG
  
  ASSET_URL=$(curl -q -s $API_URL | jq -r '.assets')

  echo $ASSET_URL
}


function check_version()
{
  echo "Checking latest binary $CLASH_REPO ($CLASH_REPO_TAG)... " 1>&2
  
  PACKAGE_NAME=$(github_releases $CLASH_REPO $CLASH_REPO_TAG | jq -r  '.[] | select(.name | contains("'$CLASH_SUFFIX'")) | .name')
  echo "Latest version: " $PACKAGE_NAME 1>&2
}

function install_clash()
{
  echo "Getting asset download URL..." 1>&2
  ASSET_URL=$(github_releases $CLASH_REPO $CLASH_REPO_TAG | jq -r  '.[] | select(.name | contains("'$CLASH_SUFFIX'")) | .browser_download_url')

  TMPFILE=$(http_download $ASSET_URL)
  
  if [ $? -eq 0 ]; then   
    mv "$TMPFILE" "$TMPFILE".gz
    gunzip "$TMPFILE".gz
    chmod +x "$TMPFILE"
    "$TMPFILE" -v | grep "Clash" > /dev/null 2>&1 && sudo mv "$TMPFILE" $CLASH_BINARY
  fi 

  rm -f "$TMPFILE"

}

function clash_version()
{
  test -x $CLASH_BINARY && $CLASH_BINARY -v
}


function download_config()
{
  echo "Download Config" 1>&2

  if [ ! -x $CLASH_BINARY ]; then
    echo "You need to download clash binary first"
    exit 1
  fi

  CONFIG_URL=$(cli-shell-api returnEffectiveValue interfaces clash $DEV config-url)

  TMPFILE=$CLASH_CONFIG_ROOT/$DEV/download.yaml
  
  curl -q -s -o "$TMPFILE" $CONFIG_URL

  # test config and install 
  $CLASH_BINARY -d $CLASH_CONFIG_ROOT/$DEV -f $TMPFILE -t | grep 'test is successful' >/dev/null 2>&1 &&  mv "$TMPFILE" $CLASH_CONFIG_ROOT/$DEV/$CLASH_DOWNLOAD_NAME
}

function download_geoip_db()
{
  DB_PATH=$CLASH_CONFIG_ROOT/Country.mmdb

  mkdir -p $(dirname $DB_PATH)
  
  echo "Downloading DB..." 1>&2
  TMPFILE=$(github_download Dreamacro/maxmind-geoip latest)
  
  if [ $? -eq 0 ]; then 
    sudo mv "$TMPFILE" $DB_PATH 
  fi
  rm -f "$TMPFILE"
}

function copy_geoip_db()
{
  echo "Installing GeoIP DB..." 1>&2

  DB_PATH=$CLASH_CONFIG_ROOT/Country.mmdb
    
  if [ -f $DB_PATH ]; then 
    # DO NOT COPY
    ln -s $DB_PATH $CLASH_RUN_ROOT/$DEV/Country.mmdb
  else 
    echo "GeoIP DB Not found, clash will download it, if it's too slow, try USE_PROXY=1 $0 update_db " 1>&2
  fi
}

function check_copy_geoip_db()
{
  if [ ! -f $CLASH_RUN_ROOT/$DEV/Country.mmdb ]; then
    copy_geoip_db
  fi
}

function install_yq()
{
  echo "Installing yq..." 1>&2
  YQ_ASSET_URL=$(github_releases mikefarah/yq latest | jq -r  '.[] | select(.name | endswith("'$YQ_SUFFIX'")) | .browser_download_url')

  TMPFILE=$(http_download $YQ_ASSET_URL)

  if [ $? -eq 0 ]; then   
    chmod +x "$TMPFILE"
    # extract
    "$TMPFILE" -V | grep "yq" > /dev/null 2>&1 && sudo mv "$TMPFILE" $YQ_BINARY && echo "yq installed to $YQ_BINARY" 1>&2
  fi
  rm -f "$TMPFILE"
}

function yq_version()
{
  $YQ_BINARY -V
}

function install_ui()
{
  echo "Downloading UI..." 1>&2
  TMPFILE=$(http_download $CLASH_DASHBOARD_URL)
  
  if [ $? -eq 0 ]; then 
    # extract
    echo "Installing UI to $UI_PATH" 1>&2
    mkdir -p $UI_PATH
    tar --strip-components=1 -xv -C $UI_PATH -f "$TMPFILE" 
  fi
  rm -f "$TMPFILE"
}

function generate_config()
{
  if [ ! -f $CLASH_CONFIG_ROOT/$DEV/$CLASH_DOWNLOAD_NAME ]; then
    download_config 
  fi 

  # /config/clash/templates => /config/clash/utun
  for i in $(ls $CLASH_CONFIG_ROOT/templates/*.yaml); do 
    f=$(basename $i)
    if [ ! -f $CLASH_CONFIG_ROOT/$DEV/$f ]; then
      cp $CLASH_CONFIG_ROOT/templates/$f $CLASH_CONFIG_ROOT/$DEV/
    fi
  done

  rm -f $CLASH_RUN_ROOT/$DEV/config.yaml

  # manually setting order to ensure local rules correctly inserted before downloaded rules
  yq eval-all --from-file /usr/share/ubnt-clash/one.yq \
    $CLASH_CONFIG_ROOT/$DEV/*.yaml \
    $CLASH_CONFIG_ROOT/$DEV/rulesets/*.yaml \
    $CLASH_CONFIG_ROOT/$DEV/$CLASH_DOWNLOAD_NAME \
    $CLASH_CONFIG_ROOT/$DEV/*.yaml.overwrite \
    > $CLASH_RUN_ROOT/$DEV/config.yaml

}

function show_config()
{
  cli-shell-api showCfg interfaces clash $DEV 
}

function start()
{
  if [ -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then 
    if read pid < "$CLASH_RUN_ROOT/$DEV/clash.pid" && ps -p "$pid" > /dev/null 2>&1; then
      echo "Clash $DEV is running." 1>&2
      return 0
    else
      rm -f $CLASH_RUN_ROOT/$DEV/clash.pid 
    fi
  fi

  # pre-up
  [ -x $CLASH_CONFIG_ROOT/$DEV/scripts/pre-up.sh ] && . $CLASH_CONFIG_ROOT/$DEV/scripts/pre-up.sh 

  check_copy_geoip_db
  
  generate_config 

  ( umask 0; sudo setsid sh -c "$CLASH_BINARY -d $CLASH_RUN_ROOT/$DEV > /tmp/clash_$DEV.log 2>&1 & echo \$! > $CLASH_RUN_ROOT/$DEV/clash.pid" )

  # post-up
  [ -x $CLASH_CONFIG_ROOT/$DEV/scripts/post-up.sh ] && . $CLASH_CONFIG_ROOT/$DEV/scripts/post-up.sh 
}


function stop()
{
  if [ -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then
    # pre-down
    [ -x $CLASH_CONFIG_ROOT/$DEV/scripts/pre-down.sh ] && . $CLASH_CONFIG_ROOT/$DEV/scripts/pre-down.sh 
    sudo kill $(cat $CLASH_RUN_ROOT/$DEV/clash.pid)
    rm -f $CLASH_RUN_ROOT/$DEV/clash.pid 
    # post-down
    [ -x $CLASH_CONFIG_ROOT/$DEV/scripts/post-down.sh ] && . $CLASH_CONFIG_ROOT/$DEV/scripts/post-down.sh 
  fi
}

function delete()
{
  stop
  sudo rm -rf $CLASH_RUN_ROOT/$DEV $CLASH_CONFIG_ROOT/$DEV
}

function check_status()
{
  if [ ! -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then
    echo "Clash $DEV is not running". 1>&2
    return 2
  fi

  if read pid < "$CLASH_RUN_ROOT/$DEV/clash.pid" && ps -p "$pid" > /dev/null 2>&1; then
    echo "Clash $DEV is running." 1>&2
    return 0
  else
    echo "Clash $DEV is not running but $CLASH_RUN_ROOT/$DEV/clash.pid exists." 1>&2
    return 1 
  fi
}


function run_cron()
{
  # read device config
  for i in $(cli-shell-api listActiveNodes interfaces clash); do 
    eval "device=($i)"

    echo "Processing Device $device" 1>&2

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

  install)
    install_yq
    download_geoip_db
    install_clash
    install_ui
    ;;

  update_db)
    download_geoip_db
    ;;  
  update_yq)
    install_yq
    ;;  
  update_ui)
    install_ui
    ;;  

  update | update_clash)
    install_clash
    ;;



  status)
    check_status
    ;;  

  check_update | check_version)
    clash_version
    check_version
    ;;

  show_version | clash_version)
    clash_version
    ;;
  
  yq_version) 
    yq_version
    ;;

  check_config)
    
    ;;

  show_config)
    show_config
    ;;

  rehash)
    download_config 

  echo "Restarting clash..." 1>&2
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
    echo "Invalid Command" 1>&2
    help
    exit 1
    ;;
esac


