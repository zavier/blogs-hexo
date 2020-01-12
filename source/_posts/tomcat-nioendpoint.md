---
title: Tomcat NioEndpoint解析
date: 2020-01-12 15:35:43
tags: [java, tomcat]
---

NioEndpoint 是 Tomcat 中负责使用 NIO 方式进行网络通信功能的模块，它负责监听处理请求连接，并将解析出的字节流传递给 Processor 进行后续的处理

下面梳理一下主要的处理流程，如下图

![NioEndpoint](/images/NioEndpoint.png)



<!-- more -->

1. 创建Acceptor(默认1个)，并启动在对应端口进行监听
2. 创建Poller(多核下默认为2个)并启动，每个 Poller 在创建时会开启一个 Selector
3. Acceptor 监听到连接后，将其转发注册到随机的一个 Poller 中
4. Poller 在获取到连接后，将其包装为 PollerEvent，并添加到其 events 列表中
5. Poller 在执行时，会循环获取 events，执行其 run方法
6. PollerEvent 执行时，会将其中的 SocketChannel 注册到selector中，监听对应事件
7. 当有事件触发时，Poller 会将对应的连接转发给 Endpoint
8. Endpoint 会创建对应的 SocketProcessor, 并将其提交到线程池中执行
9. SocketProcessor 会获取 Endpoint 中的 hanler进行处理



简化一下，可以得到如下结果

![acceptor-poller](/images/acceptor-poller.jpg)



如果还有兴趣，可以看下接下来的代码， 为了简单，省略了部分代码，处理流程可根据序号进行跟进

Endpoint 的基础类为 AbstractEndpoint，部分简略后的代码如下

```java
public abstract class AbstractEndpoint<S> {
    public final void start() throws Exception {
        bind();
        startInternal();
    }
  
    /**
     * 创建Acceptor, 进行端口监听
     */
    protected abstract Acceptor createAcceptor();
  
  
    public abstract void bind() throws Exception;
    public abstract void unbind() throws Exception;
    public abstract void startInternal() throws Exception;
    public abstract void stopInternal() throws Exception;
  
    // 抽象方法，创建 SocketProcessor
    protected abstract SocketProcessorBase<S> createSocketProcessor(
            SocketWrapperBase<S> socketWrapper, SocketEvent event);
  
    // 16. 
    public boolean processSocket(SocketWrapperBase<S> socketWrapper,
            SocketEvent event, boolean dispatch) {
        try {
            if (socketWrapper == null) {
                return false;
            }
            // 16. 创建 SockerProcessor
            SocketProcessorBase<S> sc = processorCache.pop();
            if (sc == null) {
                sc = createSocketProcessor(socketWrapper, event);
            } else {
                sc.reset(socketWrapper, event);
            }
            // 17. 放入线程池中进行执行
            Executor executor = getExecutor();
            if (dispatch && executor != null) {
                executor.execute(sc);
            } else {
                sc.run();
            }
        } catch (RejectedExecutionException ree) {
            getLog().warn(sm.getString("endpoint.executor.fail", socketWrapper) , ree);
            return false;
        } catch (Throwable t) {
            ExceptionUtils.handleThrowable(t);
            // This means we got an OOM or similar creating a thread, or that
            // the pool and its queue are full
            getLog().error(sm.getString("endpoint.process.fail"), t);
            return false;
        }
        return true;
    }
}
```

NioEndpoint 有如下几个主要方法

```java
public class NioEndpoint {
  
    // 初始化ServerSocketChannel 并绑定端口
    public void bind() throws Exception {...}

    // 创建 Executor
    // 创建 Poller 集合(默认单核1个，多核为2个)并依次启动
    // 创建 Acceptor(默认1个)并启动
    public void startInternal() throws Exception {
        if (!running) {
            // 1. 创建 Executor 
            if ( getExecutor() == null ) {
                createExecutor();
            }

            // 2. 创建启动 poller 线程
            pollers = new Poller[getPollerThreadCount()];
            for (int i=0; i<pollers.length; i++) {
                pollers[i] = new Poller();
                Thread pollerThread = new Thread(pollers[i], getName() + "-ClientPoller-"+i);
                pollerThread.setPriority(threadPriority);
                pollerThread.setDaemon(true);
                pollerThread.start();
            }
            
            // 3. 启动 acceptor 线程
            startAcceptorThreads();
        }
    }
  
    @Override
    protected AbstractEndpoint.Acceptor createAcceptor() {
        return new Acceptor();
    }
  
    // NioEndpoint 中实现的抽象类中的 Acceptor如下（省略调整了部分代码）
    protected class Acceptor extends AbstractEndpoint.Acceptor {
        @Override
        public void run() {
            while (running) {
                // 如果达到最大连接数则阻塞等待
                countUpOrAwaitConnection();
                // 4. 等待客户端的连接
                SocketChannel socket = serverSock.accept();
                if (!setSocketOptions(socket)) {
                    closeSocket(socket);
                }
            }
        }
    }
  
    // 5.
    protected boolean setSocketOptions(SocketChannel socket) {
        try {
            socket.configureBlocking(false);
            Socket sock = socket.socket();
            // 5. 生成 NioChannel 
            NioChannel channel = new NioChannel(socket, bufhandler);
            // 6. 随机获取一个 poller, 将 NioChannel 注册进去
            getPoller0().register(channel);
        } catch (Throwable t) {
            // Tell to close the socket
            return false;
        }
        return true;
    }
  
    // 17. NioEndpoint 的 SocketProcessor
    protected class SocketProcessor extends SocketProcessorBase<NioChannel> {

        public SocketProcessor(SocketWrapperBase<NioChannel> socketWrapper, SocketEvent event) {
            super(socketWrapper, event);
        }

        @Override
        protected void doRun() {
            NioChannel socket = socketWrapper.getSocket();
            SelectionKey key = socket.getIOChannel().keyFor(socket.getPoller().getSelector());

            try {
                if (handshake == 0) {
                    SocketState state = SocketState.OPEN;
                    // 18. 处理请求
                    if (event == null) {
                        state = getHandler().process(socketWrapper, SocketEvent.OPEN_READ);
                    } else {
                        state = getHandler().process(socketWrapper, event);
                    }
                    if (state == SocketState.CLOSED) {
                        close(socket, key);
                    }
                } else if (handshake == -1 ) {
                    getHandler().process(socketWrapper, SocketEvent.CONNECT_FAIL);
                    close(socket, key);
                } else if (handshake == SelectionKey.OP_READ){
                    socketWrapper.registerReadInterest();
                } else if (handshake == SelectionKey.OP_WRITE){
                    socketWrapper.registerWriteInterest();
                }
            } catch (CancelledKeyException cx) {
                socket.getPoller().cancelledKey(key);
            } catch (VirtualMachineError vme) {
                ExceptionUtils.handleThrowable(vme);
            } catch (Throwable t) {
                log.error("", t);
                socket.getPoller().cancelledKey(key);
            } finally {
                socketWrapper = null;
                event = null;
                //return to cache
                if (running && !paused) {
                    processorCache.push(this);
                }
            }
        }
    }
}
```

下面我们看一下 Poller 类

```java
public class Poller implements Runnable {
    private Selector selector;
    private final SynchronizedQueue<PollerEvent> events = new SynchronizedQueue<>();
    
    public Poller() throws IOException {
        this.selector = Selector.open();
    }
    
    // 7. 
    public void register(final NioChannel socket) {
        socket.setPoller(this);
        NioSocketWrapper ka = new NioSocketWrapper(socket, NioEndpoint.this);
        socket.setSocketWrapper(ka);
        ka.setPoller(this);
        ka.setReadTimeout(getSocketProperties().getSoTimeout());
        ka.setWriteTimeout(getSocketProperties().getSoTimeout());
        ka.setKeepAliveLeft(NioEndpoint.this.getMaxKeepAliveRequests());
        ka.setSecure(isSSLEnabled());
        ka.setReadTimeout(getConnectionTimeout());
        ka.setWriteTimeout(getConnectionTimeout());
        PollerEvent r = eventCache.pop();
        ka.interestOps(SelectionKey.OP_READ);//this is what OP_REGISTER turns into.
        // 7. 创建 PollerEvent 对象， 添加到 events 中，注意这里的 interestOps 为 OP_REGISTER
        if ( r==null) r = new PollerEvent(socket,ka,OP_REGISTER);
        else r.reset(socket,ka,OP_REGISTER);
        addEvent(r);
    }
  
    @Override
    public void run() {
        // Loop until destroy() is called
        while (true) {
            boolean hasEvents = false;
            try {
                if (!close) {
                    // 8. 依次注册监听事件，select
                    hasEvents = events();
                    if (wakeupCounter.getAndSet(-1) > 0) {
                        keyCount = selector.selectNow();
                    } else {
                        // 11. selector.select
                        keyCount = selector.select(selectorTimeout);
                    }
                    wakeupCounter.set(0);
                }
            } catch (Throwable x) {
                continue;
            }
            // 如果时间超时后，没有任何事件，则再次执行 events
            if ( keyCount == 0 ) hasEvents = (hasEvents | events());

            // 12. 有关注的事件到来
            Iterator<SelectionKey> iterator =
                keyCount > 0 ? selector.selectedKeys().iterator() : null;
            while (iterator != null && iterator.hasNext()) {
                SelectionKey sk = iterator.next();
                NioSocketWrapper attachment = (NioSocketWrapper)sk.attachment();
                if (attachment == null) {
                    iterator.remove();
                } else {
                    iterator.remove();
                    // 13. 处理对应的事件key
                    processKey(sk, attachment);
                }
            }//while

            //process timeouts
            timeout(keyCount,hasEvents);
        }//while

        getStopLatch().countDown();
    }
  
    // 9. 依次调用之前插入的每个 event 的 run方法
    public boolean events() {
        boolean result = false;
        PollerEvent pe = null;
        for (int i = 0,size = events.size(); i<size && (pe = events.poll())!=null; i++) {
            result = true;
            try {
                pe.run();
                pe.reset();
                if (running && !paused) {
                    eventCache.push(pe);
                }
            } catch ( Throwable x ) {
                log.error("",x);
            }
        }
        return result;
    }
  
    // 14.
    protected void processKey(SelectionKey sk, NioSocketWrapper attachment) {
        try {
            if ( close ) {
                cancelledKey(sk);
            } else if ( sk.isValid() && attachment != null ) {
                if (sk.isReadable() || sk.isWritable() ) {
                    if ( attachment.getSendfileData() != null ) {
                        processSendfile(sk,attachment, false);
                    } else {
                        unreg(sk, attachment, sk.readyOps());
                        boolean closeSocket = false;
                        // 14. 如果数据已经准备好，可以进行读取了
                        if (sk.isReadable()) {
                            // 15. 处理socket, 调用 AbstractEndpoint 中的 processSocket 方法
                            if (!processSocket(attachment, SocketEvent.OPEN_READ, true)) {
                                closeSocket = true;
                            }
                        }
                        if (!closeSocket && sk.isWritable()) {
                            if (!processSocket(attachment, SocketEvent.OPEN_WRITE, true)) {
                                closeSocket = true;
                            }
                        }
                        if (closeSocket) {
                            cancelledKey(sk);
                        }
                    }
                }
            } else {
                //invalid key
                cancelledKey(sk);
            }
        } catch ( CancelledKeyException ckx ) {
            cancelledKey(sk);
        } catch (Throwable t) {
            ExceptionUtils.handleThrowable(t);
            log.error("",t);
        }
    }
}
```

接着来看下 PollerEvent 的实现

```java
public static class PollerEvent implements Runnable {
    private NioChannel socket;
    private int interestOps;
    private NioSocketWrapper socketWrapper;
  
    @Override
    public void run() {
        if (interestOps == OP_REGISTER) {
            try {
                // 10. 注册一个 OP_READ 事件
                socket.getIOChannel().register(
                        socket.getPoller().getSelector(), SelectionKey.OP_READ, socketWrapper);
            } catch (Exception x) {
                log.error(sm.getString("endpoint.nio.registerFail"), x);
            }
        } else {
            final SelectionKey key = socket.getIOChannel().keyFor(socket.getPoller().getSelector());
            try {
                if (key == null) {
                    socket.socketWrapper.getEndpoint().countDownConnection();
                    ((NioSocketWrapper) socket.socketWrapper).closed = true;
                } else {
                    final NioSocketWrapper socketWrapper = (NioSocketWrapper) key.attachment();
                    if (socketWrapper != null) {
                        int ops = key.interestOps() | interestOps;
                        socketWrapper.interestOps(ops);
                        key.interestOps(ops);
                    } else {
                        socket.getPoller().cancelledKey(key);
                    }
                }
            } catch (CancelledKeyException ckx) {
                try {
                    socket.getPoller().cancelledKey(key);
                } catch (Exception ignore) {}
            }
        }
    }
}
```

