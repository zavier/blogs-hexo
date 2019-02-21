---
title: AbstractQueuedSynchronizer简述
date: 2019-02-20 20:48:15
tags: java
---

AbstractQueuedSynchronizer 是一个用于在竞争资源（如多线程）时使用的同步器，它内部使用了一个`int`类型的字段`status`表示需要同步的资源状态， 并基于一个先进先出（FIFO）的等待队列，队列中的每个节点表示要获取资源的线程

工作流程

同步器主要是用于控制资源的获取以及释放，它可以用于独占模式和共享模式，这里我们以独占模式为例

>  在获取和释放资源时，我们需要实现自己的尝试获取和尝试释放的方法，利用`status`字段来控制成功与否

<!-- more -->

获取资源

```java
// 在独占模式下尝试获取资源
protected boolean tryAcquire(int arg) {
    // 尝试获取资源与释放资源都是依靠 status 来实现具体的逻辑
    // 可以基于 status 与 arg 字段来实现此方法 （我们可以赋予status任何意义来实现逻辑）
}
```

获取资源的源码如下（独占模式）
1. 首先尝试获取资源，如果成功直接返回，进行后续流程
2. 失败则创建一个新节点，将其添加到链表尾部（如果链表为空，则先创建一个空的表头再添加）
3. 之后判断当前节点前一个节点是不是头结点，如果是则再次尝试获取资源，成功则将当前节点置为头节点，进行获取资源后的流程
4. 如果当前节点前一个节点不是头结点，那么将当前节点中的线程阻塞（阻塞前务必将其前一节点状态改为signal）,等待被唤醒
5. 唤醒后跳转到第3步

```java
public final void acquire(int arg) {
    if (!tryAcquire(arg) &&
        acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
        selfInterrupt();
}
```

释放资源

```java
// 在独占模式下尝试释放资源
protected boolean tryRelease(int arg) {
    // 尝试获取资源与释放资源都是依靠 status 来实现具体的逻辑
    // 可以基于 status 与 arg 字段来实现此方法 （我们可以赋予status任何意义来实现逻辑）
}
```

释放资源的源码如下（独占模式）
1.首先尝试释放资源
2.成功后判断，如果头结点不为null，同时其状态不是初始0值（需要有后继节点更改其状态），那么将当前节点状态置为0，同时唤醒下一节点中线程

```java

public final boolean release(int arg) {
    if (tryRelease(arg)) {
        Node h = head;
        if (h != null && h.waitStatus != 0)
            unparkSuccessor(h);
        return true;
    }
    return false;
}
```



共享模式与独占模式基本相同

区别主要在于此方法，当线程被唤醒后获取资源，如果成功且返回值>0，则会继续唤醒后续线程
返回负数：失败
返回0：成功，但是其他线程无法再获取资源
返回正数：成功，其他线程可能继续获取资源（需要尝试后知道）

```java
protected int tryAcquireShared(int arg) {
    // todo
}
```



下面举一个《Java并发编程实战》中的二元闭锁例子来说明AQS的使用

```java
/**
 * 使用 AQS 实现的二元闭锁（所有线程都会阻塞，直到状态改变被唤醒，此时所有线程都得到执行）
 * status表是开关状态，=0时关闭，=1时开启
 */
public class OneShotLatch {

    private final Sync sync = new Sync();

    public void signal() {
        sync.releaseShared(0);
    }

    public void await() throws InterruptedException {
        sync.acquireSharedInterruptibly(0);
    }

    private class Sync extends AbstractQueuedSynchronizer {

        /**
         * 如果闭锁是开的 （state==1），那么这个操作成功，否则失败阻塞
         * @param ignored
         * @return
         */
        @Override
        protected int tryAcquireShared(int ignored) {
            return (getState() == 1) ? 1: -1;
        }

        /**
         * 打开status状态开关，放开所有线程
         * @param ignored
         * @return
         */
        @Override
        protected boolean tryReleaseShared(int ignored) {
            setState(1);
            return true;
        }
    }
    
    // 测试方法
    public static void main(String[] args) throws Exception {
        OneShotLatch oneShotLatch = new OneShotLatch();
        for (int i = 0; i < 3; i++) {
            new Thread(() -> {
                try {
                    oneShotLatch.await();
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
                System.out.println("completed");
            }).start();
        }

        // 2S后唤醒
        TimeUnit.SECONDS.sleep(2);
        oneShotLatch.signal();
        TimeUnit.SECONDS.sleep(5);
        System.out.println("end");
    }
}
```

**小结**

使用AQS后，我们要做的就是通过status来控制请求和释放资源操作及是否成功，而AQS会负责在获取失败后将其放入队列，等待有释放资源操作后被唤醒，进而再次请求资源等操作

