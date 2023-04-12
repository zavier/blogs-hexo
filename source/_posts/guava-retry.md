---
title: Java异常重试-GuavaRetrying
date: 2023-04-12 07:48:29
tags: [retry, guava-retrying, java]
---

重试在项目中还是比较常见的一个场景，比如调用外部服务因为网络等原因的异常，重试一次可能就成功了，而不需要立即给用户反馈错误，提高体验

假设我们自己来写一个最简单异常重试的话，可能代码是这样子的

```java
int retryTime = 3;
for (int i = 0; i < retryTime; i++) {
    try {
        // 方法调用
        return service.query();
    } catch (Throwable e) {
        log.info("调用异常，进行重试");
    }
}
```

这里可能有几个问题需要考虑

1. 不仅仅是异常需要重试，有时接口返回的特定错误码也是需要重试的
2. 不是所有的异常都可以重试，需要根据情况判断异常原因才能重试
3. 有时失败不能立即重试，需要等待一小段时间，比如短时网络波动
4. 重试停止不一定只需要次数，有时也需要判断整体用的时间等因素

这么一看，需要考虑的地方还挺多，而重试功能又是一个非常通用的功能，所以完全可以包装一下做成通用的能力

而这个目前已经有一些现成的工具供我们使用，这次我们就先看下 [guava-retrying](https://github.com/rholder/guava-retrying)

<!-- more -->

### 快速使用

首先需要引入依赖包

```xml
<dependency>
  <groupId>com.github.rholder</groupId>
  <artifactId>guava-retrying</artifactId>
  <version>2.0.0</version>
</dependency>
```

然后就可以使用了

```java
// 1. 将方法调用包装成一个 callable
Callable<Boolean> callable = new Callable<Boolean>() {
    public Boolean call() throws Exception {
        return true; // do something useful here
    }
};

// 2. 配置重试相关策略（根据具体使用进行调整配置）
Retryer<Boolean> retryer = RetryerBuilder.<Boolean>newBuilder()
        // 结果是null进行重试
        .retryIfResult(Predicates.<Boolean>isNull())
        // IO异常进行重试
        .retryIfExceptionOfType(IOException.class)
        // 运行时异常进行重试
        .retryIfRuntimeException()
        // 固定间隔等待(也可以设置其他等待策略)
        .withWaitStrategy(WaitStrategies.fixedWait(100, TimeUnit.MILLISECONDS))
        // 3次重试后停止
        .withStopStrategy(StopStrategies.stopAfterAttempt(3))
        .build();
try {
    retryer.call(callable);
} catch (RetryException e) {
    e.printStackTrace();
} catch (ExecutionException e) {
    e.printStackTrace();
}
```



### 实现分析

