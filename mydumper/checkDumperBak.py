#!/usr/bin/env python
#coding:utf-8
import urllib,urllib2,sys,json
reload(sys)
sys.setdefaultencoding('utf-8')

if len(sys.argv)-1!=2:sys.exit()

###团队企业微信号
corpidSecret={
              '企业号':'密钥'
             }

###微信消息内容和接收消息的用户
user=sys.argv[1].split(':')[0]
info=sys.argv[2]

###获取令牌
def getToken(corpid,corpsecret):
    url1='https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid='
    url=url1+corpid+'&corpsecret='+corpsecret
    try:
        request=urllib2.Request(url)
        openUrl=urllib2.urlopen(request,timeout=5)
    except urllib2.HTTPError,e:
        print e.code
        sys.exit(10)
    except urllib2.URLError,e:
        print e.reason
        sys.exit(10)
    else:
        tokenDic=openUrl.read()
        tokenJson=json.loads(tokenDic)
        token=tokenJson['access_token']
        return token

###向微信企业号发布消息
def sendWechat(accessToken,user,info):
    url1='https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token='
    url=url1+accessToken
    text={
    "touser":user,     
    "msgtype":"text",  
    "agentid":"1000002",
    "text":{"content":info},
    "safe":"0"
    }
    data=json.dumps(text,ensure_ascii=False)
    try:
        request=urllib2.Request(url,data)
        openUrl=urllib2.urlopen(request,timeout=5)
        print user
        print openUrl.read()
    except urllib2.HTTPError,e:
        print e.code
        sys.exit(10)
    except urllib2.URLError,e:
        print e.reason
        sys.exit(10)

if __name__=='__main__':
    for (corpid,corpsecret) in corpidSecret.items(): 
        accesstoken=getToken(corpid,corpsecret)
        if accesstoken:
            sendWechat(accesstoken,user,info)
            user=sys.argv[1].split(':')[1]
