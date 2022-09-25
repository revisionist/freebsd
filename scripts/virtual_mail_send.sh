#!/usr/local/bin/bash

# Script to sync local mail configuration files (i.e. contents of virtual
# email directory) to a backup mail server.


DATE=`date +%Y.%m.%d`
DATE_LONG=`date +%Y%m%d-%H%M`
DATE_LONG2=`date`
DEFAULT_LOCAL_DIR='/etc/mail/virtual'
DEFAULT_REMOTE_DIR='/etc/mail/virtual'
DEFAULT_LOGFILE='/var/log/rsync_mail.log'
HOST=`hostname -s`
DEFAULT_REMOTE_PORT=22
DEFAULT_REMOTE_USER=`whoami`


main() {

  mail_dir=${DEFAULT_BACKUPDIR}
  logfile=${DEFAULT_LOGFILE}
  remote_port=${DEFAULT_REMOTE_PORT}
  local_parentdir=${DEFAULT_LOCAL_DIR}
  remote_parentdir=${DEFAULT_REMOTE_DIR}
  remote_user=${DEFAULT_REMOTE_USER}

  OPTIND=1
  while getopts "h?d:D:l:r:p:u:" opt; do
      case "$opt" in
      h)
          show_help
          exit 0
          ;;
      d)  local_parentdir=$OPTARG
          ;;
      D)  remote_parentdir=$OPTARG
          ;;
      l)  logfile=$OPTARG
          ;;
      r)  remote_host=$OPTARG
          ;;
      p)  remote_port=$OPTARG
          ;;
      u)  remote_user=$OPTARG
          ;;
      esac
  done

  shift $((OPTIND-1))
  [ "${1:-}" = "--" ] && shift

  mailsubdirs=("$@")
  mailsubdir_count=${#mailsubdirs[@]}

  if [ -z $remote_host ]; then
    echo 'Please specify a remote host'
    exit 1
  fi

  if [ ${mailsubdir_count} -eq 0 ]; then
    echo 'Please specify at least one subdir to send'
    exit 1
  fi

  if [ "${remote_user}" == "root" ]; then
    echo "It is not supported to use root as remote user - please specify an alternative"
    exit 1
  fi

  if [[ ! $remote_port =~ ^-?[0-9]+$ ]]; then
    echo 'Remote port must be an integer'
    exit 1
  fi

  if [ $remote_port -lt 0 ]; then
    echo 'Please specify a valid remote port!'
    exit 1
  fi

  if [ ! -d $local_parentdir ]; then
    echo 'Local mail directory does not exist: '$local_parentdir
    exit 1
  fi

  if [ "${local_parentdir}" == "/" ]; then
    echo "It is not supported to use / as local directory - please specify an alternative"
    exit 1
  fi

  if [ "${remote_parentdir}" == "/" ]; then
    echo "It is not supported to use / as remote directory - please specify an alternative"
    exit 1
  fi

  if ! test_remote_directory $remote_parentdir ; then
    echo 'Remote mail directory does not exist: '$remote_parentdir
    exit 1
  fi

  for subdir in "${mailsubdirs[@]}"
  do
    send_directory $subdir
  done

  echo "Processed ${mailsubdir_count} items: "${mailsubdirs[*]}

}


show_help () {

  usage="
  $(basename "$0") [-h] [-d] [-D] [-l] [-r] [-p] [-u] <mailsubdirs> -- send the specified virtual mail subdirectories to the remote host

  where:
    -h  show this help text
    -d  local parent directory containing virtual mail subdirs (default: ${DEFAULT_LOCAL_DIR})
    -D  remote parent directory containing virtual mail subdirs (default: ${DEFAULT_LOCAL_DIR})
    -l  log file to write to (default: ${DEFAULT_LOGFILE})
    -r  remote host
    -p  remote port to (default: ${DEFAULT_REMOTE_PORT})
    -u  remote user (default: ${DEFAULT_REMOTE_USER})

    <mailsubdirs> - list of subdirectories to send, separated by spaces

  For example:

    $(basename "$0") -h remoteserver.example.com virtual.domainA virtual.domainB

     - send virtual domain directories virtual.domainA and virtual.domainB

  This script is intended to send virtual mail directories to a remote mail server.
  
  It expects to be able to SSH to the remote host using passwordless authentication.
  "

  echo "$usage"

}


test_remote_directory () {

  #echo "Testing that remote directory exists: "$1

  test_cmd="ssh -p $remote_port -tt $remote_user@$remote_host 'test -d ${1}'"
  #echo "test_cmd: "${test_cmd}

  eval ${test_cmd} 2> /dev/null ; ec=$?

  #echo "Result: "${ec}
  if [ $ec -eq 0 ]; then
    return 0
  else
    return 1
  fi

}


send_directory () {

  directory=$1

  local_dir=${local_parentdir}/${directory}

  # Enter start log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - sending ${local_dir} to ${remote_host}" >> ${logfile}

  if [ ! -d $local_dir ]; then
    echo 'Directory send failure - does not exist locally: '$local_dir
    return 1
  fi

  /usr/local/bin/rsync -va --no-r -d -e 'ssh -p '${remote_port} --delete-after --exclude 'CVS' $local_dir/ ${remote_user}@${remote_host}:${remote_parentdir}/${directory}/ >> ${logfile}

  # Enter end log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - sent ${remote_host}:${local_dir}" >> ${logfile}

}


main "$@"
