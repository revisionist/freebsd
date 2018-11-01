#!/usr/local/bin/bash

# $Id: $

# Backup script written by David Goddard for FreeBSD systems using ZFS

DATE=`date +%Y.%m.%d`
DATE_LONG=`date +%Y%m%d-%H%M`
DATE_LONG2=`date`
DEFAULT_BACKUPDIR='/backup/zfs'
DEFAULT_LOGFILE='/var/log/backup-zfs.log'
HOST=`hostname -s`
FILE_SUFFIX=".zfs"
DEEPEST_LEVEL=5


main() {

  backup_dir=${DEFAULT_BACKUPDIR}
  logfile=${DEFAULT_LOGFILE}
  level=-1
  dataset=""
  umask 026

  OPTIND=1
  while getopts "h?l:d:t:o:" opt; do
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
      esac
  done

  shift $((OPTIND-1))
  [ "${1:-}" = "--" ] && shift

  datasets=("$@")
  dataset_count=${#datasets[@]}

  if [ ${dataset_count} -eq 0 ]; then
    echo 'Please specify at least one ZFS dataset to back up' 
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

  echo "Will perform level ${level} backups of ${dataset_count} datasets: "${datasets[*]}

  for ds in "${datasets[@]}"
  do
    backup_dataset $ds
  done

  echo "Processed ${dataset_count} datasets: "${datasets[*]}

}


show_help () {

  usage="
  $(basename "$0") [-h] [-t] [-o] -l <datasets> -- incrementally back up ZFS datasets to compressed files

  where:
    -h  show this help text
    -l  backup level (in range 0-${DEEPEST_LEVEL})
    -t  directory to output backups to (default: ${DEFAULT_BACKUPDIR})
    -o  log file to write to (default: ${DEFAULT_LOGFILE})

    <datasets> - list of ZFS data sets to back up, separated by spaces

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

backup_dataset () {

  dataset=$1

  dataset_test=`zfs list | cut -d ' ' -f 1 | grep -c \^${dataset}\$`
  if [ $dataset_test -eq 0 ]; then
    echo 'Target ZFS dataset does not exist: '$dataset
    return 1
  fi

  echo "Performing level ${level} backup of ZFS dataset "${dataset}" at "${DATE_LONG2}

  # Enter start log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - zfsbackup - S - level "${level}" - "${dataset} >> ${logfile}

  dataset_name_safe=${dataset//\//-}
  #echo "Dataset name: "$dataset_name_safe

  this_snapshot_name='backup-level-'${level}
  prior_snapshot_name=''

  declare -a snapshots_to_delete
  for (( lev=$DEEPEST_LEVEL; lev>=($level-1); lev-- ))
  do
    this_name='backup-level-'${lev}
    if [ $lev -lt $level ]; then
      if [ $level -eq 0 ]; then
        prior_snapshot_name=''  # special case
      else
        prior_snapshot_name=${this_name}
      fi
    else
      snapshots_to_delete+=(${this_name})
    fi
  done

  echo "Will delete these snapshots if they exist: "${snapshots_to_delete[*]}
  echo "Will create snapshot: "${this_snapshot_name}
  if [ $level -eq 0 ]; then
    echo "Will send full data for level 0"
  else
    echo "Will send incremental changes since: "${prior_snapshot_name}
  fi

  for del in "${snapshots_to_delete[@]}"
  do
    exist_count=`zfs list -t snapshot -o name,creation -s creation -r ${dataset} | tail -1 | cut -d ' ' -f 1 | grep -c \@${del}\$`
    if [ $exist_count -gt 0 ]; then
      delete_snapshot=${dataset}'@'${del}
      echo "Destroying existing snapshot: $delete_snapshot"
      zfs destroy $delete_snapshot
    fi
  done

  create_snapshot=${dataset}'@'${this_snapshot_name}

  echo "Creating snapshot: $create_snapshot"
  zfs snapshot ${create_snapshot}

  # Delete matching and lower level backup files
  echo "Deleting old backup files..."
  for (( lev=$DEEPEST_LEVEL; lev>=($level); lev-- ))
  do
    deletefilepattern=`echo *'-'$HOST'-'$dataset_name_safe'-level'$lev$FILE_SUFFIX`
    #echo "Deleting past files: "$deletefilepattern
    rm -f ${backup_dir}/${deletefilepattern}
    rm -f ${backup_dir}/${deletefilepattern}.bz2
  done

  outputfile=`echo $DATE_LONG'-'$HOST'-'$dataset_name_safe'-level'$level$FILE_SUFFIX`
  echo "Sending to new file: "$outputfile".bz2"

  if [ $level -gt 0 ]; then
    zfs send -i ${dataset}'@'${prior_snapshot_name} ${dataset}'@'${this_snapshot_name} | bzip2 > ${backup_dir}/${outputfile}.bz2
  else
    zfs send ${dataset}'@'${this_snapshot_name} | bzip2 > ${backup_dir}/${outputfile}.bz2
  fi

  # Enter end log entry:
  echo `date +%Y-%m-%d`" "`date +%T`" - zfsbackup - F - level "${level}" - "${dataset} >> ${logfile}

  echo "Completed level ${level} backup of ZFS dataset "${dataset}" at "${DATE_LONG2}

}


main "$@"