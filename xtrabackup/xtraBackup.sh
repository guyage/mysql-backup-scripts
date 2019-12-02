#!/bin/bash

usage() {
  cat <<EOF  
USAGE : $0 -f configFileName
EOF
exit 1
}

#######################################################################################################
[[ $# -ne 2 ]] && usage

#######################################################################################################
while getopts :f: opt
do
 case $opt in
  f ) configFile=$OPTARG ;;
  * ) usage ;;
 esac
done

#######################################################################################################
[[ -s $(dirname $0)/$configFile ]] && . $(dirname $0)/$configFile || usage
checkBackup=$(dirname $0)/checkXtraBak.py
IP=$(/sbin/ifconfig|grep -E 'addr:172|addr:192|addr:10'|awk '{sub(/addr:/,"",$2);print $2|"head -1"}')

#######################################################################################################
Date=$(date +"%Y%m%d")
YearMonth=$(date +"%Y%m")
if [[ $backupType = full ]];then
  backupLogDir=$backupDir/fullBackup/backupLog
  backupInfoDir=$backupDir/fullBackup/backupInfo
  backupDst=$backupDir/fullBackup/$mysqlPort
  backupTmp=$backupDir/fullBackup/tmp/$mysqlPort/$Date
  lastLsnDir=$backupDir/fullBackup/lastLsn/$mysqlPort/$Date
  lsnStored=$backupDir/lsn/$mysqlPort/lastLsn
elif [[ $backupType = incremental ]];then
  backupLogDir=$backupDir/incrBackup/backupLog
  backupInfoDir=$backupDir/incrBackup/backupInfo
  backupDst=$backupDir/incrBackup/$mysqlPort
  backupTmp=$backupDir/incrBackup/tmp/$mysqlPort/$Date
  lastLsnDir=$backupDir/incrBackup/lastLsn/$mysqlPort/$Date
  lsnStored=$backupDir/lsn/$mysqlPort/lastLsn
fi

#######################################################################################################
xtraCmd() {
 local connType=$1
 local connPath=$2
 case $connType in 
   socket ) if [[ -n "$mysqlPwd" ]];then
             innobackup="$basedir/bin/innobackupex --defaults-file=$defaultsFile --user=$mysqlUser --password=$mysqlPwd --socket=$connPath"
            else
             innobackup="$basedir/bin/innobackupex --defaults-file=$defaultsFile --user=$mysqlUser --socket=$connPath"  
            fi ;;            
   port  ) if [[ -n "$mysqlPwd" ]];then
            innobackup="$basedir/bin/innobackupex --defaults-file=$defaultsFile --user=$mysqlUser --password=$mysqlPwd --host=$mysqlHost --port=$connPath"
           else            
            innobackup="$basedir/bin/innobackupex --defaults-file=$defaultsFile --user=$mysqlUser --host=$mysqlHost --port=$connPath"
           fi ;; 
   esac
}

#######################################################################################################
connType=${connection%:*}
case $connType in
 socket ) socket=${connection#*:} 
          xtraCmd socket $socket ;;
 port   ) port=${connection#*:} 
          xtraCmd port $port ;;
 *      ) usage ;;
 esac

#######################################################################################################
[[ -e $backupDir ]] || mkdir -p $backupDir
[[ -e $backupLogDir ]] || mkdir -p $backupLogDir
[[ -e $backupInfoDir ]] || mkdir -p $backupInfoDir
[[ -e $backupDst ]] || mkdir -p $backupDst
[[ -e $backupTmp ]] || mkdir -p $backupTmp
[[ -e $lastLsnDir ]] || mkdir -p $lastLsnDir
[[ -e ${lsnStored%/*} ]] || mkdir -p ${lsnStored%/*}

#######################################################################################################
find $backupLogDir -mindepth 1 -maxdepth 1 -type f -mtime +90|xargs -I {} rm -f {}
find $backupInfoDir -mindepth 1 -maxdepth 1 -type f -mtime +14|xargs -I {} rm -f {}
find ${backupTmp%/*} -mindepth 1 -maxdepth 1 -type d -mtime +7|xargs -I {} rmdir {}
find ${lastLsnDir%/*} -mindepth 1 -maxdepth 1 -type d -mtime +90|xargs -I {} rm -rf {}

#######################################################################################################
fullBackup(){
  local infoFile=$backupInfoDir/xtra_${Date}_${mysqlPort}.info 
  local logFile=$backupLogDir/xtra_${YearMonth}_${mysqlPort}.log
  local compact=
  local xbFile=xbstream_${IP}_$Date
  [[ $remoteBackup = No && -f $backupDst/$xbFile ]] && rm -f $backupDst/$xbFile
  [[ $noSecIndex = --compact ]] && compact=1 || compact=0
  innoBackupex="$innobackup --no-timestamp $slaveOpt $lockOpt $noSecIndex --parallel=$threads $stream --extra-lsndir=$lastLsnDir"
  if [[ $remoteBackup = No ]];then
    $innoBackupex --tmpdir=$backupTmp $compress $backupTmp > $backupDst/$xbFile 2> $infoFile
    text="$backupDst/$xbFile"
  elif [[ $remoteBackup = Yes ]];then
    ssh -p $dstPort $dstUser@$dstHost "[[ -e $dstDir ]] || mkdir -p $dstDir"
    $innoBackupex --tmpdir=$backupTmp $compress $backupTmp 2> $infoFile|ssh -p $dstPort $dstUser@$dstHost "cat - > $dstDir/$xbFile"
    text="${dstHost}@$dstDir/$xbFile"
  fi
  local lastline=$(tail -1 $infoFile)
  if [[ $lastline =~ .*completed[[:space:]]OK.* ]];then     
     echo "$(date +"%F %T") | $mysqlPort | compact: $compact | backup succeed - $text" >> $logFile     
     echo -e "LSN:$lastLsnDir\nfileName:$text" > $lsnStored
     if [[ $checkBak -eq 1 ]];then
       i=1
       while [[ $i -le $retries ]]
         do
           ((i++))
           $checkBackup $toUser "$(date +"%F %T") | ${IP}:$mysqlPort:$backupdbname | backup_type:$backuptype | full backup succeed"
           if [[ $? -eq 10 ]];then
              sleep 2s
              continue
           else
              break
           fi
         done
     fi         
  else     
    echo "$(date +"%F %T") | $mysqlPort | compact: $compact | backup failed - $text" >> $logFile
    if [[ $checkBak -eq 1 ]];then
      i=1
      while [[ $i -le $retries ]]
        do
          ((i++))
          $checkBackup $toUser "$(date +"%F %T") | ${IP}:$mysqlPort:$backupdbname | backup_type:$backuptype | full backup failed"
          if [[ $? -eq 10 ]];then
             sleep 2s
             continue
          else
             break
          fi
        done
    fi    
  fi
}

#######################################################################################################
incrBackup() {
  local infoFile=$backupInfoDir/xtra_${Date}_${mysqlPort}.info
  local logFile=$backupLogDir/xtra_${YearMonth}_${mysqlPort}.log  
  local compact= 
  local xbFile=xbstream_${IP}_$Date
  [[ $remoteBackup = No && -f $backupDst/$xbFile ]] && rm -f $backupDst/$xbFile
  [[ $noSecIndex = --compact ]] && compact=1 || compact=0
  if [[ -e $lsnStored ]];then
    lsnDir=$(awk -F ':' '$1 ~ /LSN/ {print $2}' $lsnStored)
    baseFile=$(awk -F ':' '$1 ~ /fileName/ {print $2}' $lsnStored)
    [[ ! -e $lsnDir ]] && echo "Cannot find last lsn" && exit 3
    if [[ ! -e $baseFile ]];then
      if [[ $remoteBackup = No ]];then  
        echo "Cannot find incremental basefile" && exit 4
      elif [[ $remoteBackup = Yes ]];then
        if [[ $(ssh -p $dstPort $dstUser@$dstHost 2> /dev/null "[[ -e $(awk -F '@' '{print $2}' <<< $baseFile) ]] && echo 1 || echo 0") -eq 0 ]];then
          echo "Cannot find incremental basefile on $dstHost" && exit 5
        fi
      fi
    fi
  else
     echo "Cannot the file in which last lsn and incremental basefile stored" && exit 2
  fi
  local incrOpt="--incremental --incremental-basedir=$lsnDir" 
  innoBackupex="$innobackup --no-timestamp $slaveOpt $lockOpt $noSecIndex --parallel=$threads $incrOpt $stream --extra-lsndir=$lastLsnDir"
  if [[ $remoteBackup = No ]];then
    $innoBackupex --tmpdir=$backupTmp $compress $backupTmp > $backupDst/$xbFile 2> $infoFile 
    text="$backupDst/$xbFile"
  elif [[ $remoteBackup = Yes ]];then
    ssh -p $dstPort $dstUser@$dstHost "[[ -e $dstDir ]] || mkdir -p $dstDir"
    $innoBackupex --tmpdir=$backupTmp $compress $backupTmp 2> $infoFile|ssh -p $dstPort $dstUser@$dstHost "cat - > $dstDir/$xbFile"
    text="${dstHost}@$dstDir/$xbFile"
  fi 
  local lastline=$(tail -1 $infoFile)
  if [[ $lastline =~ .*completed[[:space:]]OK.* ]];then 
     echo -e "LSN:$lastLsnDir\nfileName:$text" > $lsnStored
     echo "$(date +"%F %T") | $mysqlPort | compact: $compact | backup succeed - $text" >> $logFile     
     echo "$(date +"%F %T") | $mysqlPort | compact: $compact | incremental basefile - $baseFile" >> $logFile     
     if [[ $checkBak -eq 1 ]];then
       i=1
       while [[ $i -le $retries ]]
         do
           ((i++))
           $checkBackup $toUser "$(date +"%F %T") | ${IP}:$mysqlPort:$backupdbname | backup_type:$backuptype | incremental backup succeed"
           if [[ $? -eq 10 ]];then
              sleep 2s
              continue
           else
              break
           fi
         done
     fi         
  else 
    echo "$(date +"%F %T") | $mysqlPort | compact: $compact | backup failed - $text" >> $logFile
    if [[ $checkBak -eq 1 ]];then
       i=1
       while [[ $i -le $retries ]]
         do
           ((i++))
           $checkBackup $toUser "$(date +"%F %T") | ${IP}:$mysqlPort:$backupdbname | backup_type:$backuptype | incremental backup failed"
           if [[ $? -eq 10 ]];then
              sleep 2s
              continue
           else
              break
           fi
         done
    fi         
  fi  
}

#######################################################################################################
case $backupType in
 full ) fullBackup ;;
 incremental ) incrBackup ;;
esac
