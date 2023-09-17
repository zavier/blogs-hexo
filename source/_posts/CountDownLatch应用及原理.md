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

<!-- more -->

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
pool-1-thread-4 working...
pool-1-thread-3 working...
pool-1-thread-5 working...
pool-1-thread-2 working...
pool-1-thread-1 working...
task end!
```



## CountDownLatch内部实现

CountDownLath内部使用AbstractQueuedSynchronizer来实现

将AQS中的staus用作CountDownLatch的初始值

在**获取资源**时会判断status是否等于0，等于0则通过，否则加入AQS中的CLH队列阻塞等待

在**释放资源**时会对status进行减一操作，如果结果等于0则进行真正的释放操作，将等待队列中的任务唤醒执行

CountDownLatch核心源码

```java
// await 和 countDown时，调用对应内部Sync类方法
public boolean await(long timeout, TimeUnit unit)
    throws InterruptedException {
    return sync.tryAcquireSharedNanos(1, unit.toNanos(timeout));
}

public void countDown() {
    sync.releaseShared(1);
}

// CountDownLatch 内部类，继承AQS，为了方便查看，将AQS中对应代码也粘贴到此处
private static final class Sync extends AbstractQueuedSynchronizer {
  
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
  
    
    // *******  AQS中对应部分代码  ************
    public final boolean releaseShared(int arg) {
        if (tryReleaseShared(arg)) {
            // 如果释放成功，status == 0, 那面唤醒线程
            doReleaseShared();
            return true;
        }
        return false;
    }

    private void doReleaseShared() {
        for (;;) {
            Node h = head;
            if (h != null && h != tail) {
                int ws = h.waitStatus;
                if (ws == Node.SIGNAL) {
                    if (!compareAndSetWaitStatus(h, Node.SIGNAL, 0))
                        continue;            // loop to recheck cases
                    unparkSuccessor(h);
                }
                else if (ws == 0 &&
                         !compareAndSetWaitStatus(h, 0, Node.PROPAGATE))
                    continue;                // loop on failed CAS
            }
            if (h == head)                   // loop if head changed
                break;
        }
    }
}
```

关于AbstractQueuedSynchronizer有不明白的，可以参考之前的[AbstractQueuedSynchronizer简述](https://www.zhengw-tech.com/2019/02/20/AQS%E6%A6%82%E8%BF%B0/)

