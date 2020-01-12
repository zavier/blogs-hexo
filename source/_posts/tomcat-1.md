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