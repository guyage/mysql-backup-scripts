# mysql-backup-scripts

## 物理备份和逻辑备份脚本
* xtrabackup文件夹为物理备份
  * 物理备份可配置备份到本地或远端服务器(不落地备份)，采用流备份，科并行效率高
  * 流备份解压,需安装qpress，安装包在文件夹里，解压即可(tar xvf qpress-11-linux-x64.tar && cp qpress /usr/bin)
  ```bash 
  xbstream -x < xxxxxx.xbstream -C ./restore 
  cd restore
  for f in `find ./ -iname "*\.qp"`; do qpress -dT2 $f  $(dirname $f) && rm -f $f; done
  ```
* mydumper文件夹为逻辑备份
  * 逻辑备份可配置备份到本地或远端服务器，备份远端为先备份到本地，再通过rsync传至远端服务器
* delete_obsolete_backup文件夹为删除指定保留日期文件删除脚本

## 使用方法：
* 物理备份
  * 安装xtrabackup
  * 修改配置文件
  * 添加crontab(0 0 * * * /xtrabackup.sh -f xtraBackup_full_3306.cnf &> /tmp/xtrabackup_3306.log)
  * 配置微信企业号，可微信通知
* 逻辑备份
  * 安装mydumper
  * 修改配置文件
  * 添加crontab(0 0 * * * /mydumper.sh -f -f mydumper_3306.cnf &> /tmp/mydumper_3306.log)
  * 配置微信企业号，可微信通知
