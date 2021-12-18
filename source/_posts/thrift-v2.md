---
title: Thrift处理流程分析
date: 2021-12-18 14:14:46
tags: [java, thrift]
---

之前介绍过[thrift使用](https://zhengw-tech.com/2021/12/12/thrift/), 但是只知道使用总是不够满足，这次我们接着之前的代码，来看下这个具体的实现和处理流程，在介绍之前先看下几个重要的接口

传输层 TTransport : 负责数据传输（大部分场景为负责网络传输）

协议层 TProtocol:  负责进行数据结构的序列化与反序列化（依赖TTransport 进行数据传输及读取）

处理层 TProcessor : 使用协议和传输接口进行具体处理处理

<!-- more -->

### server初始化

再次看下Server的初始化启动代码

```java
// 创建传输层ServerTransport
TServerTransport serverTransport = new TServerSocket(12345);

// 实例化接口实现类
// 构造Server参数（TProcessor, TTransport, TProtocol-默认TBinaryProtocol）
UserService.Processor<UserServiceImpl> processor = new UserService.Processor<>(new UserServiceImpl());
final TServer.Args serverArgs = new TServer.Args(serverTransport).processor(processor);

// 使用参数初始化Server并启动
TServer server = new TSimpleServer(serverArgs);
System.out.println("Starting the simple server...");
server.serve();
```

下面据此来进入源码，了解一下具体实现（本次使用的代码为 libthrift : 0.15.0）

#### 网络传输初始化

先来看下传输层TServerTransport，对应的实现TServerSocket就是对平时我们使用的ServerSocket的包装，负责进行相关的网络传输

```java
// org.apache.thrift.transport.TServerSocket
public class TServerSocket extends TServerTransport {
    private ServerSocket serverSocket_ = null;
}
```

#### 相关参数构造

接着分析一下代码`UserService.Processor<UserServiceImpl> processor = new UserService.Processor<>(new UserServiceImpl());`，这是 UserService.Processor的构造过程

```java
// UserService.Processor 继承了 org.apache.thrift.TBaseProcessor
// 所以先看下 org.apache.thrift.TBaseProcessor
public abstract class TBaseProcessor<I> implements TProcessor {
    // 维护了iface为我们的逻辑实现类 UserServiceImpl
    // 同时维护一个map<方法名, 处理函数>
    private final I iface;
    private final Map<String, ProcessFunction<I, ? extends TBase>> processMap;

    // 处理时根据读取到的方法名获取到对应的函数类进行处理
    @Override
    public void process(TProtocol in, TProtocol out) throws TException {
        // 读取方法，调用对应的函数进行处理
        TMessage msg = in.readMessageBegin();
        ProcessFunction fn = processMap.get(msg.name);
        fn.process(msg.seqid, in, out, iface);
    }
}

// thrift自动生成的 UserService.Processor
public static class Processor<I extends Iface> extends TBaseProcessor<I> implements TProcessor {
    // 设置iface为我们实现的 UserServiceImpl类
    // 同时设置了处理的map<方法名，处理逻辑类>
    public Processor(I iface) {
        super(iface, getProcessMap(new HashMap<String, ProcessFunction<I, ? extends TBase>>()));
    }

    // 设置各个方法名对应的处理map信息（这里只有searchUsers一个方法）
    private static <I extends Iface> Map<String,  ProcessFunction<I, ? extends TBase>> getProcessMap(Map<String, ProcessFunction<I, ? extends TBase>> processMap) {
        processMap.put("searchUsers", new searchUsers());
        return processMap;
    }
}
```

再来看下 TServer.Args，它其实类似于我们平时使用的builder模式，用来构造 TServer使用

```java
public static class Args extends AbstractServerArgs<Args> {
    public Args(TServerTransport transport) {
        super(transport);
    }
}

// 这里构造了server需要的全部基础类
public static abstract class AbstractServerArgs<T extends AbstractServerArgs<T>> {
    // 传输层，会使用之前构造的 TServerSocket
    final TServerTransport serverTransport;
    // 处理工厂，会返回之前构造传入进来的 UserService.Processor
    TProcessorFactory processorFactory;
    // 传输层的输入输出工厂，默认空实现，会将入参的TTransport直接返回
    TTransportFactory inputTransportFactory = new TTransportFactory();
    TTransportFactory outputTransportFactory = new TTransportFactory();
    // 协议的输入输出，默认使用二进制的 TBinaryProtocol
    TProtocolFactory inputProtocolFactory = new TBinaryProtocol.Factory();
    TProtocolFactory outputProtocolFactory = new TBinaryProtocol.Factory();
}
```

#### 创建server实例启动

最后启动server，这次我们只看最简单的 TSimpleServer 实现

```java
// TSimplerServer.serve 核心代码
public void serve() {
    while (!stopped_) {
        TTransport client = null;
        TProcessor processor = null;
        TTransport inputTransport = null;
        TTransport outputTransport = null;
        TProtocol inputProtocol = null;
        TProtocol outputProtocol = null;
        ServerContext connectionContext = null;
        try {
            // 等待客户端连接（初始启动阻塞的位置）
            client = serverTransport_.accept();
            // 有客户端连接接入
            if (client != null) {
                // 从对应工厂获取实例
                processor = processorFactory_.getProcessor(client);
                inputTransport = inputTransportFactory_.getTransport(client);
                outputTransport = outputTransportFactory_.getTransport(client);
                inputProtocol = inputProtocolFactory_.getProtocol(inputTransport);
                outputProtocol = outputProtocolFactory_.getProtocol(outputTransport);
                while (true) {
                    // 调用process进行逻辑处理
                    processor.process(inputProtocol, outputProtocol);
                }
            }
        } catch (TTransportException ttx) {
            // 代码省略
        }
    }
}
```



### client初始化及调用

相关代码如下

```java
// 初始化网络连接
TTransport transport = new TSocket("localhost", 12345);
transport.open();

// 构造协议及客户端
TProtocol protocol = new TBinaryProtocol(transport);
UserService.Client client = new UserService.Client(protocol);

// 发起调用获取结果
UserSearchResult userRes = client.searchUsers("zhangsan");
System.out.println(userRes);

// 关闭连接
transport.close();
```

下面我们来依次分析一下

#### 初始化网络连接

```java
TTransport transport = new TSocket("localhost", 12345);
transport.open();
```

TSocket是对java Socket的包装

```java
// TSocket.open
public void open() throws TTransportException {
    if (socket_ == null) {
        initSocket();
    }

    try {
        // 建立连接及后期构造输入输出流
        socket_.connect(new InetSocketAddress(host_, port_), connectTimeout_);
        inputStream_ = new BufferedInputStream(socket_.getInputStream());
        outputStream_ = new BufferedOutputStream(socket_.getOutputStream());
    } catch (IOException iox) {
        close();
        throw new TTransportException(TTransportException.NOT_OPEN, iox);
    }
}
```

#### 构造客户端及调用

```java
TProtocol protocol = new TBinaryProtocol(transport);
UserService.Client client = new UserService.Client(protocol);

UserSearchResult userRes = client.searchUsers("zhangsan");
```

UserService.Client也是thrift自动生成的代码，看下`searchUsers`方法调用的实现

```java
// UserService.Client
public static class Client extends org.apache.thrift.TServiceClient implements Iface {
    public UserSearchResult searchUsers(String name) throws TException {
        send_searchUsers(name);
        return recv_searchUsers();
    }
  
    // 发送消息
    public void send_searchUsers(String name) throws TException {
        searchUsers_args args = new searchUsers_args();
        args.setName(name);
        sendBase("searchUsers", args);
    }
  
    // 接受处理结果
    public UserSearchResult recv_searchUsers() throws TException {
        searchUsers_result result = new searchUsers_result();
        receiveBase(result, "searchUsers");
        if (result.isSetSuccess()) {
            return result.success;
        }
        throw new TApplicationException(MISSING_RESULT, "searchUsers failed: unknown result");
    }
}
```

thrift会为我们定义的结构和属性生成相关的类，包含我们定义的参数信息也会有对应的类，每个生成的类型会两个方法，read 和 write 来使用 TProtocol 来实现序列化和传输数据

这里以searchUsers_args（参数对应类）看一下相关的生成代码，代码量比较多，我们只看下核心部分实现

```java
// 1. 定义了相关字段及结构信息
// 2. 通过TProtocol读取写入数据
public static class searchUsers_args implements TBase<UserService.searchUsers_args, UserService.searchUsers_args._Fields>, Serializable, Cloneable, Comparable<UserService.searchUsers_args>   {
    // 定义类对应的结构
    private static final TStruct STRUCT_DESC = new TStruct("searchUsers_args");
    // 结构中的字段信息（id、名称、类型信息）
    private static final TField NAME_FIELD_DESC = new TField("name", TType.STRING, (short)1);

    // 用了通过TProtocol读写(接受、发送) searchUsers_args 数据 
    private static final SchemeFactory STANDARD_SCHEME_FACTORY = new searchUsers_argsStandardSchemeFactory();

    // 参数对应的字段
    public String name; // required

    // 参数结构中对应的每个字段field枚举结构信息
    public enum _Fields implements org.apache.thrift.TFieldIdEnum {
        NAME((short)1, "name");

        // 名称和属性Fields的映射
        private static final Map<String, UserService.searchUsers_args._Fields> byName = new HashMap<>();

        // 一些Fields查询逻辑
    }

    public void read(org.apache.thrift.protocol.TProtocol iprot) throws org.apache.thrift.TException {
        scheme(iprot).read(iprot, this);
    }

    public void write(org.apache.thrift.protocol.TProtocol oprot) throws org.apache.thrift.TException {
        scheme(oprot).write(oprot, this);
    }
    

    private static class searchUsers_argsStandardSchemeFactory implements SchemeFactory {
        public UserService.searchUsers_args.searchUsers_argsStandardScheme getScheme() {
            return new UserService.searchUsers_args.searchUsers_argsStandardScheme();
        }
    }

    private static class searchUsers_argsStandardScheme extends StandardScheme<UserService.searchUsers_args> {

        public void read(TProtocol iprot, UserService.searchUsers_args struct) throws TException {
            TField schemeField;
            // 开始读取结构信息
            iprot.readStructBegin();
            while (true)
            {
                // 开始读取Field
                schemeField = iprot.readFieldBegin();
                // 如果是结束标识则跳过
                if (schemeField.type == TType.STOP) {
                    break;
                }
                // 根据读取到的id匹配到及类型，再读取对应的值并设置
                switch (schemeField.id) {
                    case 1: // NAME
                        if (schemeField.type == TType.STRING) {
                            struct.name = iprot.readString();
                            struct.setNameIsSet(true);
                        } else {
                            // 类型不同则跳过
                            TProtocolUtil.skip(iprot, schemeField.type);
                        }
                        break;
                    default:
                        TProtocolUtil.skip(iprot, schemeField.type);
                }
                iprot.readFieldEnd();
            }
            iprot.readStructEnd();
        }

        public void write(TProtocol oprot, UserService.searchUsers_args struct) throws TException {
            // 开始写入结构信息
            oprot.writeStructBegin(STRUCT_DESC);
            if (struct.name != null) {
                // 写入Field信息
                oprot.writeFieldBegin(NAME_FIELD_DESC);
                oprot.writeString(struct.name);
                oprot.writeFieldEnd();
            }
            // 写入结束信息
            oprot.writeFieldStop();
            oprot.writeStructEnd();
        }

    }

    // 这里使用了 searchUsers_argsStandardSchemeFactory
    private static <S extends IScheme> S scheme(TProtocol proto) {
        return (StandardScheme.class.equals(proto.getScheme()) ? STANDARD_SCHEME_FACTORY : TUPLE_SCHEME_FACTORY).getScheme();
    }
}
```

构造参数完成后，调用sendBase进行数据发送，sendBase为父类TServiceClient中的方法

消息接收则使用对应的receiveBase方法

```java
public abstract class TServiceClient {
    // 发送
    protected void sendBase(String methodName, TBase<?,?> args) throws TException {
        sendBase(methodName, args, TMessageType.CALL);
    }
  
    private void sendBase(String methodName, TBase<?,?> args, byte type) throws TException {
        // 开始放送消息（方法名、类型、序号-递增）
        oprot_.writeMessageBegin(new TMessage(methodName, type, ++seqid_));
        // 调用args类的write方法写入数据
        args.write(oprot_);
        // 结束写入并刷新
        oprot_.writeMessageEnd();
        oprot_.getTransport().flush();
    }
  
    // 接收结果
    protected void receiveBase(TBase<?,?> result, String methodName) throws TException {
        TMessage msg = iprot_.readMessageBegin();
        // 读取到异常信息处理
        if (msg.type == TMessageType.EXCEPTION) {
            TApplicationException x = new TApplicationException();
            x.read(iprot_);
            iprot_.readMessageEnd();
            throw x;
        }
        // 读取到的消息序号和自己发送的序号不同时抛出异常，说明不是自己发送的消息的响应
        if (msg.seqid != seqid_) {
            throw new TApplicationException(TApplicationException.BAD_SEQUENCE_ID,
                    String.format("%s failed: out of sequence response: expected %d but got %d", methodName, seqid_, msg.seqid));
        }
        // 调用对应searchUsers_result的read方法，逻辑类似searchUsers_args
        result.read(iprot_);
        iprot_.readMessageEnd();
    }
}
```



### server接收请求处理及响应

之前server部分看到处理化等待连接，这里直接从接收到请求处理逻辑开始

```java
// TBaseProcessor.process
public void process(TProtocol in, TProtocol out) throws TException {
    TMessage msg = in.readMessageBegin();
    // 获取方法名称，找到对应的处理函数
    ProcessFunction fn = processMap.get(msg.name);
    if (fn == null) {
        TProtocolUtil.skip(in, TType.STRUCT);
        in.readMessageEnd();
        TApplicationException x = new TApplicationException(TApplicationException.UNKNOWN_METHOD, "Invalid method name: '"+msg.name+"'");
        out.writeMessageBegin(new TMessage(msg.name, TMessageType.EXCEPTION, msg.seqid));
        x.write(out);
        out.writeMessageEnd();
        out.getTransport().flush();
    } else {
        // 使用找到的处理函数进行逻辑处理
        fn.process(msg.seqid, in, out, iface);
    }
}
```

这里我们关注下ProcessFunction

```java
public abstract class ProcessFunction<I, T extends TBase> {
    // 方法名称
    private final String methodName;

    public final void process(int seqid, TProtocol iprot, TProtocol oprot, I iface) throws TException {
        // 有各个子类提供对应的类实例
        T args = getEmptyArgsInstance();
        try {
            // 通过TProtocol读取数据
            args.read(iprot);
        } catch (TProtocolException e) {
            // 忽略异常处理
        }
        iprot.readMessageEnd();
        TSerializable result = null;
        byte msgType = TMessageType.REPLY;

        try {
            // 获取结果
            result = getResult(iface, args);
        } catch (TTransportException ex) {
            // 忽略异常处理
        }

        if(!isOneway()) {
            // 写入响应结果
            oprot.writeMessageBegin(new TMessage(getMethodName(), msgType, seqid));
            result.write(oprot);
            oprot.writeMessageEnd();
            oprot.getTransport().flush();
        }
    }

    protected boolean rethrowUnhandledExceptions(){
        return false;
    }

    protected abstract boolean isOneway();

    public abstract TBase getResult(I iface, T args) throws TException;

    public abstract T getEmptyArgsInstance();

    public String getMethodName() {
        return methodName;
    }
}
```

对于上面例子，对应的ProcessFunction子类为 searchUsers

```java
public static class searchUsers<I extends UserService.Iface> extends ProcessFunction<I, UserService.searchUsers_args> {
    public searchUsers() {
        super("searchUsers");
    }

    public UserService.searchUsers_args getEmptyArgsInstance() {
        return new UserService.searchUsers_args();
    }

    protected boolean isOneway() {
        return false;
    }

    @Override
    protected boolean rethrowUnhandledExceptions() {
        return false;
    }

    public UserService.searchUsers_result getResult(I iface, UserService.searchUsers_args args) throws TException {
        UserService.searchUsers_result result = new UserService.searchUsers_result();
        // 调用iface(业务逻辑实现)进行方法处理，获取并设置结果
        result.success = iface.searchUsers(args.name);
        return result;
    }
}
```



以上即为简单的一次thrift调用和响应的实现逻辑流程

简单总结一下就是thrift会为每种类型生成对应的一个结构，包括如果参数为多个字段也会合并生成一个结构TBase，其中会使用TProtocol（其中会使用TTransport进行消息发送）进行对应结构数据的写入和读取

每次消息会被包装成一个TMessage，其中会包括方法名、消息类型及递增的一个序号(收到响应时用来进行对应)
