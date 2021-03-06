#!/bin/bash

if [[ $EUID -ne 0 ]]
then
  echo "Please log in as root, or 'sudo' run the command if you have sudo privileges."
  exit 1
fi

if which dpkg > /dev/null 2>&1
then
  OS=UBUNTU
  PKGMGR=`which dpkg`
  PKGMGROPT='-l'
  CMDOPT='-S'
elif which rpm >/dev/null 2>&1 
then
  OS=RHEL
  PKGMGR=`which rpm`
  PKGMGROPT='-q'
  CMDOPT='-qf'
else
  echo "Unsupported OS."
  exit 1
fi

report="report4GraphSQL_`hostname`.txt"
(
  echo "=== Checking Prerequisites ==="
  echo "**checking required system libraries ..."
  LIBS="glibc libgcc libstdc++ zlib"
  LIBS_MISSING=''
  for lib in $LIBS
  do
    if [ $OS = 'RHEL' ]
    then
      if $PKGMGR $PKGMGROPT $lib > /dev/null 2>&1
      then
        pkglib=$( $PKGMGR $PKGMGROPT $lib)
        echo "  \"$lib\" found in $pkglib"
      else
        echo "  \"$lib\" NOT FOUND"
        LIBS_MISSING="$LIBS_MISSING $lib"
      fi
    else 
      if $PKGMGR $PKGMGROPT ${lib}*|grep $lib > /dev/null 2>&1
      then
        pkglib=$( $PKGMGR $PKGMGROPT ${lib}*|grep $lib |head -1|awk '{print $2}')
        echo "  \"$lib\" found: $pkglib"
      else
        echo "  \"$lib\" NOT FOUND"
        LIBS_MISSING="$LIBS_MISSING $lib"
      fi
    fi
  done

  echo
  echo "**checking required commands ..."
  CMDS="java unzip scp nc"
  CMDS_MISSING=''
  for cmd in $CMDS
  do
    if which $cmd >/dev/null 2>&1
    then
      if [ "j$cmd" = 'jjava' ]
      then
        echo "  $(java -version 2>&1|head -1) found"
        JV=$(java -version 2>&1|head -1 | grep -oP "[12]\.\d\d*")
        if [ "$JV" = "1.5" -o "$JV" = "1.6" ]
        then
          CMDS_MISSING="$CMDS_MISSING ${cmd}>=1.7"
          echo "  Java >= 1.7 required"
        fi
      else
        if [ $OS = 'RHEL' ]
        then 
          pkg=$( $PKGMGR $CMDOPT "$(which $cmd)")
          echo "  $cmd found in $pkg"
        else
          pkg=$( $PKGMGR $CMDOPT "$(which $cmd)" |awk 'BEGIN { FS = ":" } ; { print $1 }') 
          pkgVer=$( $PKGMGR $PKGMGROPT $pkg|grep $pkg |head -1|awk '{print $3}')
          echo "  \"$cmd\" version $pkgVer"
        fi
      fi
    else
      echo "  $cmd NOT FOUND"
      CMDS_MISSING="$CMDS_MISSING $cmd"
    fi
  done  

  if [ "l$LIBS_MISSING" != 'l' -o "c$CMDS_MISSING" != 'c' ]
  then
    if [ "l$LIBS_MISSING" != 'l' ]
    then
      echo
      echo "!! Missing system libaries: $LIBS_MISSING"
    fi

    if [ "l$CMDS_MISSING" != 'l' ]
    then
      echo
      echo "!! Missing comand(s): $CMDS_MISSING"
    fi
    
    echo "Please install all missing items and run the check again."
    exit 2
  fi

  # not required, but good to know  
  echo
  echo "**checking optional commands ..."
  CMDS="python lsof make gcc g++ redis-server"
  for cmd in $CMDS
  do
    if which $cmd >/dev/null 2>&1
    then
      if [ $cmd = 'python' ]
      then
        echo "  $(python -V 2>&1) found"
      else
        if [ $OS = 'RHEL' ]
        then 
          pkg=$( $PKGMGR $CMDOPT "$(which $cmd)")
          echo "  $cmd found in $pkg"
        else
          pkg=$( $PKGMGR $CMDOPT "$(which $cmd)" |awk 'BEGIN { FS = ":" } ; { print $1 }') 
          pkgVer=$( $PKGMGR $PKGMGROPT $pkg|grep $pkg |head -1|awk '{print $3}')
          echo "  \"$cmd\" version $pkgVer"
        fi
      fi
    else
      echo "  $cmd: NOT FOUND"
    fi
  done 

  echo
  echo "**checking required python modules ..."
  PyMod="Crypto ecdsa paramiko nose yaml setuptools fabric psutil kazoo elasticsearch requests"
  for pymod in $PyMod
  do
    if python -c "import $pymod" >/dev/null 2>&1
    then
      echo "  $pymod: found"
    else
      echo "  $pymod: NOT FOUND"
    fi
  done

  /bin/echo -e "\n= Gathering System information ="
  /bin/echo -e "\n---Host name: " `hostname`
  /bin/echo -e "\n---Arch:" `uname -a`

  if [ $OS = 'RHEL' ]
  then
    /bin/echo -e "\n---OS Family: `cat /etc/redhat-release`"
  else
    /bin/echo -e "\n---OS Family: `grep VERSION= /etc/os-release`"
  fi

  /bin/echo -e "\n---CPU:" 
    lscpu
    grep flags /proc/cpuinfo|head -1
  /bin/echo -e "\n---Memory:" 
    grep Mem /proc/meminfo 

  /bin/echo -e "\n---Disk space:" 
    df -h

  /bin/echo -e "\n---NIC and IP:" 
    if which ifconfig >/dev/null 2>&1
    then
      ifconfig -a|grep -v '127\|lo' | grep -B1 'inet '
    else 
      ip addr|grep -B1 'inet '
    fi

  /bin/echo -e "\n---NTP service:"
    if pgrep ntpd >/dev/null 2>&1
    then
      echo "NTP service is running."
    else 
      echo "NTP service is NOT running."
    fi

  /bin/echo -e "\n---Firewall Configuration:"
    if [ -f /etc/sysconfig/iptables ]
    then
      if which firewall-cmd >/dev/null 2>&1
      then
        echo -n Status: 
        firewall-cmd --state
        echo Rules:
        egrep -v '^#' /etc/sysconfig/iptables
      else
        iptables -L
      fi
    else
      ufw status verbose
      egrep -v '^#' /lib/ufw/user.rules
    fi

  if grep -v '^#' /etc/hosts.deny|grep -v '^ *$' > /dev/null 2>&1
  then
    /bin/echo -e "\n---TCP Wrapper Configuration:"
    egrep -v '^#' /etc/hosts.allow
  fi

  /bin/echo -e "\n---SSH Port Configuration:"
    grep 'Port ' /etc/ssh/sshd_config

  /bin/echo -e "\n---Outside Connection:"
    ping -c 3 -W 3 www.github.com | grep 'of data\|transmitted\|avg'
  /bin/echo 
  /bin/echo -e "Please review $report and send it to GraphSQL. Thank you!"
) 2>&1 | tee $report 
