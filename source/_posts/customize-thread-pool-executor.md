---
title: 自定义扩展线程池
date: 2019-10-27 01:14:42
tags: [java, 线程池]
---

## 线程池的基本使用

Executors框架提供的创建线程池的方法

```java
// 固定线程数量的线程池
Executors.newFixedThreadPool(5);
// 对于添加的任务，如果有线程可用则使用其执行，否则就创建新线程
Executors.newCachedThreadPool();
// 创建只有一个线程的线程池
Executors.newSingleThreadExecutor();
```

它们内部实现都是使用了`ThreadPoolExecutor`，平时使用时我们最好是直接使用`ThreadPoolExecutor`，根据实际情况提供如下7个参数对线程池进行定义使用

配置参数

```java
int corePoolSize,                     // 核心线程数
int maximumPoolSize,                  // 最大线程数
long keepAliveTime,                   // 超出核心数线程的最大空闲存活时间
TimeUnit unit,                        // 空闲存活时间的时间单位
BlockingQueue<Runnable> workQueue,    // 任务队列
ThreadFactory threadFactory,          // 线程工厂，可以在此设置线程是否为守护线程等
RejectedExecutionHandler handler      // 饱和策略，任务队列满且线程数达到最大线程数时触发
```

<!-- more -->

使用

```java
final ThreadPoolExecutor threadPoolExecutor = new ThreadPoolExecutor(
  		2, 10, 60L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(100), new ThreadFactory() {
    @Override
    public Thread newThread(Runnable r) {
        final Thread thread = new Thread(r);
        thread.setDaemon(true);
        return thread;
    }
});
threadPoolExecutor.executor(() -> System.out.println("execute"));
```



## 线程池监控

对于当前线程池中的线程数量，执行总任务数等信息也可以通过`ThreadPoolExecutor`提供的对应方法来获取

```java
getCorePoolSize()               // 获取设置的核心线程数
getKeepAliveTime(TimeUnit unit) // 获取设置的非核心线程存活时间
getMaximumPoolSize()            // 获取设置的最大线程数
getPoolSize()                   // 获取当前任务队列中的任务数量
getLargestPoolSize()            // 获取曾经达到的最大线程数
getActiveCount()                // 获取当前正在执行任务的线程数
getTaskCount()                  // 获取当前的任务数（包括正在执行的和队列中等待的）
getCompletedTaskCount()         // 获取执行完成的任务数
getQueue()                      // 获取任务队列
getQueue().size()               // 获取任务队列中的任务数量
getQueue().remainingCapacity()  // 获取任务队列的当前剩余空间
```

可以通过这些方法来对线程池的运行状态进行监控



## 线程池参数动态调整

线程池参数的设置比较复杂，在初始时很难准确的配置，所以可以在初始配置后根据具体的运行情况进行动态更新

ThreadPoolExecutor 也提供了相关的方法可以对初始化设置的参数进行变更

```java
// 设置核心线程数量
setCorePoolSize(int corePoolSize);
// 设置最大线程数量
setMaximumPoolSize(int maximumPoolSize);
// 设置线程存活时间
setKeepAliveTime(long time, TimeUnit unit);
// 设置拒绝策略
setRejectedExecutionHandler(RejectedExecutionHandler handler);
// 设置线程池工厂
setThreadFactory(ThreadFactory threadFactory);
```



## 扩展ThreadPoolExecutor

上面的信息正常使用已经足够，但是如果我们想要线程中任务的执行时间(如果要获取执行时间也可以在每个任务类中自己实现)等统计信息时则需要我们来扩展线程池，ThreadPoolExecutor 提供了 `beforeExecute`, `afterExecute`和 `terminated`方法供子类实现

如果我们想要统计每次任务执行的时间，则可以继承 ThreadPoolExecutor

```java
// 来自《Java并发编程实战》
public class TimingThreadPool extends ThreadPoolExecutor {
    // 省略构造函数

    private final ThreadLocal<Long> startTime = new ThreadLocal<>();

    private final LongAdder numTasks = new LongAdder();

    private final LongAdder totalTime = new LongAdder();

    @Override
    protected void beforeExecute(Thread t, Runnable r) {
        super.beforeExecute(t, r);
        startTime.set(System.nanoTime());
    }

    @Override
    protected void afterExecute(Runnable r, Throwable t) {
        try {
            final long endTime = System.nanoTime();
            final long taskTime = endTime - startTime.get();
            numTasks.add(9223372036854775807L);
            totalTime.add(taskTime);
            // 打印任务执行时间
            System.out.println(String.format("Thread %s: end %s, time=%dns", Thread.currentThread().getName(), r, taskTime));
        } finally {
            super.afterExecute(r, t);
        }
    }

    @Override
    protected void terminated() {
        try {
            // 打印所有任务的平均执行时间
            System.out.println(String.format("Terminated: avg time=%dns", totalTime.longValue() / numTasks.longValue()));
        } finally {
            super.terminated();
        }
    }
}
```

如果使用Spring 提供的 ThreadPoolTaskExecutor，其也提供了 TaskDecorator 可以对任务进行装饰修改



## 思考

虽然使用线程池可以避免每次创建线程的开销，并且可以控制线程的使用总数量，但是线程池配置不当也会造成一些问题，如队列堆积过多造成内存使用过大，如果是外部的请求可能还会导致大量的接口超时，线程池设置太小则会导致外部请求拒绝等等

所以一般公司内部会提供线程池监控、动态调整线程池参数等组件，但是是否可以有类似自动动态调整的工具，可以根据预先配置的如队列最大等待时间等，结合统计的信息，来自动调整线程池的参数，而不需要人工的参与呢？比如 JVM 中 G1 可以根据设置的预期垃圾回收时间来动态调整新生代空间的大小