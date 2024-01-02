---
title: 协程之Kotlin
date: 2024-01-01 23:25:52
tags: [kotlin, 协程]
---

一般我们在 Java 项目中做并发编程，基本都是通过创建线程的方式来执行（JDK21支持了虚拟线程），但是线程有如下问题

- 线程是不能无限创建的，而是受到操作系统的限制
- 线程切换的时候有较高的上下文切换的成本

而协程可以理解为轻量级的线程，可以在一个线程中执行多个任务，而不需要线程切换的开销，同时也避免了线程数量的限制

这里看一下kotlin中的协程，首先需要引入单独的依赖包

```kotlin
// gradle.kts
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0-RC2")
}
```

<!-- more -->

如果需要在主线程中异步执行一些任务，但是主线程要同步等待异步任务结果，可以使用`runBlocking`（结构化并发）

### 无需结果的任务执行

对于不需要获取结果的任务，可以使用如下形式：

```kotlin
// 1. 主线程逻辑
runBlocking {
    // 协程中执行任务1
    launch { /*任务1逻辑*/ }
    // 协程中执行任务2
    launch { /*任务2逻辑*/ }
}
// 2. 协程中不会阻塞主线程，但是主线程会因为runBlocking在这里阻塞等待最终都执行完成
```

下面看一个具体的使用例子：

```kotlin
fun main() {
    println("start ${Thread.currentThread()} ${System.currentTimeMillis()}")
    runBlocking {
        // 启用协程执行任务
        launch {
            delay(2000) 
            // 使用 delay和 yield 方法，会给另一个挂起的协程任务执行机会(因为共用线程，无法真正并行)
            // 这里如果换成TimeUnit.SECOND.sleep(2)，那么会同步阻塞，不会给其他协程任务执行机会，task1执行完成后才会执行task2, 大家有兴趣可以验证下
            println("task 1 ${Thread.currentThread()} ${System.currentTimeMillis()}")
        }
        // 启用协程执行任务
        launch {
            delay(1000)
            println("task 2 ${Thread.currentThread()} ${System.currentTimeMillis()}")
        }
        println("runBlocking ${Thread.currentThread()} ${System.currentTimeMillis()}")
    }
    println("done ${Thread.currentThread()} ${System.currentTimeMillis()}")
}
```

执行结果

```
// 可以看到线程ID都是相同的，说明都是在同一个线程内执行完成，但是任务明显不都是同步顺序执行的
start Thread[#1,main,5,main] 1704114721498
runBlocking Thread[#1,main,5,main] 1704114721583
task 2 Thread[#1,main,5,main] 1704114722600       -- 启动后，过了1s执行task2
task 1 Thread[#1,main,5,main] 1704114723592       -- 启动后，过了2s执行task1
done Thread[#1,main,5,main] 1704114723593         -- 等待task1与task2都执行完成
```



### 需要结果的任务执行

如果需要获取协程中执行的结果，那么上面的形式可以进行如下修改：

1. 将 launch 改为 async
2. async返回结果类型为 Deferred\<T\>
3. 调用 Deferred#await方法同步获取结果

（这部分类似 Java 中的 Future 和 Future#get）

```kotlin
// 1. 主线程逻辑
runBlocking {
    // 协程中执行任务1
    val defer1: Deferred<T> = async { /*任务1逻辑*/ }
    // 协程中执行任务2
    val defer2: Deferred<T> = async { /*任务2逻辑*/ }
    // 获取结果使用 Deferred.await()方法同步等待执行完成
    val result1 = defer1.await()
}
// 2. 协程中不会阻塞主线程，但是主线程会因为runBlocking在这里阻塞等待最终都执行完成
```

下面同样用一个例子看一下具体使用

```kotlin
fun main() {
    runBlocking {
        // 使用 async 执行，返回Deferred
        val count: Deferred<Int> = async {
            println("start ${Thread.currentThread()}")
            Random.nextInt()
        }
        println("runBlocking ${Thread.currentThread()}")
        // 使用 await 方法等待获取结果
        println("count: ${count.await()} ${Thread.currentThread()}")
    }
}
```

执行结果如下

```
runBlocking Thread[#1,main,5,main]
start Thread[#1,main,5,main]
count: -779821096 Thread[#1,main,5,main]
```



### 协程通信

协程间通信可以使用 channel（类似为一个队列）

![coroutine-channel](/images/coroutine-channel.png)

 channel类型可以分为

Unlimited channel : channel中元素无限制，放入过多元素且没有及时消费会出现OOM

Buffered channel: 可以指定缓存的元素数量，当发送到数量上限时，发送调用会被挂起

Rendezvous channel:  可以认为可以缓存的数量为0，发送调用会被挂起，直到有消费方进行消费

Conflated channel: 每次发送到channel的元素都会覆盖之前的元素，所以发送调用永远不会被挂起

```kotlin
fun main() = runBlocking<Unit> {
    // val channel = Channel<String>(Channel.RENDEZVOUS)，参数中可以指定类型
    val channel = Channel<String>()
    launch {
        channel.send("A1")
        channel.send("A2")
        log("A done")
    }
    launch {
        channel.send("B1")
        log("B done")
    }
    launch {
        repeat(3) {
            val x = channel.receive()
            log(x)
        }
    }
}
```

输出：

```
[main] A1
[main] B1
[main] A done
[main] B done
[main] A2
```



### 协程分派

之前看的任务都是在主线程(main)中执行的，我们也可以协程分派到不同的线程中进行执行，下面说的配置同时适用于 launch 和 async

首先，可以在launch中指定分派策略

```kotlin
// Dispatchers.Default  用于CPU密集型任务，池中线程数为2和核心数两个的最大值
// Dispatchers.IO       用于IO密集型任务，线程数适当多一些
runBlocking {
    launch {
        delay(2000)
        println("task 1 ${Thread.currentThread()} ${System.currentTimeMillis()}")
    }
    // task2在另一个线程中执行
    launch(Dispatchers.IO) {
        delay(1000)
        println("task 2 ${Thread.currentThread()} ${System.currentTimeMillis()}")
    }
    println("runBlocking ${Thread.currentThread()} ${System.currentTimeMillis()}")
}
```

执行结果

```kotlin
start Thread[#1,main,5,main] 1704115043212
runBlocking Thread[#1,main,5,main] 1704115043297
task 2 Thread[#21,DefaultDispatcher-worker-1,5,main] 1704115044305  // 单独线程
task 1 Thread[#1,main,5,main] 1704115045304
done Thread[#1,main,5,main] 1704115045306
```

如果觉得默认提供的不适用，也可以使用自定义的线程池

```kotlin
// 使用自定义线程池，使用use会在执行完毕后关闭线程池
ThreadPoolExecutor(5, 10, 60, TimeUnit.SECONDS, ArrayBlockingQueue(20))
    .asCoroutineDispatcher().use { dispatcher ->
        runBlocking {
            launch(dispatcher) {
                TimeUnit.SECONDS.sleep(1)
                println("task 2 ${Thread.currentThread()} ${System.currentTimeMillis()}")
            }
            println("runBlocking ${Thread.currentThread()} ${System.currentTimeMillis()}")
        }
    }
```



如果挂起后再执行时切换线程，可以使用 launch的第二个参数(start = CoroutineStart.UNDISPATCHED)，当然还有一些其他的选项可以自行参考一下文档～

```kotlin
ThreadPoolExecutor(5, 10, 60, TimeUnit.SECONDS, ArrayBlockingQueue(20))
    .asCoroutineDispatcher().use { dispatcher ->
        runBlocking {
            // 设置start参数值，UNDISPATCHED为初始在当前线程执行，挂起恢复后切换线程
            launch(context = dispatcher, start = CoroutineStart.UNDISPATCHED) {
                println("task 2 ${Thread.currentThread()} ${System.currentTimeMillis()}")
            }
            println("runBlocking ${Thread.currentThread()} ${System.currentTimeMillis()}")
        }
    }
```



runBlocking中要切换线程上下文，可以使用 withContext

```kotlin
ThreadPoolExecutor(5, 10, 60, TimeUnit.SECONDS, ArrayBlockingQueue(20))
    .asCoroutineDispatcher().use { dispatcher ->
        runBlocking {
            // 使用withContext切换调用协程任务的线程
            withContext(Dispatchers.IO) {
                println("task 2.1 ${Thread.currentThread()} ${System.currentTimeMillis()}")
            }

            launch(context = dispatcher, start = CoroutineStart.UNDISPATCHED) {
                TimeUnit.SECONDS.sleep(1)
                println("task 2.2 ${Thread.currentThread()} ${System.currentTimeMillis()}")
            }
            println("runBlocking ${Thread.currentThread()} ${System.currentTimeMillis()}")
        }
    }

// 输出
start Thread[#1,main,5,main] 1704117793052
task 2.1 Thread[#21,DefaultDispatcher-worker-1,5,main] 1704117793154
task 2.2 Thread[#1,main,5,main] 1704117794162
runBlocking Thread[#1,main,5,main] 1704117794163
done Thread[#1,main,5,main] 1704117794165
```

