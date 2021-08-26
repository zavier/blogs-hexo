---
title: transmittable-thread-local浅析
date: 2021-08-22 19:16:29
tags: [java]
---



之前简单介绍过 [ThreadLocal](/2020/03/22/threadlocal/)，但是其中有个问题就是当一个请求中使用到线程池时，无法将主线程中ThreadLocal中的值传递进去，这次我们就看下怎么解决这个问题

比较直接的的方法就是包装一下Runnable或Callable，在创建的时候将主线程中ThreadLocal对应内容传递保存进去，之后执行的时候再取出来重新赋值到对应ThreadLocal中，使用之后再清理掉即可，大致样子如下

```java
public class SimpleThreadLocalTest {
    // 创建一个线程池及姓名的ThreadLocal
    private Executor executor = Executors.newSingleThreadExecutor();
    public static ThreadLocal<String> USER_NAME_THREAD_LOCAL = new ThreadLocal<>();

    @Test
    public void test() {
        USER_NAME_THREAD_LOCAL.set("zheng");
        executor.execute(new ThreadLocalRunnable());
    }
    
    static class ThreadLocalRunnable implements Runnable {
        private String userName;
        // 自己定义一个Runnable实现，在创建的时候，记录主线程在ThreadLocal中设置的值
        public ThreadLocalRunnable() {
            this.userName = USER_NAME_THREAD_LOCAL.get();
        }

        @Override
        public void run() {
            try {
                // 在线程池中执行时，重新设置值到ThreadLocal中供后续业务逻辑使用
                USER_NAME_THREAD_LOCAL.set(userName);
                // todo 业务逻辑
                System.out.println("userName: " + USER_NAME_THREAD_LOCAL.get());
            } finally {
                // 使用后进行清理
                USER_NAME_THREAD_LOCAL.remove();
            }
        }
    }
}
```

这里很明显可以看出来，自定义的Runnable实现与系统中定义的ThreadLocal进行了强耦合，当有更多的ThreadLocal时会使代码很难维护，比较幸运的是，这种工具已经有了比较好的开源实现，这里就介绍下[transmittable-thread-local](https://github.com/alibaba/transmittable-thread-local)

<!-- more --> 

## 使用

先来看下它的使用方法

```java
public class TtlMain {
    ExecutorService executorService = Executors.newSingleThreadExecutor();
    // 这里要将ThreadLocal替换为 TransmittableThreadLocal
    TransmittableThreadLocal<String> nameThreadLocal = new TransmittableThreadLocal<>();


    @Test
    public void test() {
        // 父线程中进行ThreadLocal赋值
        nameThreadLocal.set("zheng");

        // 注意这里要用TtlRunnable包装一下Runnable
        Runnable r = TtlRunnable.get(() -> {
            // 这里进行业务逻辑的处理，如获取TransmittableThreadLocal中的值，进行使用等
            final String s = nameThreadLocal.get();
            System.out.println(s);
        });
        // 在线程池中执行任务
        executorService.execute(r);
    }
}
```

如果觉得每次使用TtlRunnable进行包装比较麻烦，可以使用它提供的线程池进行包装

```java
public class TtlMain {
    // 使用 TtlExecutors.getTtlExecutorService 对线程池进行包装，就可以不使用 TtlRunnable
    ExecutorService executorService = TtlExecutors.getTtlExecutorService(Executors.newSingleThreadExecutor());

    TransmittableThreadLocal<String> nameThreadLocal = new TransmittableThreadLocal<>();

    @Test
    public void test() {
        nameThreadLocal.set("zheng");

        executorService.execute(() -> {
            final String s = nameThreadLocal.get();
            System.out.println(s);
        });
    }
}
```



## 原理

原理部分相对啰嗦些，着急知道结果的可以直接看小结部分

### TransmittableThreadLocal

这里面有个很重要的类：TransmittableThreadLocal，先来看下它的get, set方法部分源码实现

这里可以看到，它继承了InheritableThreadLocal，在 get 和 set 时直接调用父类 InheritableThreadLocal 的方法，就是在set时多了一步，会将TransmittableThreadLocal的实例统一保存起来，这个后面在进行跨线程赋值传递的时候会用到，不需要到处去找都有哪些TransmittableThreadLocal实例的数据要进行复制

```java
// TransmittableThreadLocal 继承了 InheritableThreadLocal
public class TransmittableThreadLocal<T> extends InheritableThreadLocal<T> implements TtlCopier<T> {
    // get时，直接调用父类InheritableThreadLocal的get方法即可
    @Override
    public final T get() {
        T value = super.get();
        if (disableIgnoreNullValueSemantics || null != value) addThisToHolder();
        return value;
    }

    @Override
    public final void set(T value) {
        if (!disableIgnoreNullValueSemantics && null == value) {
            remove();
        } else {
            // 设置值时，先调用父类InheritableThreadLocal的 set 方法
            super.set(value);
            // 将此TransmittableThreadLocal实例添加到holder的key中
            addThisToHolder();
        }
    }

    // InheritableThreadLocal中存储的是Map结构，
    // 其中的key为 TransmittableThreadLocal，value没有使用，永远为null
    // 这里维护了所有使用到的TransmittableThreadLocal实例，统一添加到holder中，后面使用时比较方便
    private static final InheritableThreadLocal<WeakHashMap<TransmittableThreadLocal<Object>, ?>> holder =
            new InheritableThreadLocal<WeakHashMap<TransmittableThreadLocal<Object>, ?>>() {
                @Override
                protected WeakHashMap<TransmittableThreadLocal<Object>, ?> initialValue() {
                    return new WeakHashMap<TransmittableThreadLocal<Object>, Object>();
                }

                @Override
                protected WeakHashMap<TransmittableThreadLocal<Object>, ?> childValue(WeakHashMap<TransmittableThreadLocal<Object>, ?> parentValue) {
                    return new WeakHashMap<TransmittableThreadLocal<Object>, Object>(parentValue);
                }
            };

    // 将此次增加的TransmittableThreadLocal添加到holder中
    // 通过此方法，可以将所有用到的TransmittableThreadLocal实例统一记录下来
    private void addThisToHolder() {
        if (!holder.get().containsKey(this)) {
            holder.get().put((TransmittableThreadLocal<Object>) this, null);
        }
    }
}
```

因为TransmittableThreadLocal中处理holder还有一个threadLocalHolder，所以对于使用了ThreadLocal，无法替换为TransmittableThreadLocal的情况，它也提供了对应的注册方法，可以注册到TransmittableThreadLocal的threadLocalHolder中

```java
// 使用注册代码
Transmitter.registerThreadLocalWithShadowCopier(threadLocal);
// 自己实现TtlCopier
Transmitter.registerThreadLocal(threadLocal, copyLambda);
// 不再使用后进行注销
Transmitter.unregisterThreadLocal(threadLocal);
```

对应的部分源码：

```java
public static <T> boolean registerThreadLocalWithShadowCopier(@NonNull ThreadLocal<T> threadLocal) {
    return registerThreadLocal(threadLocal, (TtlCopier<T>) shadowCopier, false);
}

public static <T> boolean registerThreadLocal(@NonNull ThreadLocal<T> threadLocal, @NonNull TtlCopier<T> copier, boolean force) {
    if (threadLocal instanceof TransmittableThreadLocal) {
        logger.warning("register a TransmittableThreadLocal instance, this is unnecessary!");
        return true;
    }

    synchronized (threadLocalHolderUpdateLock) {
        if (!force && threadLocalHolder.containsKey(threadLocal)) return false;

        WeakHashMap<ThreadLocal<Object>, TtlCopier<Object>> newHolder = new WeakHashMap<ThreadLocal<Object>, TtlCopier<Object>>(threadLocalHolder);
        newHolder.put((ThreadLocal<Object>) threadLocal, (TtlCopier<Object>) copier);
        threadLocalHolder = newHolder;
        return true;
    }
}
```

后面在处理的时候，可以发现对于holder和threadLocalHolder是处理逻辑是相同的

同时，如果我们用深拷贝的需求，可以实现TransmittableThreadLocal子类，重写copy方法即可

```java
TransmittableThreadLocal<String> nameThreadLocal = new TransmittableThreadLocal<String>() {
    @Override
    public String copy(String parentValue) {
        // 实现自己的复制逻辑
        return super.copy(parentValue);
    }
};
```



### Transmitter

除此之外，还有一个很重要的类：Transmitter，它是TransmittableThreadLocal的一个内部类，主要用来在线程切换时进行数据的快照保存(capture)、重放(replay)和恢复(restore)，在看源码之前先看一下使用的例子

1. 利用Transmitter将主线程的数据快照进行记录
2. 在子线程/线程池中执行时，将记录的快照数据进行重新设置到当前线程，并将当前子线程的数据进行备份
3. 执行完毕后将备份的数据恢复到当前线程数据中

```java
public void test1() {
    // 记录主线程当时的数据快照
    Object captured = Transmitter.capture();
    Callable<String> callable = () -> {
        // 将记录的主线程快照进行重放，并将当前子线程的数据快照进行备份
        Object backup = Transmitter.replay(captured); // (2)
        try {
            System.out.println("Hello");
            return "World";
        } finally {
            // 执行完毕之后，恢复之前备份的子线程快照数据
            Transmitter.restore(backup); // (3)
        }
    };
    executorService.submit(callable);
}
```

下面依次看下这几个步骤的实现

#### Transmitter.capture

这个方法本身比较简单，它是在主线程中执行的，主要就是将之前记录到的所有TransmittableThreadLocal实例数据转成对应map进行返回

```java
public static class Transmitter {

    public static Object capture() {
        // 将复制的数据保存到快照类中
        return new Snapshot(captureTtlValues(), captureThreadLocalValues());
    }

    // 将之前holder中记录的所有使用到的TransmittableThreadLocal实例复制出来
    private static HashMap<TransmittableThreadLocal<Object>, Object> captureTtlValues() {
        HashMap<TransmittableThreadLocal<Object>, Object> ttl2Value = new HashMap<TransmittableThreadLocal<Object>, Object>();
        for (TransmittableThreadLocal<Object> threadLocal : holder.get().keySet()) {
            ttl2Value.put(threadLocal, threadLocal.copyValue());
        }
        return ttl2Value;
    }

    // 这个方式是用于将threadLocalHolder中的ThreadLocal复制出来
    private static HashMap<ThreadLocal<Object>, Object> captureThreadLocalValues() {
        final HashMap<ThreadLocal<Object>, Object> threadLocal2Value = new HashMap<ThreadLocal<Object>, Object>();
        for (Map.Entry<ThreadLocal<Object>, TtlCopier<Object>> entry : threadLocalHolder.entrySet()) {
            final ThreadLocal<Object> threadLocal = entry.getKey();
            final TtlCopier<Object> copier = entry.getValue();

            threadLocal2Value.put(threadLocal, copier.copy(threadLocal.get()));
        }
        return threadLocal2Value;
    }
}

//快照类
private static class Snapshot {
    final HashMap<TransmittableThreadLocal<Object>, Object> ttl2Value;
    final HashMap<ThreadLocal<Object>, Object> threadLocal2Value;

    private Snapshot(HashMap<TransmittableThreadLocal<Object>, Object> ttl2Value, HashMap<ThreadLocal<Object>, Object> threadLocal2Value) {
        this.ttl2Value = ttl2Value;
        this.threadLocal2Value = threadLocal2Value;
    }
}
```

#### Transmitter.replay

这个方法是在子线程/线程池中执行的，用于将快照中的数据设置到当前线程中，并将当前线程中的数据进行备份返回

```java
// 这里主要分析下replayTtlValues方法，replayThreadLocalValues逻辑类似就不看了
public static Object replay(@NonNull Object captured) {
    final Snapshot capturedSnapshot = (Snapshot) captured;
    return new Snapshot(replayTtlValues(capturedSnapshot.ttl2Value), replayThreadLocalValues(capturedSnapshot.threadLocal2Value));
}

@NonNull
private static HashMap<TransmittableThreadLocal<Object>, Object> replayTtlValues(@NonNull HashMap<TransmittableThreadLocal<Object>, Object> captured) {
    HashMap<TransmittableThreadLocal<Object>, Object> backup = new HashMap<TransmittableThreadLocal<Object>, Object>();

    // 遍历当前子线程中的所有TransmittableThreadLocal
    for (final Iterator<TransmittableThreadLocal<Object>> iterator = holder.get().keySet().iterator(); iterator.hasNext(); ) {
        TransmittableThreadLocal<Object> threadLocal = iterator.next();

        // 将当前子线程的数据进行备份
        backup.put(threadLocal, threadLocal.get());

        // 快照中没有的TransmittableThreadLocal实例要进行删除
        // 避免使用到在调用capture之后添加的值
        if (!captured.containsKey(threadLocal)) {
            iterator.remove();
            threadLocal.superRemove();
        }
    }

    // 为TransmittableThreadLocal设置当前线程对应的值
    // 之前的值是其他线程设置的，读取不到，所以方法中对应的是用value的值进行再次赋值
    setTtlValuesTo(captured);

    // 执行TransmittableThreadLocal的beforeExecute方法，一般为空方法，此处可以忽略
    doExecuteCallback(true);

    return backup;
}

private static void setTtlValuesTo(HashMap<TransmittableThreadLocal<Object>, Object> ttlValues) {
    for (Map.Entry<TransmittableThreadLocal<Object>, Object> entry : ttlValues.entrySet()) {
        TransmittableThreadLocal<Object> threadLocal = entry.getKey();
        threadLocal.set(entry.getValue());
    }
}
```



#### Transmitter.restore

这个方法是在子线程/线程池中执行的，用于在业务逻辑处理完成后，将子线程之前的线程相关数据进行恢复，也即是进行使用后的清理恢复工作

```java
public static void restore(@NonNull Object backup) {
    final Snapshot backupSnapshot = (Snapshot) backup;
    restoreTtlValues(backupSnapshot.ttl2Value);
    restoreThreadLocalValues(backupSnapshot.threadLocal2Value);
}

private static void restoreTtlValues(HashMap<TransmittableThreadLocal<Object>, Object> backup) {
    // 直接忽略：调用TransmittableThreadLocal.afterExecute方法，一般也是空方法
    doExecuteCallback(false);
    // 遍历当前线程设置过的所有TransmittableThreadLocal信息
    for (final Iterator<TransmittableThreadLocal<Object>> iterator = holder.get().keySet().iterator(); iterator.hasNext(); ) {
        TransmittableThreadLocal<Object> threadLocal = iterator.next();

        // 如果存在备份数据中不存在的TransmittableThreadLocal，则进行删除处理
        if (!backup.containsKey(threadLocal)) {
            iterator.remove();
            threadLocal.superRemove();
        }
    }

    // 重新设置值
    setTtlValuesTo(backup);
}

private static void setTtlValuesTo(@NonNull HashMap<TransmittableThreadLocal<Object>, Object> ttlValues) {
    // 重新为当前线程的TransmittableThreadLocal设置备份的值
    for (Map.Entry<TransmittableThreadLocal<Object>, Object> entry : ttlValues.entrySet()) {
        TransmittableThreadLocal<Object> threadLocal = entry.getKey();
        threadLocal.set(entry.getValue());
    }
}
```



有了上面的这些类和方法进行支撑，TtlRunnable或者TtlExecutors等进行使用时就比较容易了，我们简单看一下

```java
public final class TtlRunnable implements Runnable, TtlWrapper<Runnable>, TtlEnhanced, TtlAttachments {
    private final AtomicReference<Object> capturedRef;
    private final Runnable runnable;
    private final boolean releaseTtlValueReferenceAfterRun;

    // 构造函数，记录保证runnable及主线程的中的数据快照，这里调用了Transmitter.capture（之前已经分析）
    private TtlRunnable(Runnable runnable, boolean releaseTtlValueReferenceAfterRun) {
        this.capturedRef = new AtomicReference<Object>(capture());
        this.runnable = runnable;
        this.releaseTtlValueReferenceAfterRun = releaseTtlValueReferenceAfterRun;
    }

    // 这里就是标准的处理逻辑，在子线程中进行 replay, 执行业务逻辑，再restore
    @Override
    public void run() {
        // 线程池/子线程中执行时，获取快照中的数据
        final Object captured = capturedRef.get();
        if (captured == null || releaseTtlValueReferenceAfterRun && !capturedRef.compareAndSet(captured, null)) {
            throw new IllegalStateException("TTL value reference is released after run!");
        }
        // 重新设置快照中的数据到当前线程中，并创建当前线程的数据进行备份
        final Object backup = replay(captured);
        try {
            // 执行业务逻辑
            runnable.run();
        } finally {
            // 执行后将备份的数据恢复
            restore(backup);
        }
    }
}
```



## 小结

通过上面的分析，可以发现核心类其实就是两个：`TransmittableThreadLocal` 和 `Transmitter`

在使用 TransmittableThreadLocal 时，它在将值保存到父类 InheritableThreadLocal 中的同时，会将当前的 TransmittableThreadLocal 实际进行存储，这样使用完成后，它自己就会维护一份所有用到的TransmittableThreadLocal 实例，不管它是用户信息的，还是其他信息的实例

有了上面维护的信息，就可以借助Transmitter来对其中的数据进行操作，一般操作步骤如下

1. 主线程：调用Transmitter.capture，将当前主线程中的所有TransmittableThreadLocal和值进行快照保存(Map结构，结果要作为value进行存储，否则其他线程取不到TransmittableThreadLocal的value值)
2. 子线程：调用Transmitter.replay，用于将之前保存的所有TransmittableThreadLocal实例及其值重新设置一下（需要借助之前保存的map结构，因为TransmittableThreadLocal中的数据是线程隔离的），并将当前线程的所有TransmittableThreadLocal实例进行备份返回
3. 子线程：业务代码执行完毕之后调用Transmitter.restore，用于将之前备份的数据进行恢复，原理同replay方法
