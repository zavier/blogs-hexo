---
title: 定时任务实现原理浅析
date: 2021-09-20 22:50:53
tags: [java]
---



如果我们有想固定间隔时间执行的任务等，自己实现的一种方式是可以新启动一个线程，在其中sleep固定的时间后执行，但是这种方式在任务多的时候肯定是不行的。现在已经有很多现成的工具我们可以直接使用，这里主要介绍一下JDK的`ScheduledThreadPoolExecutor`与Netty的`HashedWheelTimer`，看一下它们的实现原理

<!-- more -->

### ScheduledThreadPoolExecutor

ScheduledThreadPoolExecutor是JDK自带的一个用于执行周期任务的线程池，用法大致如下

```java
// 创建任务线程池
ScheduledThreadPoolExecutor executor = new ScheduledThreadPoolExecutor(5);
// 提交任务
executor.schedule(() -> System.out.println("111"), 1, TimeUnit.SECONDS);
executor.scheduleAtFixedRate(() -> System.out.println("22"), 2, 3, TimeUnit.SECONDS);
executor.scheduleWithFixedDelay(() -> System.out.println("33"), 1, 2, TimeUnit.SECONDS);
```

了解它原理话需要先了解一下线程池的使用，线程池中是多个线程从一个阻塞队列中获取任务来进行执行

<img src="/images/thread-pool-base.jpg" alt="thread-pool-base" style="zoom:50%;" />

ScheduledThreadPoolExecutor是继承了ThreadPoolExecutor，其中最大的一个区别是提供了一个延迟工作队列`DelayedWorkQueue`，内部是一个优先级队列，需要最先执行的排在最前面，每次插入数据的时候会重新排序

同时还实现了`ScheduledFutureTask`任务类，其中除了记录原始任务外还会记录任务要执行的时间等信息

这样每次拿到任务的时候都是需要最先执行的，判断下如果到达了执行时间就可以执行



### HashedWheelTimer

使用ScheduledThreadPoolExecutor最大的一个问题是每次提交任务的时候，都会再次进行一下队列的排序，这个工作时间复杂度为O(nlogn)，下面我们看一下HashedWheelTimer的使用例子及实现

```java
// 使用示例
HashedWheelTimer timer = new HashedWheelTimer();
Timeout timeout = timer.newTimeout(new TimerTask() {
    @Override
    public void run(Timeout timeout) throws Exception {
        System.out.println("111");
    }
}, 1, TimeUnit.SECONDS);
```

实现原理如下图所示

<img src="/images/hash-wheel-timer.png" alt="hash-wheel-timer" style="zoom:50%;" />

有一个固定长度的数组（时间轮），有一个可以理解为指针，每隔固定时间(tickDuration)会移动到下一个数组索引上，循环往复。当指针到达对应数组元素时，会获取链表中的元素进行遍历，如果任务达到了指定轮次和执行时间就执行，否则减少其中的轮次

每个数组元素有一个定时任务的链表，当有一个定时任务提交时，会根据它距离执行的时间，和任务线程启动的时间，来根据差值计算出任务需要放置到的索引位置（超过一圈的会增加一个轮次），插入到对应的链表中 O(1) 。



下面分析一下对应源码，我们只根据主线看一下最核心的流程，相关代码进行了简化调整

```java
// 初始化 HashedWheelTimer
HashedWheelTimer timer = new HashedWheelTimer();
```

看下基础的构造器

```java
// 基础构造器（代码已进行简化）
public HashedWheelTimer(
        ThreadFactory threadFactory,
        long tickDuration, TimeUnit unit, int ticksPerWheel, boolean leakDetection,
        long maxPendingTimeouts) {
    // 创建对应的数组 ticksPerWheel默认值为512
    wheel = createWheel(ticksPerWheel);
    // 掩码，用于按位与计算定位索引使用，类似HashMap索引定位方法
    mask = wheel.length - 1;

    // tickDuration默认100ms，将其转为纳秒值后，进行赋值
    long duration = unit.toNanos(tickDuration);
    this.tickDuration = duration;

    // 创建任务线程(只会创建一个)
    workerThread = threadFactory.newThread(worker);
}
```

之后开始添加任务

```java
Timeout timeout = timer.newTimeout(new TimerTask() {
    @Override
    public void run(Timeout timeout) throws Exception {
        System.out.println("111");
    }
}, 1, TimeUnit.SECONDS);
```

进入对应的源码

```java
public Timeout newTimeout(TimerTask task, long delay, TimeUnit unit) {
    // 初始化启动时间startTime(基于此时间计算时间差值定位索引)，启动线程
    start();
    // 用于计算执行时间与startTime的相差时间
    long deadline = System.nanoTime() + unit.toNanos(delay) - startTime;
    // 构造HashedWheelTimeout，添加到对应的队列中 Queue<HashedWheelTimeout> timeouts
    // 后面在另一个线程中会将对应的的任务分派到时间轮上面
    HashedWheelTimeout timeout = new HashedWheelTimeout(this, task, deadline);
    timeouts.add(timeout);
    return timeout;
}

// start函数，进行了一定程度的简化
public void start() {
    switch (WORKER_STATE_UPDATER.get(this)) {
        case WORKER_STATE_INIT:
            if (WORKER_STATE_UPDATER.compareAndSet(this, WORKER_STATE_INIT, WORKER_STATE_STARTED)) {
                // 只有在初始化的时候，这里进行线程的启动
                workerThread.start();
            }
            break;
    }

    // 等待启动线程中初始化startTime后结束（不然后面添加任务时，无法正确使用startTime值）
    while (startTime == 0) {
        try {
            startTimeInitialized.await();
        } catch (InterruptedException ignore) {
        }
    }
}
```

线程中对应的代码如下（为了便于理解和关注重点，代码已进行简化调整，详情可以查看对应源码）

```java
private final class Worker implements Runnable {
    public void run() {
        // 初始化 startTime
        startTime = System.nanoTime();
        // 唤醒之前外层的start()函数
        startTimeInitialized.countDown();
    
        // 这个任务是一个循环任务，只要是启动状态就会一直循环执行
        do {
            // 获取并等待到下一次执行的时间（相对启动的时间差）
            final long deadline = waitForNextTick();
            if (deadline > 0) {
                // tick为轮次，计算对应要处理的索引
                int idx = (int) (tick & mask);
                // 将已取消队列中的任务进行清理
                processCancelledTasks();
                HashedWheelBucket bucket = wheel[idx];
                // 将timeouts队列中的任务计算后分派到时间轮对应槽位上
                transferTimeoutsToBuckets();
                // 进行槽位中所有到期任务的执行(具体在下面分析)
                bucket.expireTimeouts(deadline);
                // 轮次+1
                tick++;
            }
        } while (WORKER_STATE_UPDATER.get(HashedWheelTimer.this) == WORKER_STATE_STARTED);
    
        // 忽略：未执行的任务等清理工作
    }
  
    // 获取并等待到下一次执行的时间（相对启动的时间差）
    private long waitForNextTick() {
        // 下一轮次的执行时间（相对启动的时间差）
        long deadline = tickDuration * (tick + 1);
    
        // 直到到达执行时间才退出
        for (;;) {
            // 判断到达deadline需要睡眠的时间，如果已经到了则返回当前时间（相对启动的时间差）
            final long currentTime = System.nanoTime() - startTime;
            long sleepTimeMs = (deadline - currentTime + 999999) / 1000000;
          
            // 已到达指定时间
            if (sleepTimeMs <= 0) {
                return currentTime;
            }
            // 时间没到的时候，则sleep差值时间
            Thread.sleep(sleepTimeMs);
        }
    }

  
    // 将timeouts队列中的任务计算后分派到时间轮对应槽位上
    private void transferTimeoutsToBuckets() {
        for (int i = 0; i < 100000; i++) {
            HashedWheelTimeout timeout = timeouts.poll();

            // 用间隔时间除以时间轮的执行周期(默认100ms),计算槽位位置
            // 可能大于总槽位数，后面会再次进行计算
            long calculated = timeout.deadline / tickDuration;
            // 计算所在的轮次
            timeout.remainingRounds = (calculated - tick) / wheel.length;
            // 防止处理执行过的任务
            final long ticks = Math.max(calculated, tick);
            // 这里计算真正的槽位索引
            int stopIndex = (int) (ticks & mask);
            // 计算后将其添加到对应槽位里面的队列中
            HashedWheelBucket bucket = wheel[stopIndex];
            bucket.addTimeout(timeout);
        }
    }
}
```

最后看下到期任务的执行部分源码

```java
// HashedWheelBucket.expireTimeouts
public void expireTimeouts(long deadline) {
    HashedWheelTimeout timeout = head;

    // 获取槽位对应的链表头，不为空则执行
    while (timeout != null) {
        HashedWheelTimeout next = timeout.next;
        // 对应的任务到达了当前轮次
        if (timeout.remainingRounds <= 0) {
            // 将当前任务从链表摘除，并获取链表的下一个任务
            next = remove(timeout);
            if (timeout.deadline <= deadline) {
                // 到期了执行timeout中TimerTask的run方法
                timeout.expire();
            }
        } else if (timeout.isCancelled()) {
            next = remove(timeout);
        } else {
            // 没有到达指定轮次的时候，将其轮次减少1
            timeout.remainingRounds --;
        }
        // 设置值为下一个任务，进入下一次循环判断
        timeout = next;
    }
}
```



以上就是相关的原理分析，如有错误欢迎指正





