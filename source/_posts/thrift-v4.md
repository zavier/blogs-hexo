---
title: Thrift-Java注解方式
date: 2022-05-29 15:34:46
tags: [java, thrift]
---

Thrift的service可以使用跨语言的IDL来定义，之后可以通过工具生成对应语言的代码，但是对于都是Java服务间的调用来说，还有一种简单的方式，可以通过定义类+使用注解的方式，来达到与IDL基本相同的效果，但是这种方式因为没有自动生成的代码，所以需要一套库来进行支持将对应结构进行序列化与反序列化

<!-- more -->

IDL中的类型基本在Java中都有对应的类

| IDL     | 对应Java                    |
| ------- | --------------------------- |
| bool    | java.lang.Boolean / boolean |
| byte    | java.lang.Byte / byte       |
| i16     | java.lang.Short / short     |
| i32     | java.lang.Integer / int     |
| i64     | java.lang.Long / long       |
| double  | java.lang.Double / double   |
| string  | java.lang.String            |
| binary  | byte[]                      |
| struct  | java类 / class              |
| list    | java.uti.List               |
| map     | java.util.Map               |
| set     | java.util.Set               |
| service | java接口 / interface        |

同时，在[上一篇](/2021/12/19/thrift-v3/)我们也介绍了TBinaryProtocol序列化的消息结构，这样只需要将Java类按照对应的类型转换成消息结构进行发送，接收的时候再按照消息结构进行解析创建类即可

这个目前已经有库进行了实现，这里以[drift](https://github.com/prestodb/drift)为例进行一下功能的简单分析

## drift使用

首先需要引入如下包

```xml
<!-- 服务端依赖包 -->
<dependency>
    <groupId>com.facebook.drift</groupId>
    <artifactId>drift-server</artifactId>
    <version>1.34</version>
</dependency>
<!-- 客户端依赖包 -->
<dependency>
    <groupId>com.facebook.drift</groupId>
    <artifactId>drift-client</artifactId>
    <version>1.34</version>
</dependency>
<!-- netty网络传输依赖包 -->
<dependency>
    <groupId>com.facebook.drift</groupId>
    <artifactId>drift-transport-netty</artifactId>
    <version>1.34</version>
</dependency>
```

### 接口定义

这个接口定义一般会单独在一个单独的jar包中，打包后可以被客户端和服务端分别引入依赖

```java
@ThriftService
public interface DemoService {
    @ThriftMethod
    String echo(String message);
}
```

### 服务实现及发布

```java
// 服务实现
public class DemoServiceImpl implements DemoService {
    @Override
    public String echo(String message) {
        return message;
    }
}

// 服务发布
// 1. 服务实例化
DemoService obj = new DemoServiceImpl();
// 2. 配置服务发布端口
final DriftNettyServerConfig config = new DriftNettyServerConfig();
config.setPort(9999);
// 3. 配置server
DriftServer driftServer = new DriftServer(
        // 配置netty传输工厂
        new DriftNettyServerTransportFactory(config),
        // 配置编码Manager
        new ThriftCodecManager(),
        // 配置空的方法调用状态信息工厂
        new NullMethodInvocationStatsFactory(),
        // 配置服务实例集合
        ImmutableSet.of(new DriftService(obj)),
        // 配置调用过滤器(配置为空)
        ImmutableSet.of());
// 4. server启动
driftServer.start();

Runtime.getRuntime().addShutdownHook(new Thread(driftServer::shutdown));
```

### 客户端调用

```java
// 1. 服务地址列表(实际使用可根据注册中心信息获取及更新)
List<HostAndPort> addresses = ImmutableList.of(HostAndPort.fromParts("localhost", 9999));

// 2. 配置编码Manager, 地址选择器等配置
ThriftCodecManager codecManager = new ThriftCodecManager();
AddressSelector addressSelector = new SimpleAddressSelector(addresses, false);
DriftNettyClientConfig config = new DriftNettyClientConfig();

// 3. 根据配置创建方法调用工厂
DriftNettyMethodInvokerFactory<?> methodInvokerFactory = DriftNettyMethodInvokerFactory
        .createStaticDriftNettyMethodInvokerFactory(config);

// 4. 根据方法工厂等信息，创建客户端工厂类
DriftClientFactory clientFactory = new DriftClientFactory(codecManager, methodInvokerFactory, addressSelector);

// 5. 根据客户端工厂类来创建客户端
final DriftClient<DemoService> driftClient = clientFactory.createDriftClient(DemoService.class);

// 6. 获取客户端实例并发起调用，打印结果
final String aa = driftClient.get().echo("hello world");
System.out.println(aa);
```

