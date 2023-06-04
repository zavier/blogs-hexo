---
title: Thrift(三)-协议使用
date: 2021-12-19 23:04:14
tags: [java, thrift]
---

Thrift的关键其实就是在定义好结构后，通过某种序列化方式进行网络传输交互，一般定义结构可以使用IDL的方式来描述各个字段属性等信息，这种方式可以支持跨语言的使用。对于纯Java的应用，也可以通过在类中添加注解的方式来实现，即把IDL中需要定义的信息，通过注解和注解中的信息来进行描述，同样可以达到定义结构的目的

定义好结构之后，就可以通过对应的TProtocol将数据结构进行发送和接收的序列化和反序列化即可，这次我们主要看下TProtocol中的一个实现--TBinaryProtocol

<!-- more -->

<img src="/images/thrift_struct.jpg" style="zoom:60%" />

之前我们也看过thrift支持的一些结构类型，如struct、string、map、list等，具体可以看下对应枚举

```java
public final class TType {
    public static final byte STOP   = 0;
    public static final byte VOID   = 1;
    public static final byte BOOL   = 2;
    public static final byte BYTE   = 3;
    public static final byte DOUBLE = 4;
    public static final byte I16    = 6;
    public static final byte I32    = 8;
    public static final byte I64    = 10;
    public static final byte STRING = 11;
    public static final byte STRUCT = 12;
    public static final byte MAP    = 13;
    public static final byte SET    = 14;
    public static final byte LIST   = 15;
    public static final byte ENUM   = 16;
}
```

每次发送消息，都有一个消息类型的标识

```java
public final class TMessageType {
  public static final byte CALL  = 1;
  public static final byte REPLY = 2;
  public static final byte EXCEPTION = 3;
  public static final byte ONEWAY = 4;
}
```

而TProtocol提供了对应这些结构的读写接口，我们可以大致看一下写接口，读接口也类似

```java
// 发送消息开始
writeMessageBegin(name, type, seq);
writeMessageEnd();
// 开始写入结构体
writeStructBegin(name);
writeStructEnd();
// 开始写入Field，其他的string、i32等的写入都是在Field的写入范围中进行操作
writeFieldBegin(name, type, id);
writeFieldEnd();
writeFieldStop();
writeMapBegin(ktype, vtype, size);
writeMapEnd();
writeListBegin(etype, size);
writeListEnd();
writeSetBegin(etype, size);
writeSetEnd();
writeBool(bool);
writeByte(byte);
writeI16(i16);
writeI32(i32);
writeI64(i64);
writeDouble(double);
writeString(string);
```

通过阅读生成的代码，我们就可以看到具体的使用了，基本流程大致如下

```java
// 1 开始发送消息，写好消息类型及序号
// 类型为请求或响应时name为方法名称，响应与对应的请求序号要相同
writeMessageBegin(name, type, seq);
// 1.1 开始写入结构体
writeStructBegin(name);
// 1.1.2 开始写入结构体中的字段（名称、类型、id）, field中的类型也可以是struct
writeFieldBegin(name, type, id);
// 写入字段值
writeString(string);
// 写入结束一个字段
writeFieldEnd();
// 1.1.3 开始写入结构体中的另一个字段
writeFieldBegin(name, type, id);
// 写入字段值
writeString(string);
// 写入结束一个字段
writeFieldEnd();
// 1.1.4 结构体中的字段写入完成
writeFieldStop();
// 写入结束标识
writeStructEnd();
writeMessageEnd();
```

根据这些接口，掌握了写入流程后，我们可以不使用生成的代码来完成消息的接收和发送，下面我们只使用TBinaryProtocol来实现一个最简单的server服务（对应的接口参考第一篇文章），

```
// userService.thrift
struct User {
    1:string name;
    2:i32 age;
}

struct UserSearchResult {
    1:list<User> users;
}

service UserService {
    UserSearchResult searchUsers(1:string name);
}
```

实现代码如下（只是为了展示功能）

```java
// TProtocol需要以来 TTransport,这里进行构造
TServerTransport serverTransport = new TServerSocket(12345);
serverTransport.listen();
final TTransport transport = serverTransport.accept();

// 初始化 TProtocol
TProtocol protocol = new TBinaryProtocol(transport);

while (true) {
    String name = "";
    // 开始读取 Message，类型为系统调用
    final TMessage tMessage = protocol.readMessageBegin();
    if (tMessage.type == TMessageType.CALL) {
        // 开始读取结构体
        protocol.readStructBegin();
        // 读取结构体中的属性
        final TField tField = protocol.readFieldBegin();
        // 如果属性的id是1，对应的name属性（属性基本都是根据id来定位）
        if (tField.id == 1) {
            // 读取name的属性值
            name = protocol.readString();
        }
        // 因为对应方法只有一个属性，所以到这里可以认为读取完成了
        protocol.readFieldEnd();
        protocol.readStructEnd();
    }
    protocol.readMessageEnd();

    System.out.println("Read param name:" + name);

    // TODO: 这里就是获取完参数值后，进行业务计算，获取结果

    // 开始写入结果，类型为reply, 使用请求的序号
    final TMessage respMessage = new TMessage("searchUsers", TMessageType.REPLY, tMessage.seqid);
    protocol.writeMessageBegin(respMessage);

    // thrift的响应，需要最外层包装一个id=0的struct，其中的Field对应结果的struct
    protocol.writeStructBegin(new TStruct("success"));
    // 开始写入结果的field
    protocol.writeFieldBegin(new TField("success", TType.STRUCT, (short) 0));

    // 开始写入结果struct
    protocol.writeStructBegin(new TStruct("searchResult"));
    // 写入结果中的field, 类似为list<user>数据
    final TField tField = new TField("users", TType.LIST, (short) 1);
    // 写入user-field
    protocol.writeFieldBegin(tField);
    // 写入具体值（list，结构类型为struct, 元素数量为2个）
    protocol.writeListBegin(new TList(TType.STRUCT,  2));
		// 写入list中的第一个struct
    protocol.writeStructBegin(new TStruct("user"));
    protocol.writeFieldBegin(new TField("name", TType.STRING, (short) 1));
    protocol.writeString("zhangsan1");
    protocol.writeFieldEnd();
    protocol.writeFieldBegin(new TField("age", TType.I32, (short) 2));
    protocol.writeI32(18);
    protocol.writeFieldEnd();
    protocol.writeFieldStop();
    protocol.writeStructEnd();
    // 写入list中的第二个struct
    protocol.writeStructBegin(new TStruct("user"));
    protocol.writeFieldBegin(new TField("name", TType.STRING, (short) 1));
    protocol.writeString("lisi1");
    protocol.writeFieldEnd();
    protocol.writeFieldBegin(new TField("age", TType.I32, (short) 2));
    protocol.writeI32(19);
    protocol.writeFieldEnd();
    protocol.writeFieldStop();
    protocol.writeStructEnd();
		// 结束list写入及其他对应的结束方法
    protocol.writeListEnd();
    protocol.writeFieldEnd();
    protocol.writeFieldStop();
    protocol.writeStructEnd();

    protocol.writeFieldEnd();
    protocol.writeFieldStop();
    protocol.writeStructEnd();
    // 结束消息写入
    protocol.writeMessageEnd();
    // 刷新发送
    protocol.getTransport().flush();
}
```

之后启动服务，在使用之前的Client端方法进行调用

```java
// client端代码，使用thrift生成的UserService.Client调用
TTransport transport = new TSocket("localhost", 12345);
transport.open();

TProtocol protocol = new TBinaryProtocol(transport);
UserService.Client client = new UserService.Client(protocol);

UserSearchResult userRes = client.searchUsers("zhangsan");
System.out.println(userRes);

transport.close();
```

执行后可以发现可以实现之前的功能

```
// 服务端终端输出
Read param name:zhangsan
// 客户端终端输出
UserSearchResult(users:[User(name:zhangsan1, age:18), User(name:lisi1, age:19)])
```



再进行深入的话，我们可以根据 TBinaryProtocol 中的具体发送信息逻辑，直接使用原生的Java Socket进行编程，只不过会更加麻烦一些，原理基本就是如此
