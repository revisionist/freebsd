#!/usr/local/bin/bash

# Backup script written by David Goddard for FreeBSD systems using Dump


DATE=`date +%Y.%m.%d`
DATE_LONG=`date +%Y%m%d-%H%M`
DATE_LONG2=`date`
DEFAULT_BACKUPDIR='/backup/dump'
DEFAULT_LOGFILE='/var/log/backup-dump.log'
HOST=`hostname -s`
FILE_SUFFIX="dmp"
GPG_CMD="gpg"
GPG_SUFFIX="enc"
DEEPEST_LEVEL=5


main() {

  backup_dir=${DEFAULT_BACKUPDIR}
  logfile=${DEFAULT_LOGFILE}
  level=-1
  filesystem=""
  compression=""
  gpgkey=""
  nodump=0
  umask 026

  OPTIND=1
  while getopts "h?l:d:t:o:c:e:n:" opt; do
      case "$opt" in
      h|\?)
          show_help
          exit 0
          ;;
      l)  level=$OPTARG
          ;;
      t)  backup_dir=$OPTARG
          ;;
      o)  logfile=$OPTARG
          ;;
      c)  compression=$OPTARG
          ;;
      e)  gpgkey=$OPTARG
          ;;
      n)  nodump=$OPTARG
          ;;
      esac
  done

  shift $((OPTIND-1))
  [ "${1:-}" = "--" ] && shift

  filesystems=("$@")
  filesystem_count=${#filesystems[@]}

  if [ ${filesystem_count} -eq 0 ]; then
    echo 'Please specify at least one  filesystem to back up' 
    exit 1
  fi

  if [[ ! $level =~ ^-?[0-9]+$ ]]; then
    echo "Level must be an integer"
    exit 1
  fi

  if [ $level -lt 0 ]; then
    echo 'Please specify a level in range 0 to '${DEEPEST_LEVEL}
    exit 1
  fi

  if [ $level -gt $DEEPEST_LEVEL ]; then
    echo 'Maximum level is: '$DEEPEST_LEVEL
    exit 1
  fi

  if [ ! -d $backup_dir ]; then
    echo 'Backup directory does not exist: '$backup_dir
   # exit 1
  fi

  if [ ! -w $backup_dir ]; then
    echo 'Backup directory is not writeable: '$backup_dir
    exit 1
  fi

  if [ ! -z $compression ]; then
	  if [ ! -x "$(command -v $compression)" ]; then
		echo 'Compression is not valid: '$compression
		exit 1
	fi
  fi
  
  if [ ! -z $nodump ]; then
    if [[ ! $nodump =~ ^-?[0-9]+$ ]]; then
		echo "Nodump level must be an integer"
		exit 1
	fi
  fi

  echo "Will perform level ${level} backups of ${filesystem_count} filesystems: "${filesystems[*]}

  for fs in "${filesystems[@]}"
  do
    backup_filesystem $fs
  done

  echo "Processed ${filesystem_count} filesystems: "${filesystems[*]}

}


show_help () {

  usage="
  $(basename "$0") [-h] [-t] [-o] [-e] -l <filesystems> -- incrementally back up FreeBSD filesystems to compressed files

  where:
    -h  show this help text
    -l  backup level (in range 0-${DEEPEST_LEVEL})
    -t  directory to output backups to (default: ${DEFAULT_BACKUPDIR})
    -o  log file to write to (default: ${DEFAULT_LOGFILE})
    -c  compression to use (i.e. /usr/bin/bzip2)
    -e  encrypt using GPG key
    -n  level to honour 'nodump' flag [i.e. -h parameter to dump(8)] (default: 0)

    <filesystems> - list of filesystems sets to back up, separated by spaces

  For example:

    $(basename "$0") -l 1 zroot/foo zroot/bar

     - level 1 backup of zroot/foo and zroot/bar

  Works by creating snapshots and sending differentials to file; a full
  (non-differential) backup is level 0.  Higher levels will be the difference
  between that level and the previous (i.e. level 2 is difference between
  snapshots for level 1 and level 2).

  Old backup files and snapshots matching same or higher level will be deleted.

  Ensure that you have taken a level 0 backup before running level 1, level 1
  before level 2, level 2 before level 3 and so on.
  "

  echo "$usage"

}

backup_filesystem () {

  filesystem=$1

  filesystem_test=`mount | cut -d ' ' -f 3 | grep -c \^${filesystem}\$`
  if [ $filesystem_test -eq 0 ]; then
    echo 'Target filesystem does not exist: '$filesystem
    return 1
  fi

  echo "Performing level ${level} dump of filesystem "${filesystem}" at "${DATE_LONG2}

  # Enter start log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - dump - S - level "${level}" - "${filesystem} >> ${logfile}

  filesystem_name_safe=${filesystem//\//-}
  #echo "filesystem name: "$filesystem_name_safe
  if [ $filesystem_name_safe == '-' ]; then
    filesystem_name_safe="-root"
  fi

  echo "Will create dump: "${this_dump_name}

  # Delete matching and lower level backup files
  echo "Deleting old backup files..."
  for (( lev=$DEEPEST_LEVEL; lev>=($level); lev-- ))
  do
    deletefilepattern=`echo *'-'$HOST$filesystem_name_safe'-level'$lev'.'$FILE_SUFFIX'*'`
    echo "Deleting past files: "$deletefilepattern
    rm -f ${backup_dir}/${deletefilepattern}
  done

  outputfile=`echo $DATE_LONG'-'$HOST$filesystem_name_safe'-level'$level'.'$FILE_SUFFIX`
  dumpcmd="dump -${level} -L -h ${nodump} -u -a -f - "${filesystem} 

  if [ ! -z ${compression} ]; then
	compressionsuffix=`echo ${compression} | rev | cut -d '/' -f 1 | rev`
	if [ ${compressionsuffix} == 'bzip2' ]; then
		compressionsuffix="bz2"
	if [ ${compressionsuffix} == 'pbzip2' ]; then
		compressionsuffix="bz2"
	elif [ ${compressionsuffix} == 'gzip' ]; then
		compressionsuffix="gz"
	fi
	echo "Will compress using: "${compression}
	#echo "Adding suffix: "${compressionsuffix}
	dumpcmd="${dumpcmd} | ${compression}"
	outputfile="${outputfile}.${compressionsuffix}"
  fi

  if [ ! -z $gpgkey ]; then
	outputfile="${outputfile}.${GPG_SUFFIX}"
	echo "Encrypting using GPG key: "${gpgkey}
	dumpcmd="${dumpcmd} | ${GPG_CMD} --encrypt --recipient ${gpgkey}"
  fi

  outputpath="${backup_dir}/${outputfile}"
  dumpcmd="${dumpcmd} > ${outputpath}"

  echo "Executing dump command: "${dumpcmd}
  #echo "Output file: "${outputfile}
  #echo "Output path: "${outputpath}

  eval ${dumpcmd}

  # Enter end log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - dump - F - level "${level}" - "${filesystem} >> ${logfile}

  echo "Completed level ${level} backup of filesystem "${filesystem}" at "${DATE_LONG2}

}


main "$@"
