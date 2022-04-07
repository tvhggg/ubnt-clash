#!/bin/sh
# 
#
# Required commands:
#    curl
#    jq
# 

RELEASE_URL=https://api.github.com/repos/Dreamacro/clash/releases/tags/premium 

CLASH_BINARY=/usr/sbin/clash
CLASH_SUFFIX=
CLASH_RUN_ROOT=/var/run/clash

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

mkdir -p $CLASH_RUN_ROOT/$DEV

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
  status [utun]          Show instance status
  rehash [utun]          Reload instance config
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
  $CLASH_BINARY -v
}


function download_config()
{
  echo "Download Config"

  if [ ! -x $CLASH_BINARY ]; then
    echo "You need to download clash binary first"
	exit 1
  fi

  CONFIG_URL=$(cli-shell-api returnEffectiveValue interfaces clash $DEV config-url)

  TMPFILE=$(mktemp)
  
  curl -q -s -o $TMPFILE $CONFIG_URL

  # test config and install 
  $CLASH_BINARY -f $TMPFILE -t | grep 'test is successful' >/dev/null 2>&1 &&  mv $TMPFILE $CLASH_RUN_ROOT/$DEV/clash.yaml

  rm -f $TMPFILE
}

function generate_utun_config()
{
  cat > $CLASH_RUN_ROOT/$DEV/tun.yaml <<'EOF'
tun: 
  enable: true
  stack: system

EOF

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
    rm -f $CLASH_RUN_ROOT/$DEV/clash.pid 
  fi

  generate_config 

  ( umask 0; sudo setsid sh -c "/usr/sbin/clash -d $CLASH_RUN_ROOT/$DEV > /tmp/clash_$DEV.log 2>&1 & echo \$! > $CLASH_RUN_ROOT/$DEV/clash.pid" )
}


function stop()
{
  if [ -f $CLASH_RUN_ROOT/$DEV/clash.pid ]; then
    kill $(cat $CLASH_RUN_ROOT/$DEV/clash.pid)
	rm -f $CLASH_RUN_ROOT/$DEV/clash.pid 
  fi
}

function delete()
{
  stop
  sudo rm -rf $CLASH_RUN_ROOT/$DEV
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



  done
}




case $1 in
  start)
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


