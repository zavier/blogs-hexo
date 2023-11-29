---
title: Redis服务端-客户端通信协议
date: 2019-06-08 21:32:08
tags: redis
---

## 了解Redis通信内容

Redis我们都比较熟悉，可以用来做缓存、分布式锁等，但是，其中的客户端与服务端是如何进行通信的呢？

我们可以分别模拟一个服务端或者客户端，打印查看来自实际连接的请求来获取它们的通信方式

首先，让我们先使用先模拟一个服务端，使用`Jedis`进行连接查看



```java
// 一个简单的demo
public class MockRedisServer {
    public static void main(String[] args) throws IOException {
        ServerSocket serverSocket = new ServerSocket(6379);
        Socket socket = serverSocket.accept();
        try (InputStream inputStream = socket.getInputStream();
            final OutputStream outputStream = socket.getOutputStream()) {
            byte[] data = new byte[1024];
            final int read = inputStream.read(data);
            final byte[] bytes = Arrays.copyOf(data, read);
            System.out.println(new String(bytes));
        }
    }
}
```



<!-- more -->

这时用`Jedis`进行连接

```java
// 这时客户端会报错，因为我们模拟的非常简单，没有实现真正的功能返回数据
Jedis jedis = new Jedis("127.0.0.1", 6379);
jedis.set("k1", "v1");

// 在服务端将会看到如下输出
*3
$3
SET
$2
k1
$2
v1
```

具体这些内容是什么意思呢？其实这就是RESP(REdis Serialization Protocol)协议的格式

## Redis通信协议-RESP

Redis客户端与服务端通信使用 RESP(REdis Serialization Protocol)协议

它是一个序列化协议，支持如下几种数据类型，具体类型判断通过第一个字节判断，之间通过"\r\n"来分隔

- 简单字符串    以"+"开头
- 错误类型        以"-"开头
- 整数                以":"开头
- 块字符串        以"$"开头
- 数组                以"*"开头

**客户端每次发送一个块字符串数组到服务端，服务端根据命令执行后返回结果**

### 简单字符串

以"+"字符开头，后面接实际字符串，最后以"\r\n"结尾

因为字符是通过'\r\n'来判断结尾的，所以此种类型中的字符串内容就不能包含这特殊字符，如果有需要可以使用块字符串类型

例子：`+OK\r\n`

### 错误类型

以"-"字符开头，后面接着错误错误信息，最后以"\r\n"结尾

例子：`-Error message\r\n`

### 整数

以":"字符开头，后面为具体数值，最后以"\r\n"结尾

例子：`:1000\r\n`

### 块字符串

以"$"字符开头，后面是字符串的实际长度，之后以"\r\n"分隔，接着是字符串内容，最后以'\r\n'结尾

例子：

```
foobar : $6\r\nfoobar\r\n
// 为了方便阅读，可以简化为
$6
foobar
```

空字符串：`$0\r\n\r\n`

Null(不存在的值)：`$-1\r\n`

### 数组

以"*"开头，后面是数组长度，之后以"\r\n"分隔，后面是具体的其他的数据值(数据类型不要求一致)

空数组：`*0\r\n`

```
["1", "foo"]：*2\r\n$1\r\n1\r\n$3\r\nfoo\r\n
方便阅读，简化为：
*2           // 数组长度为2
$1           // 此元素为长度为1的简单字符
1            // 字符内容为"1"
$3           // 此元素为长度为3的简单字符
foo          // 字符内容为"foo"
```

如果是队列阻塞超时，则返回值为：`*-1\r\n`

现在再让我们看一下之前demo中的返回值就会很明了了，这里简单解释一下

```java
// 原始命令 set k1 v1
*3       -长度为3的数组
$3       -一个长度为3的字符串
SET      -字符内容为 "SET"
$2       -一个长度为2的字符串
k1       -字符内容为 "k1"
$2       -一个长度为2的字符串
v1       -字符内容为 "v1"
```



这里有一个简单的实现几个功能的[demo](https://github.com/zavier/lite-redis)

参考资料：[protocol-spec](https://redis.io/docs/reference/protocol-spec/)

