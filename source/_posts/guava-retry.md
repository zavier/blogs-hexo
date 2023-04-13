---
title: Java异常重试-GuavaRetrying
date: 2023-04-12 07:48:29
tags: [异常重试, guava-retrying, java]
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
        // 单次执行超时时间配置，超时则异常
        .withAttemptTimeLimiter(AttemptTimeLimiters.fixedTimeLimit(200, TimeUnit.MILLISECONDS))
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

可以看到整体源码比较简单清晰

<img src="/images/guava-retrying.png" style="zoom:60%" />

我们直接通过调用方法的代码来看一下各个类的用途

```java
// com.github.rholder.retry.Retryer
public V call(Callable<V> callable) throws ExecutionException, RetryException {
    long startTime = System.nanoTime();
    for (int attemptNumber = 1; ; attemptNumber++) {
        Attempt<V> attempt;
        try {
            // 1. 执行实际方法调用(如有超时配置，达到超时时间后会抛出异常，再次进行重试)
            V result = attemptTimeLimiter.call(callable);
            // 2. 成功后则包装成功结果
            attempt = new ResultAttempt<V>(result, attemptNumber, TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime));
        } catch (Throwable t) {
            // 3. 假如执行异常时也先包装异常的结果，不抛出异常
            attempt = new ExceptionAttempt<V>(t, attemptNumber, TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startTime));
        }

        // 4. 异常监听器通知处理
        for (RetryListener listener : listeners) {
            listener.onRetry(attempt);
        }

        // 5. 这里就是我们之前配置的需要重试的条件汇总，如retryIfRuntimeException等
        // 如果全部都没有匹配上，则说明不需要重试，此时会直接返回结果或抛出异常
        if (!rejectionPredicate.apply(attempt)) {
            return attempt.get();
        }
        // 6. 如果前面的重试条件匹配上了，则会进入这里，进行是否停止重试的判断(一般不可能允许无限重试)
        // 比如配置了最多重试三次，或者从第一次尝试到现在已经达到了多少时间等等
        // 如果需要停止，则也不会再次进行重试，直接抛出异常
        if (stopStrategy.shouldStop(attempt)) {
            throw new RetryException(attemptNumber, attempt);
        } else {
            // 7. 计算重试的间隔时间
            long sleepTime = waitStrategy.computeSleepTime(attempt);
            try {
                // 8. 阻塞达到间隔时间结束
                blockStrategy.block(sleepTime);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RetryException(attemptNumber, attempt);
            }
        }
    }
}
```

这样我们就比较好理解下面的类的作用了

```
.
├── Attempt                          // 执行的结果包装(可能成功或失败) 【接口】
├── AttemptTimeLimiter               // 执行时间限制接口(实际方法由它执行)【接口】
├── AttemptTimeLimiters              // 执行时间限制接口实现工厂类【类】
├───── FixedAttemptTimeLimit         // 固定限制执行时间【类】
├───── NoAttemptTimeLimit            // 不限制执行时间【类】
├── BlockStrategy                    // 执行阻塞策略接口【接口】
├── BlockStrategies                  // 执行阻塞策略工厂类【类】
├───── ThreadSleepStrategy           // 通过Thread.sleep进行阻塞的实现【类】
├── RetryException                   // 重试异常类【类】
├── RetryListener                    // 重试监听器接口【接口】
├── Retryer                          // 实际执行重试器【类】
├───── ExceptionAttempt              // 执行异常的结果包装【类】
├───── ResultAttempt                 // 执行成功的结果包装【类】
├───── RetryerCallable               // 没有使用..【类】
├── RetryerBuilder                   // 重试构造器【类】
├───── ExceptionClassPredicate       // 用于异常类型判断是否需要重试断言【类】
├───── ExceptionPredicate            // 根据异常进行判断是否需要重试断言【类】
├───── ResultPredicate               // 根据执行结果判断是否需要重试断言【类】
├── StopStrategy                     // 终止策略【接口】
├── StopStrategies                   // 终止策略实现工厂类【类】
├───── NeverStopStrategy             // 永不终止【类】
├───── StopAfterAttemptStrategy      // 限制最多重试次数进行终止【类】
├───── StopAfterDelayStrategy        // 限制总执行时间进行终止【类】
├── WaitStrategy                     // 等待时间计算策略【接口】
├── WaitStrategies                   // 等待时间计算策略实现工厂【类】
├───── CompositeWaitStrategy         // 复合等待时间计算类（聚合其他实现类）【类】
├───── ExceptionWaitStrategy         // 根据特定类型异常计算等待时间【类】
├───── ExponentialWaitStrategy       // 每次等待时间进行指数增长【类】
├───── FibonacciWaitStrategy         // 每次等待时间进行fibonacci方式增长【类】
├───── FixedWaitStrategy             // 每次都是固定的等待时间【类】
├───── IncrementingWaitStrategy      // 根据初始值和指定值，每次重试增加指定值时间【类】
└───── RandomWaitStrategy            // 指定一个时间范围，每次在其中进行随机取值【类】
```

