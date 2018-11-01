#!/usr/local/bin/bash

# $Id: $

# Backup script written by David Goddard for FreeBSD systems using ZFS
#
# Some parameters:
#
DATE=`date +%Y.%m.%d`
DATE_LONG=`date +%Y%m%d-%H%M`
DATE_LONG2=`date`
DEFAULT_BACKUPDIR='/backup/zfs'
DEFAULT_BACKUPLINKDIR=
DEFAULT_LOGFILE='/var/log/backup-zfs.log'
HOST=`hostname -s`
FILE_SUFFIX=".zfs"

LEVEL=$1
DATASET=$2


# Set umask
umask 026

DEEPEST_LEVEL=5

if [ $# -lt 2 ]; then
  echo 'You need to specify a level: 0-'$DEEPEST_LEVEL' and target to back up'
  exit 1
fi

if [[ ! $LEVEL =~ ^-?[0-9]+$ ]]; then
  echo "Level must be an integer"
  exit 1
fi

if [ $LEVEL -gt $DEEPEST_LEVEL ]; then
  echo 'Maximum level is: '$DEEPEST_LEVEL
  exit 1
fi

if [ $LEVEL -lt 0 ]; then
  echo 'Minimum level is: 0'
  exit 1
fi

dataset_test=`zfs list | cut -d ' ' -f 1 | grep -c \^${DATASET}\$`
if [ $dataset_test -eq 0 ]; then
  echo 'Target ZFS dataset does not exist: '$DATASET
  exit 1
fi

backup_dir=${DEFAULT_BACKUPDIR}
backup_linkdir=${DEFAULT_BACKUPLINKDIR}
logfile=${DEFAULT_LOGFILE}

echo "Performing level ${LEVEL} backup of ZFS dataset "${DATASET}" at "${DATE_LONG2}

# Enter start log entry:
echo `date +%Y-%m-%d`" "`date +%T`" - zfsbackup - S - level "${LEVEL}" - "${DATASET} >> ${logfile}

dataset_name_safe=${DATASET//\//-}
#echo "Dataset name: "$dataset_name_safe

this_snapshot_name='backup-level-'${LEVEL}
prior_snapshot_name=''

declare -a snapshots_to_delete
for (( lev=$DEEPEST_LEVEL; lev>=($LEVEL-1); lev-- ))
do
  this_name='backup-level-'${lev}
  if [ $lev -lt $LEVEL ]; then
    if [ $LEVEL -eq 0 ]; then
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
if [ $LEVEL -eq 0 ]; then
  echo "Will send full data for level 0"
else
  echo "Will send incremental changes since: "${prior_snapshot_name}
fi

for del in "${snapshots_to_delete[@]}"
do
  exist_count=`zfs list -t snapshot -o name,creation -s creation -r ${DATASET} | tail -1 | cut -d ' ' -f 1 | grep -c \@${del}\$`
  if [ $exist_count -gt 0 ]; then
    delete_snapshot=${DATASET}'@'${del}
    echo "Destroying existing snapshot: $delete_snapshot"
    zfs destroy $delete_snapshot
  fi
done

create_snapshot=${DATASET}'@'${this_snapshot_name}

echo "Creating snapshot: $create_snapshot"
zfs snapshot ${create_snapshot}

# Delete matching and lower level backup files
echo "Deleting old backup files..."
for (( lev=$DEEPEST_LEVEL; lev>=($LEVEL); lev-- ))
do
  deletefilepattern=`echo *'-'$HOST'-'$dataset_name_safe'-level'$lev$FILE_SUFFIX`
  #echo "Deleting past files: "$deletefilepattern
  rm -f ${backup_dir}/${deletefilepattern}
  rm -f ${backup_dir}/${deletefilepattern}.bz2
done

outputfile=`echo $DATE_LONG'-'$HOST'-'$dataset_name_safe'-level'$LEVEL$FILE_SUFFIX`
echo "Sending to new file: "$outputfile".bz2"

if [ $LEVEL -gt 0 ]; then
  zfs send -i ${DATASET}'@'${prior_snapshot_name} ${DATASET}'@'${this_snapshot_name} | bzip2 > ${backup_dir}/${outputfile}.bz2
else
  zfs send ${DATASET}'@'${this_snapshot_name} | bzip2 > ${backup_dir}/${outputfile}.bz2
fi

# Enter end log entry:
echo `date +%Y-%m-%d`" "`date +%T`" - zfsbackup - F - level "${LEVEL}" - "${DATASET} >> ${logfile}

echo "Completed level ${LEVEL} backup of ZFS dataset "${DATASET}" at "${DATE_LONG2}
