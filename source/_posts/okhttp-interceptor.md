---
title: OkHttp拦截器的使用及原理分析
date: 2024-06-29 10:55:11
tags: [拦截器]
---

OkHttp作为一个HTTP客户端，拦截器是其强大的功能之一，它允许用户在请求和响应的声明周期中拦截并修改它们，利用拦截器，我们可以很方便的实现如日志记录、请求加密/签名、响应解密、异常重试等功能。本文将详细介绍一下拦截器的使用方法及其原理

<!-- more -->

## 如何使用拦截器

首先我们先来看下拦截器使用的具体场景感受一下

### 监控打点拦截器

在服务端掉用外部系统的接口，我们一般需要统计一下成功率，TP99等信息，假设我们使用 [cat](https://github.com/dianping/cat) 来支持此监控功能，那么我们就可以定义一个拦截器进行统计上报

```java
public class CatInterceptor implements Interceptor {
    @NotNull
    @Override
    public Response intercept(@NotNull Chain chain) throws IOException {
        final Request request = chain.request();

        Transaction t = Cat.newTransaction("URL", request.url().encodedPath());
        try {
            // 执行实际请求
            Response response = chain.proceed(request);
            t.setStatus(Transaction.SUCCESS);
            return response;
        } catch (Exception e) {
            t.setStatus(e);
            Cat.logError(e);
            throw e;
        } finally {
            t.complete();
        }
    }
}
```

### 自动重试拦截器

如果是查询接口或者请求支持幂等的，我们可以实现一个在返回非2XX或者网络异常时自动重试的功能

```java
public class RetryInterceptor implements Interceptor {

    private int maxRetry;
    // 定义最大重试次数
    public RetryInterceptor(int maxRetry) {
        this.maxRetry = maxRetry;
    }

    @NotNull
    @Override
    public Response intercept(@NotNull Chain chain) throws IOException {
        final Request request = chain.request();
        int currentRetry = 0;
        while (true) {
            try {
                // 执行请求
                final Response response = chain.proceed(request);
                // 如果返回非2XX, 同时可以重试
                if (!response.isSuccessful() && isRecoverable(currentRetry)) {
                    // 关闭响应
                    response.close();
                    // 增加重试次数，进行重试
                    currentRetry++;
                    continue;
                }
                return response;
            } catch (IOException e) {
                // 如果发生异常后不能重试则直接抛出异常，否则进行重试
                if (!isRecoverable(currentRetry)) {
                    throw e;
                }
                currentRetry++;
            }
        }
    }
    
    private boolean isRecoverable(int currentRetry) {
        return currentRetry <= maxRetry;
    }
}
```

### 添加自定义Header

有些情况如鉴权等需要，可能需要设置一些自定义的header，这个也可以通过拦截器来实现

```java
public class TokenHeaderInterceptor implements Interceptor {
    @NotNull
    @Override
    public Response intercept(@NotNull Chain chain) throws IOException {
        Request originalRequest = chain.request();
        Request requestWithUserAgent = originalRequest.newBuilder()
                .header("token", "this is token")
                .build();
        return chain.proceed(requestWithUserAgent);
    }
}
```

之后在构造客户端时配置上拦截器即可

```java
OkHttpClient httpClient = new OkHttpClient.Builder()
  .addInterceptor(new RetryInterceptor(3))
  .addInterceptor(new CatInterceptor())
  .addInterceptor(new TokenHeaderInterceptor())
  .build();
```



## 拦截器的原理

拦截器主要是基于责任链模式，每个拦截器都是一个独立的处理单元，在其中可以选择修改请求/响应报文、可以终止请求返回自定义的结果

OkHttp内部实际都是使用拦截器进行的实现，比如最后一个节点发起真实网络调用的是 CallServerInterceptor 拦截器

一个最简单的使用OkHttp的代码大致如下，我们可以依据这个为入口看一下大致流程

```kotlin
// 构造请求
val okHttpClient = OkHttpClient()
val request = Request.Builder().url("http://localhost:8080/").build()
val call = okHttpClient.newCall(request)
// 发起调用
val execute = call.execute()
println(execute)
```

构造请求的部分先略过，我们直接看发起调用的部分，这部分对应的实际类是 RealCall.kt，对应execute代码如下

```kotlin
// RealCall.kt  execute方法
override fun execute(): Response {
  check(executed.compareAndSet(false, true)) { "Already Executed" }

  timeout.enter()
  callStart()
  try {
    // 执行（这里只是将请求添加到队列中）
    client.dispatcher.executed(this)
    // 使用拦截器获取结果
    return getResponseWithInterceptorChain()
  } finally {
    client.dispatcher.finished(this)
  }
}
```

这里我们重点看一下通过拦截器获取结果这部分

```kotlin
// RealCall.kt  getResponseWithInterceptorChain 方法
@Throws(IOException::class)
internal fun getResponseWithInterceptorChain(): Response {
  // 将用户自定义的拦截器和其默认的拦截器统一添加到链中
  val interceptors = mutableListOf<Interceptor>()
  // 这部分是用户自定义的拦截器
  interceptors += client.interceptors
  // 这里负责处理重试和处理重定向拦截器（重试功能有限，如网络超时等不会重试，需要自己实现）
  interceptors += RetryAndFollowUpInterceptor(client)
  // 主要就是设置 Content-Type 和 User-Agent，以及处理Gzip压缩等
  interceptors += BridgeInterceptor(client.cookieJar)
  // 负责处理HTTP缓存逻辑
  interceptors += CacheInterceptor(client.cache)
  // 初始化网络连接Exchange
  interceptors += ConnectInterceptor
  if (!forWebSocket) {
    // 网络拦截器，需要使用的话可以通过 addNetworkInterceptor 添加
    // 通过拦截器位置也可以看出来，这里是倒数第二层拦截器的位置了，可以进行更底层的一些操作
    // 甚至可以覆盖重写默认的header, 如 Content-Type 等内容
    interceptors += client.networkInterceptors
  }
  // 最后一个拦截器，发起真实的网络调用(使用之前构建的Exchange)
  interceptors += CallServerInterceptor(forWebSocket)

  // 构造最终使用的拦截器链
  val chain =
    RealInterceptorChain(
      call = this,
      // 全部拦截器
      interceptors = interceptors,
      // 这个表示上面拦截器集合的索引，很关键
      index = 0,
      // 后续在 ConnectInterceptor 初始化
      exchange = null,
      request = originalRequest,
      connectTimeoutMillis = client.connectTimeoutMillis,
      readTimeoutMillis = client.readTimeoutMillis,
      writeTimeoutMillis = client.writeTimeoutMillis,
    )

  var calledNoMoreExchanges = false
  try {
    // 调用 RealInterceptorChain 的 proceed方法进行处理
    val response = chain.proceed(originalRequest)
    if (isCanceled()) {
      response.closeQuietly()
      throw IOException("Canceled")
    }
    return response
  } catch (e: IOException) {
    calledNoMoreExchanges = true
    throw noMoreExchanges(e) as Throwable
  } finally {
    if (!calledNoMoreExchanges) {
      noMoreExchanges(null)
    }
  }
}
```

这时候请求就进入到了 RealInterceptorChain 方法中

```kotlin
// RealInterceptorChain.kt proceed 方法
override fun proceed(request: Request): Response {
  check(index < interceptors.size)

  calls++

  if (exchange != null) {
    check(exchange.finder.routePlanner.sameHostAndPort(request.url)) {
      "network interceptor ${interceptors[index - 1]} must retain the same host and port"
    }
    check(calls == 1) {
      "network interceptor ${interceptors[index - 1]} must call proceed() exactly once"
    }
  }

  // 复制 RealInterceptorChain 自身，注意这里将拦截器的索引进行了+1，表示要处理下一个拦截器
  val next = copy(index = index + 1, request = request)
  // 根据上一步传入的索引，获取当前要使用的拦截器
  val interceptor = interceptors[index]

  @Suppress("USELESS_ELVIS")
  val response =
    // 使用当前获取到的拦截器进行处理，请求中的拦截器索引已经设置为下一个
    // 在拦截器中调用 chain.proceed方法，又会进入到这个方法，此时索引变更，会执行下一个拦截器的逻辑
    // 最后一个拦截器 CallServerInterceptor 中并不会调用 chain.proceed，所以流程到此结束进行返回
    interceptor.intercept(next) ?: throw NullPointerException(
      "interceptor $interceptor returned null",
    )

  if (exchange != null) {
    check(index + 1 >= interceptors.size || next.calls == 1) {
      "network interceptor $interceptor must call proceed() exactly once"
    }
  }

  return response
}
```



合理使用拦截器可以帮助我们设计出更健壮、更高效的程序，无论是添加公共头部、日志记录、缓存控制还是重试机制，拦截器都能提供简洁而高效的解决方案。希望本文在大家使用OkHttp的过程中能够有所帮助，如果有任何问题或建议，欢迎交流讨论～
