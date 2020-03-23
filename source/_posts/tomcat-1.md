---
title: Tomcat整体结构概览
date: 2020-01-12 15:14:16
tags: [java, tomcat]
---

这里主要介绍一下 Tomcat 的整体设计结构

## 整体结构

Tomcat 的整体结构如下

<img src="/images/tomcat.png" style="zoom:30%" />

主要分为两大部分，连接器和容器

<!-- more -->

## 连接器

### ProtocolHandler

#### EndPoint

EndPoint 负责进行 TCP 监听连接，解析之后将消息转发给Processor

#### Processor

Processor 进行应用层对应的解析，如HTTP1.1协议，为请求和响应生成对应的Tomcat 的 Request 和 Response

 对象

### Adapter

Adapter 主要负责将 **Tomcat** 的 Request 和 Response对象转换为 **Servlet** 的 ServletRequest 和 ServletResponse 对象



## 容器

容器中也是分层的，从 Engine -> Host -> Context -> Wrapper，消息进行层层对位转发



## Server.xml

下面看一个具体 Tomcat 的 serverl.xml配置信息对应一下

```xml
<?xml version="1.0" encoding="UTF-8"?>

<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>

  <!-- 对应图中最外层的Service -->
  <Service name="Catalina">

    <!-- 对应图中上半部分的连接器 -->
    <Connector port="8080" protocol="HTTP/1.1"
               connectionTimeout="20000"
               redirectPort="8443" />

    <!-- 支持NIO的连接器 -->
    <!--
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="150" SSLEnabled="true">
        <SSLHostConfig>
            <Certificate certificateKeystoreFile="conf/localhost-rsa.jks"
                         type="RSA" />
        </SSLHostConfig>
    </Connector>
    -->
    

    <!-- AJP协议的连接器 -->
    <Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />


    <!-- 表示图中下半部分的最外层的 Engine -->
    <Engine name="Catalina" defaultHost="localhost">

      
      <Realm className="org.apache.catalina.realm.LockOutRealm">
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
               resourceName="UserDatabase"/>
      </Realm>

      <!-- 对应图中下半部分的 Host -->
      <Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="true">

        
        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="localhost_access_log" suffix=".txt"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />

      </Host>
    </Engine>
  </Service>
</Server>
```

