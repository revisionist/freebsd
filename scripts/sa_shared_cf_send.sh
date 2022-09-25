#!/usr/local/bin/bash

# Script to sync local Sendmail shared configuration file to a secondary mail server.


DATE=`date +%Y.%m.%d`
DATE_LONG=`date +%Y%m%d-%H%M`
DATE_LONG2=`date`
DEFAULT_LOCAL_FILE='/usr/local/etc/mail/spamassassin/shared.cf'
DEFAULT_REMOTE_FILE='/usr/local/etc/mail/spamassassin/shared.cf'
DEFAULT_LOGFILE='/var/log/rsync_mail_sa.log'
HOST=`hostname -s`
DEFAULT_REMOTE_PORT=22
DEFAULT_REMOTE_USER=`whoami`


main() {

  logfile=${DEFAULT_LOGFILE}
  remote_user=${DEFAULT_REMOTE_USER}
  remote_port=${DEFAULT_REMOTE_PORT}
  local_file=${DEFAULT_LOCAL_FILE}
  remote_file=${DEFAULT_REMOTE_FILE}

  OPTIND=1
  while getopts "h?r:p:u:l:F:f:" opt; do
      case "$opt" in
      h)
          show_help
          exit 0
          ;;
      r)  remote_host=$OPTARG
          ;;
      p)  remote_port=$OPTARG
          ;;
      u)  remote_user=$OPTARG
          ;;
      l)  logfile=$OPTARG
          ;;
      F)  local_file=$OPTARG
          ;;
      f)  remote_file=$OPTARG
          ;;
      esac
  done

  shift $((OPTIND-1))
  [ "${1:-}" = "--" ] && shift

  if [ -z $remote_host ]; then
    echo 'Please specify a remote host'
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

  if [ "${remote_user}" == "root" ]; then
    echo "It is not supported to use root as remote user - please specify an alternative"
    exit 1
  fi

  if [ ! -r $local_file ]; then
    echo 'Local file is not readable: '$local_file
    exit 1
  fi

  if ! test_remote_file $remote_file ; then
    echo 'Remote file is not writeable: '$remote_file
    exit 1
  fi

  send_file

  echo "Done"

}


show_help () {

  usage="
  $(basename "$0") [-h] [-r] [-p] [-u] [-l] [-F] [-f] -- send the sa cf file to the remote host

  where:
    -h  show this help text
    -r  remote host
    -p  remote port to (default: ${DEFAULT_REMOTE_PORT})
    -u  remote user (default: ${DEFAULT_REMOTE_USER})
    -l  log file to write to (default: ${DEFAULT_LOGFILE})
    -F  local file (default: ${DEFAULT_LOCAL_FILE})
    -f  remote file (default: ${DEFAULT_REMOTE_FILE})

  For example:

    $(basename "$0") -h remoteserver.example.com -u mailadmin

  The script expects to be able to SSH to the remote host using passwordless authentication.
  "

  echo "$usage"

}


test_remote_file () {

  #echo "Testing that remote file is writeable: "$1

  test_cmd="ssh -p $remote_port -tt $remote_user@$remote_host 'test -w ${1}'"
  #echo "test_cmd: "${test_cmd}

  eval ${test_cmd} 2> /dev/null ; ec=$?

  #echo "Result: "${ec}
  if [ $ec -eq 0 ]; then
    return 0
  else
    return 1
  fi

}


send_file () {

  # Enter start log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - sending spamassassin shared local configuration (blacklists etc.) ${local_file} to ${remote_host}" >> ${logfile}

  /usr/local/bin/rsync -va --no-r -d -e 'ssh -p '${remote_port} --delete-after --exclude 'CVS' $local_file ${remote_user}@${remote_host}:${remote_file} >> ${logfile}
 
  # Enter end log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - sent ${remote_host}:${remote_file}" >> ${logfile}

}


main "$@"
