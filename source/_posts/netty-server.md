---
title: Netty服务端使用及简介
date: 2020-02-29 13:44:46
tags: [java, netty]
---

最近因为工作原因，学习了一下Netty，这里写个笔记记录一下

Netty是什么呢？它是一款**异步**的**事件驱动**的网络应用程序框架，使用它可以快速的开发出可维护的高性能的面向协议的服务器和客户端---《Netty实战》

这是有两个关键词是异步和事件驱动，先来简单介绍一下

异步是指什么呢？就是发送消息和接收消息是异步的，如调用发送方法后，进行的异步发送，你不知道到底发送出去了没有，如果想要知道结果怎么办呢？这时候可以设置回调函数，发送结果会通过回调函数传回来，当然，其实也可以阻塞同步等待结果，不过那可能就会影响其他数据的处理了

事件驱动呢，我理解就是接收数据等的时候，如在数据可以到达可读取的时候，IO线程会通知调用我们相应的方法进行数据处理流程

<!-- more -->

好了，下面我们看一段来自Netty官网的服务端代码

```java
public class DiscardServer {
    private int port;
    public DiscardServer(int port) {
        this.port = port;
    }
    
    public void run() throws Exception {
        // EventLoopGroup可以理解为线程池，bossGroup中的线程主要负责监听连接请求，转发给workerGroup
        EventLoopGroup bossGroup = new NioEventLoopGroup();
        // workerGroup主要负责在建立连接后的所有处理
        EventLoopGroup workerGroup = new NioEventLoopGroup();
        try {
            ServerBootstrap b = new ServerBootstrap();
            b.group(bossGroup, workerGroup)
             .channel(NioServerSocketChannel.class)
              // 指定worker线程（与客户端连接）的处理链，数据在其中流转处理
             .childHandler(new ChannelInitializer<SocketChannel>() {
                 @Override
                 public void initChannel(SocketChannel ch) throws Exception {
                     ch.pipeline().addLast(new DiscardServerHandler());
                 }
             })
             .option(ChannelOption.SO_BACKLOG, 128)         
             .childOption(ChannelOption.SO_KEEPALIVE, true); 
    
            // 绑定端口，启动服务等待连接请求
            ChannelFuture f = b.bind(port).sync();
    
            f.channel().closeFuture().sync();
        } finally {
            workerGroup.shutdownGracefully();
            bossGroup.shutdownGracefully();
        }
    }
    
}
```



我们可以结合下面的图来理解一下

![Netty-server](/images/netty-server.png)

先来介绍几个概念

1. NioEventLoopGroup:  可以理解为一个线程池
2. NioEventLoop: 可以理解为单个线程，一个NioEventLoopGroup可以有多个NioEventLoop
3. Selector:  可以理解为Java NIO中的选择器，负责监听通道事件，一个NioEventLoop有一个Selector
4. Channel: 可以理解为Java NIO中的Channel通道，代表一个到客户端的连接，使用时需要注册到NioEventLoop中，NioEventLoop中可以有多个Channel，其中的Selector负责监听所有的channel事件
5. HandlePipeline/ Handler :  每个channel有一个对应的处理链，链中的handler也分为**入站handler**(处理接收到的数据)和**出站handler**(处理将要发送的数据)，当selector监听到对应事件发生时，线程会依次调用链中hanler的对应方法处理数据



有了前面的准备，这时候我们来分析一下初始化启动的流程

1. 首先会创建一个NioServerSocketChannel(boss)，初始化其数据的处理器链handlerPipeline（其中有一个ServerBootstrapAcceptor）
2. 将NioServerSocketChannel注册到EventLoopGroup的NioEventLoop中，每个NioEventLoop有一个Selector, 负责监听其下面的所有channel的事件
3. 当有客户端发起连接时，selector会通知NioServerSocketChannel， 而NioServerSocketChannel会将数据转发到对应的处理链中
4. 当处理链中的ServerBootstrapAcceptor接收到连接事件后，会获取对应的与客户端连接的channel，为其绑定初始阶段配置的handlerPipeline，并在NioServerSocketChannel(worker)中选择一个NioEventLoop进行注册，其中的Selector会负责监听事件，之后与此客户端的所有交互都由这个NioEventLoop中的线程负责执行
5. NioServerSocketChannel的 bossGroup与 workerGroup可以共用一个的



好了，主要的服务端创建处理流程就是这些，如有错误欢迎指正