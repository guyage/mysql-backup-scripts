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
checkBackup=$(dirname $0)/checkDumperBak.py
IP=$(/sbin/ifconfig|grep -E 'addr:172|addr:192|addr:10'|awk '{sub(/addr:/,"",$2);print $2|"head -1"}')

#######################################################################################################
Date=$(date +"%Y%m%d")
YearMonth=$(date +"%Y%m")
backupLogDir=$backupDir/backupLog
backupInfoDir=$backupDir/backupInfo
backupDst=$backupDir/$mysqlPort/$Date

#######################################################################################################
dumperCmd() {
 local connType=$1
 local connPath=$2
 case $connType in 
   socket ) if [[ -n "$mysqlPwd" ]];then
             dumper="$basedir/bin/mydumper -u $mysqlUser -p $mysqlPwd -S $connPath"
            else
             dumper="$basedir/bin/mydumper -u $mysqlUser -S $connPath"  
            fi ;;            
   port  ) if [[ -n "$mysqlPwd" ]];then
            dumper="$basedir/bin/mydumper -u $mysqlUser -p $mysqlPwd -h $mysqlHost -P $connPath"
           else            
            dumper="$basedir/bin/mydumper -u $mysqlUser -h $mysqlHost -P $connPath"
           fi ;; 
   esac
}

#######################################################################################################
connType=${connection%:*}
case $connType in
 socket ) socket=${connection#*:} 
          dumperCmd socket $socket ;;
 port   ) port=${connection#*:} 
          dumperCmd port $port ;;
 *      ) usage ;;
 esac

#######################################################################################################
[[ -e $backupDir ]] || mkdir -p $backupDir
[[ -e $backupLogDir ]] || mkdir -p $backupLogDir
[[ -e $backupInfoDir ]] || mkdir -p $backupInfoDir
[[ -e $backupDst ]] || mkdir -p $backupDst

#######################################################################################################
find $backupLogDir -mindepth 1 -maxdepth 1 -type f -mtime +90|xargs -I {} rm -f {}
find $backupInfoDir -mindepth 1 -maxdepth 1 -type f -mtime +14|xargs -I {} rm -f {}

#######################################################################################################
removeOldBak() {
 local threshold=$(date -d"$preserveDay day ago" +"%Y%m%d")
 local AWK="awk -v D=\$threshold 'BEGIN {FS=\"/\"} {if(\$NF<D) print \$0}'" 
 local bakDir=$(find ${backupDst%/*} -mindepth 1 -maxdepth 1 -type d -regextype posix-egrep -regex '.*[[:digit:]]{8}'|eval $AWK)
 local bak=
 local logFile=$backupLogDir/remove_${YearMonth}_${mysqlPort}.log
 [[ ${#bakDir[@]} -eq 0 ]] && return 1
 for bak in ${bakDir[@]}
 do
   if [[ $bak != / ]];then
     rm -rf $bak  
     if [[ ! -e $bak ]];then
       echo "$(date +"%F %T") | remove $bak succeed" >> $logFile
     else
       echo "$(date +"%F %T") | remove $bak failed" >> $logFile
     fi
   fi
 done
}

#######################################################################################################
rSyncScp() {
   local bakDir=$1
   local rSyncScpOutput=$backupLogDir/${dstHost}_rSyncScp.${mysqlPort}.$Date
   local logFile=$backupLogDir/rsync_${YearMonth}_${mysqlPort}.log
   expect &> $rSyncScpOutput <<EOF
   set timeout -1
   spawn rsync -avCr -P -e "ssh -p $dstPort" $bakDir $dstUser@$dstHost:$dstDir
   expect {
     "(yes/no)?"  {send "yes\r";exp_continue}
     "*assword*"  {send "$dstPass\r";exp_continue}
      eof  exit
   }  
EOF
  local lastLine=$(tail -1 $rSyncScpOutput|sed -nre '/total[[:space:]]+size[[:space:]]+is.*speedup.*/ p')
  if [[ -n "$lastLine" ]];then
     echo "$(date +"%F %T") | transfer $bakDir to ${dstHost}@$dstDir succeed" >> $logFile
     return 0
  else
     echo "$(date +"%F %T") | transfer $bakDir to ${dstHost}@$dstDir failed" >> $logFile
     return 1
  fi
         
}

#######################################################################################################
backupMySQL() {
 local infoFile=$backupInfoDir/mydumper_${Date}_${mysqlPort}.info
 local logFile=$backupLogDir/mydumper_${YearMonth}_${mysqlPort}.log
 local text=
 [[ $backupDst != / ]] && rm -f $backupDst/*
 $dumper $db $routine $longQuery $splitTbl $compress $opt -o $backupDst -v 3 -L $infoFile
 local lastline=$(awk --re-interval '$1 ~ /[0-9]{4}-[0-9]{2}-[0-9]{2}/ {print $0|"tail -1"}' $infoFile)
 if [[ $lastline =~ Finished[[:space:]]dump[[:space:]]at.* ]];then
   echo "$(date +"%F %T") | $mysqlPort | backup succeed - $backupDst" >> $logFile
   [[ $removeOldFile = Yes ]] && removeOldBak 
   if [[ $enableRsync = Yes ]];then
     rSyncScp $backupDst
     local returnCode=$?
     [[ $returnCode -eq 0 ]] && text="| rsync:succeed - host:$dstHost" 
     [[ $returnCode -eq 1 ]] && text="| rsync:failed - host:$dstHost" 
   else
     text=
   fi
   if [[ $checkBak -eq 1 ]];then
       i=1
       while [[ $i -le $retries ]]
         do
           ((i++))
           $checkBackup $toUser "$(date +"%F %T") | ${IP}:$mysqlPort:$backupdbname | backup_type:$backuptype | backup succeed $text"
           if [[ $? -eq 10 ]];then
              sleep 2s
              continue
           else
              break
           fi
         done
   fi      
 else
   echo "$(date +"%F %T") | $mysqlPort | backup failed - $backupDst" >> $logFile
   if [[ $checkBak -eq 1 ]];then
      i=1
      while [[ $i -le $retries ]]
        do
          ((i++))
          $checkBackup $toUser "$(date +"%F %T") | ${IP}:$mysqlPort:$backupdbname | backup_type:$backuptype | backup failed"
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
backupMySQL
