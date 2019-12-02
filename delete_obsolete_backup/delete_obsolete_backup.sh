#!/bin/bash

function delete_obsolete(){
# arg1 is backup basedir
# arg2 is databases backup dir
# arg3 is retention days
    FIND_CMD=/bin/find
    BACKUPDIR=$1
    DATABASEDIR=$2
    RETENTION=$3
    CHECKDIR=${BACKUPDIR}/${DATABASEDIR}
    BAK_DIR_LOG=${BACKUPDIR}/backup_delete.log
    cd ${CHECKDIR}
    if [ $? -ne 0 ]
    then
        echo `date` >> ${BAK_DIR_LOG}
        echo "change directory failed" >> ${BAK_DIR_LOG}
        exit 9
    fi

    if [ -d ${CHECKDIR} ]
    then
        echo `date` >> ${BAK_DIR_LOG}
        find ${CHECKDIR}  -ctime  +${RETENTION} >>${BAK_DIR_LOG}
        find ${CHECKDIR}  -ctime  +${RETENTION}| xargs rm -rf >> ${BAK_DIR_LOG}
    fi
}
# delete mydumper backupsets
delete_obsolete "/backup/fullBackup" 3306 10
