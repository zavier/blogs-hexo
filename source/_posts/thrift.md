---
title: Thrift(一)-快速入门
date: 2021-12-12 21:26:08
tags: [java, thrift]
---

[Thrift](https://thrift.apache.org/)是facebook开发的一款轻量级的跨语言的RPC实现，它为数据传输、数据序列化和应用层的处理提供了清晰的抽象和实现。它的代码生成器使用简单的定义语言来生成跨语言的代码，来构建可互操作的RPC客户端和服务端。这篇文章主要简单介绍一下thrift的使用

<!-- more -->

## 使用

thrift的使用可以分为如下几个步骤

1. 使用thrift的接口描述语言（IDL）定义好数据类型和服务接口
2. 安装thrift代码生成工具，来生成对应语言的客户端和服务端代码
3. 服务端需要对具体的服务接口实现逻辑进行编码实现
4. 编写初始化代码进行服务端/客户端的启动或调用

下面我们来分别具体看一下

### 使用IDL定义数据类型和服务接口

因为要实现跨语言的通信，那么就不能使用任何一种语言来定义数据类型和接口，所以thrift提供了[IDL](https://thrift.apache.org/docs/idl)来定义相关的信息，其中支持的信息包括 基本类型、结构体、容器、异常、服务接口 等

#### 基本类型

- bool
- byte
- i16 (有符号的16位整型)
- i32 (有符号的32位整型)
- i64 (有符号的64位整型)
- double (64位浮点数)
- string (字符串)

因为有的语言没有无符号的数值类型，所以thrift提供的都是有符号的整形

#### 特殊类型

- binary （bytes数组) 

#### 结构体

结构体是用来定义跨语言的通用对象，类似C语言中的结构体或者面向对象语言中的类

```
// 结构体
struct Example {
  1:i32 number = 10,  // 其中的属性信息，属性可以设置默认值
  2:i64 bigNumber,
  3:double decimals,
  4:string name = "thrifty"
}
```

#### 容器

容器即是我们平时常用的集合类，类似java中的list, map等，支持的类型如下

- list<type\>
- set<type\>
- map<type1, type2>

#### 异常

语法基本同结构体，除了使用 exception 替换 struct 关键字

#### 服务接口

定义一个服务接口与面向对象中定义一个接口类似

```
service StringCache {
  void set(1:i32 key, 2:string value),
  string get(1:i32 key) throws (1:KeyNotFound knf),
  void delete(1:i32 key)
}
```

使用thrift提供的跨语言的通用类型系统，就不需要开发人员编写序列化相关代码，thrift会根据定义信息来生成对应语言的相关代码，同时会为每种类型生成read和write方法，使用 TProtocol 对象来实现序列化和传输



下面我们来定义一个服务接口和相关的数据类型（使用Java语言）

```
// 定义用户信息
struct User {
    1:string name;
    2:i32 age;
}

// 定义查询结果
struct UserSearchResult {
    1:list<User> users;
}

// 定义查询服务接口
service UserService {
    UserSearchResult searchUsers(1:string name);
}
```



### 使用thrift代码生成工具生成对应语言(Java)代码

windows系统可以根据[此页面](https://thrift.apache.org/download)的windows下载链接进行代码生成工具的下载使用

mac系统可以使用homebrew进行安装`brew install thrift`

安装完成后，在文件对应路径执行如下命令

`thrift --gen java userService.thrift `

会在路径下生成`gen-java`文件夹，其中会包含生成的如下三个文件

`User.java`, `UserSearchResult.java` , `UserService.java`



创建对应的java项目，引入thrift的包

```xml
<dependency>
  <groupId>org.apache.thrift</groupId>
  <artifactId>libthrift</artifactId>
  <version>0.15.0</version>
</dependency>
```

之后将之前生成的代码复制到项目中即可



### 服务接口实现

服务接口实现通过实现生成的接口的Iface即可

```java
// UserService.Iface 为自动生成的类
public class UserServiceImpl implements UserService.Iface {

    @Override
    public UserSearchResult searchUsers(String name) throws TException {
        // 这里为随便模拟的数据，实际可替换为对应的功能
        List<User> userList = new ArrayList<>();
        {
            final User user = new User();
            user.setName(name);
            userList.add(user);
        }
        {
            final User user = new User();
            user.setName(name + "1");
            userList.add(user);
        }

        final UserSearchResult result = new UserSearchResult();
        result.setUsers(userList);
        return result;
    }
}
```



### 实现客户端服务端初始化代码

最后我们来实现服务端和客户端的初始化代码，进行启动并发起实际调用

#### 服务端初始化

```java
// 设置监听连接的端口
TServerTransport serverTransport = new TServerSocket(12345);

// 创建服务接口实现的实例，创建对应processor类
UserService.Processor<UserServiceImpl> processor = new UserService.Processor<>(new UserServiceImpl());
// 设置启动服务端需要的参数：transport 与 processor
TServer.Args serverArgs = new TServer.Args(serverTransport).processor(processor);

// 创建服务并启动
TServer server = new TSimpleServer(serverArgs);
System.out.println("Starting the simple server...");
server.serve();
```

#### 客户端代码

```java
// 设置连接服务端的地址信息
TTransport transport = new TSocket("localhost", 12345);
transport.open();

// 构造客户端
TProtocol protocol = new TBinaryProtocol(transport);
UserService.Client client = new UserService.Client(protocol);

// 进行请求获取响应
UserSearchResult userRes = client.searchUsers("zhangsan");
System.out.println(JSON.toJSONString(userRes));

// 关闭连接
transport.close();
```

待服务端启动后，再启动客户端即可获取对应的数据

例子代码：https://github.com/zavier/thrift-demo



以上就是thrift的基本使用方式，构造服务端和客户端的代码及实现原理我们后面继续进行分析。
