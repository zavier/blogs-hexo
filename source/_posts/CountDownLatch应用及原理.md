---
title: CountDownLatch应用及原理
date: 2019-02-26 22:39:35
tags: java
---

CountDownLatch功能很简单，它主要有两个方法，`await()`与`countDown()`，初始创建的时候需要给它提供一个数值，调用`countDown()`方法会将数值减1，调用`await()`方法的时候会判断值是不是等于0，如果等于0就继续执行，否则就阻塞等待

```java
// 初始化创建，值为1
CountDownLatch countDownLatch = new CountDownLatch(1);
// 如果countDownLatch中的值不是0则阻塞等待
countDownLatch.await();
// 将countDownLatch中的值进行减1
countDownLatch.countDown();
```

利用这两个方法，我们能用来做什么呢？

## 让一组线程等待同时开始

这种用法，我们只需要将`CountDownLatch`的初始值设为1，在需要线程阻塞的地方调用`countDownLatch.await()`方法，当满足开始条件后，调用`countDownLatch.countDown()`方法将类中的值减为0，让其他所有阻塞的线程可以几乎同时得到执行

```java
ExecutorService executorService = Executors.newCachedThreadPool();
CountDownLatch countDownLatch = new CountDownLatch(1);
for (int i = 0; i < 5; i++) {
    executorService.execute(() -> {
        System.out.println(Thread.currentThread().getName() + " waiting...");
        try {
            // 阻塞等待countdownlatch中的值被减为0
            countDownLatch.await();
            System.out.println(Thread.currentThread().getName() + " working...");
         } catch (Exception e) {
            e.printStackTrace();
        }
    });
}

TimeUnit.SECONDS.sleep(4);
System.out.println("\nstart!");
countDownLatch.countDown();
        
executorService.shutdown();
```

执行结果：

```text
pool-1-thread-1 waiting...
pool-1-thread-3 waiting...
pool-1-thread-2 waiting...
pool-1-thread-4 waiting...
pool-1-thread-5 waiting...

start!
pool-1-thread-2 working...
pool-1-thread-3 working...
pool-1-thread-5 working...
pool-1-thread-1 working...
pool-1-thread-4 working...
```



## 等待一组线程执行完毕

这时候，我们需要将`CountDownLatch`的初始值设置为线程的数量，每次执行完毕后调用`countDownLatch.countDown()`方法对值进行减1，等待线程可以调用`countDownLatch.await()`阻塞等待，待所有线程执行完毕后，类中的值减为0，这时阻塞线程就可以继续向下执行了

```java
ExecutorService executorService = Executors.newCachedThreadPool();
int num = 5;
CountDownLatch countDownLatch = new CountDownLatch(num);
System.out.println("start");
for (int i = 0; i < num; i++) {
    executorService.execute(() -> {
       // 加上延时，让效果明显些
        try {
            TimeUnit.SECONDS.sleep(5);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        System.out.println(Thread.currentThread().getName() + " working...");
        countDownLatch.countDown();
    });
}
// 阻塞等待线程执行完成
countDownLatch.await();
System.out.println("task end!");
executorService.shutdown();
```

执行结果：

```text
start
pool-1-thread-4 sworking...
pool-1-thread-3 sworking...
pool-1-thread-5 sworking...
pool-1-thread-2 sworking...
pool-1-thread-1 sworking...
task end!
```



## CountDownLatch内部实现

CountDownLath内部使用AbstractQueuedSynchronizer来实现

将AQS中的staus用作CountDownLatch的初始值

在**获取资源**时会判断status是否等于0，等于0则通过，都则加入AQS中的CLH队列阻塞等待

CountDownLatch核心源码

```java
// 实现AQS中的获取共享资源操作
protected int tryAcquireShared(int acquires) {
    return (getState() == 0) ? 1 : -1;
}

// 实现AQS中的释放共享资源操作
protected boolean tryReleaseShared(int releases) {
    // Decrement count; signal when transition to zero
    for (;;) {
        int c = getState();
        if (c == 0)
            return false;
        int nextc = c - 1;
        if (compareAndSetState(c, nextc))
            return nextc == 0;
    }
}
```

关于AbstractQueuedSynchronizer有不明白的，可以参考之前的**AbstractQueuedSynchronizer简述**

