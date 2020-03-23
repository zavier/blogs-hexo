---
title: 从源码看ThreadLocal
date: 2020-03-22 16:46:11
tags: java
---

对于多线程并发对数据的修改的情况，其实除了使用锁或者CAS机制之外，有的情况我们完全可以为每一个线程分配单独的数据，这个数量只能在对应的线程下才能访问到，这样就能避免资源的争抢，JDK提供的对应功能的类就是ThreadLocal

## 使用

先来看下最简单的例子

```java
private static ThreadLocal<String> nameThreadLocal = new ThreadLocal<>();

private static ExecutorService executorService = Executors.newSingleThreadExecutor();

public static void main(String[] args) throws Exception {
    // 在当前线程中设置值
    nameThreadLocal.set("zheng");
    testGet();
    executorService.shutdown();
}

private static void testGet() {
    // 在当前线程中获取
    String name = nameThreadLocal.get();
    System.out.println("相同线程获取名称：" + name);

    // 在另一个线程中获取threadlocal中的值
    executorService.execute(() -> {
        String name1 = nameThreadLocal.get();
        System.out.println("不同线程获取名称：" + name1);
    });
}
```

<!-- more -->

输出结果如下：

```
相同线程获取名称：zheng
不同线程获取名称：null
```

即在哪个线程下设置的值，则只有在对应的线程下才能获取到，其他线程无法获取和操作

比如在用户登录时，我们可以把用户信息设置到当前线程的ThreadLocal中，这样即使不用参数传递，后面执行的所有方法也可以获取到对应的值。当然，在使用结束后一定不要忘了调用`remove()`方法清除对应的值，不然在线程池等复用线程场景下会出现问题

## 原理

作为一个技术人，只会使用是不能让我们满足的，下面我们就一起看看这个到底是怎么实现的

为了避免大家心急，先来简单说一下结论，之后我们再去看源码（基于JDK1.8）

![threadlocal](/images/threadlocal.jpg)

其实在每个Thread类中，也就是每个线程中都有一个 ThreadLocalMap 类型的变量，这个类和我们平时使用的HashMap等的原理其实是比较相像的，如果大家对于HashMap的原理不太熟悉，可以参考一下我之前的[文章](https://zhengw-tech.com/2019/06/01/java-rehash/)，这里就不再介绍了

在这个Map中的key就是我们之前定义的ThradLocal实例，获取值时，在当前线程的ThreadLocalMap中根据ThreadLocal实例去匹配即可，由于不同线程是不同的Thread实例，所以ThreadLocalMap是独立的，互相不可见



好，现在开始进入源码分析阶段，先从`set`方法开始

```java
// ThreadLocal
public void set(T value) {
    // 从当前线程中获取 ThreadLocalMap 实例
    Thread t = Thread.currentThread();
    ThreadLocalMap map = getMap(t);
    // 不存在则创建ThreadLocalMap
    // 存在则添加键值对，key为当前ThreadLocal实例,value为对应值
    if (map != null)
        // 1. 添加到ThreadLocalMap中
        map.set(this, value);
    else
        createMap(t, value);
}

// 从线程Thread中获取对应的ThreadLocalMap类型变量threadLocals
// public class Thread implements Runnable {
//    ThreadLocal.ThreadLocalMap threadLocals = null;
// }
ThreadLocalMap getMap(Thread t) {
    return t.threadLocals;
}

// 初始化创建Map
void createMap(Thread t, T firstValue) {
    t.threadLocals = new ThreadLocalMap(this, firstValue);
}
```

上面的部分看起来还是比较简单的，我们再接着看下键值对是如何添加到ThreadLocalMap中的（对应上面源码中标注的1处），先看下ThreadLocalMap中的几个关键属性

```java
static class ThreadLocalMap {
    // 用于存储键值对 <ThreadLocal, value>
    // 注意：从这里可以看出来，其中的key也就是ThreadLocal实例是一个弱引用
    static class Entry extends WeakReference<ThreadLocal<?>> {
        Object value;
        Entry(ThreadLocal<?> k, Object v) {
            super(k);
            value = v;
        }
    }
    private static final int INITIAL_CAPACITY = 16;
    // Entry数组，储存对应的键值对数据
    private Entry[] table;
    private int size = 0;
    private int threshold;
    // ...
}
```



**弱引用**

这里要先提一下弱引用，弱引用是只要发生了GC，就会被回收掉（相关的还有强引用，软引用，虚引用等）

而这里Entry是继承了WeakReference的，但是要注意一下，只有其中的ThreadLocal引用是弱引用，而其中的value并不是弱引用的，在发生垃圾回收时，只有ThreadLocal部分会被回收，value并不会

所以，如果出现`Entry e != null && e.get() == null`时，说明其中的key被垃圾回收掉了



接下来分析 ThreadLocalMap的set方法

```java
// ThreadLocalMap
private void set(ThreadLocal<?> key, Object value) {
    Entry[] tab = table;
    int len = tab.length;
    // 1. 注意这里的获取索引位置与HashMap有很大的不同
    int i = key.threadLocalHashCode & (len-1);

    // 获取对应索引位置，如果其中不为null说明发生了哈希冲突
    // 这时会判断如果key相等（同一个ThradLocal实例)则进行值替换
    // 如果之前key已经被垃圾回收，则进行值替换
    // 否则进行索引递增查询查找，找到第一个为空的槽位进行插入
    for (Entry e = tab[i];
         e != null;
         // 顺序循环重找，具体可以见下面的方法体
         e = tab[i = nextIndex(i, len)]) {
        ThreadLocal<?> k = e.get();

        // 直接使用==比较，判断是否是同一个ThreadLocal实例
        // 2. 注意这里的key比较也与HashMap不同
        if (k == key) {
            e.value = value;
            return;
        }
        
        if (k == null) {
            // 3. e不为null, k==null说明之前的key已经被垃圾回收了，可以替换赋值
            replaceStaleEntry(key, value, i);
            return;
        }
    }

    tab[i] = new Entry(key, value);
    int sz = ++size;
    // 先进行一下清除被垃圾回收的槽位操作，如果有清除操作就不再判断是否需要rehash
    // 4. 如果没有清除任何槽位，则判断是否达到rehash阈值，达到则进行rehash
    if (!cleanSomeSlots(i, sz) && sz >= threshold)
        rehash();
}

// 依次顺序递增，循环获取索引
private static int nextIndex(int i, int len) {
    return ((i + 1 < len) ? i + 1 : 0);
}
```



**索引计算及冲突处理**

先来对比HashMap说一下槽位的定位及发生哈希冲突时的处理方式，对应上述源码标记1，2处

*HashMap*：在HashMap中，计算槽位使用的是key对应类的hashCode()，哈希冲突时先使用使用equals方法比较是否是同一个key，真正冲突后在对应槽位形成链表（达到8个后会转为红黑树）

在HashMap中，计算槽位使用的是key对应类的hashCode()，哈希冲突时先使用使用equals方法比较是否是同一个key，真正冲突后在对应槽位形成链表（达到8个后会转为红黑树）

*ThreadLocalMap*：对比着我们看下ThreadLocalMap

```java
// 计算索引的方法
int i = key.threadLocalHashCode & (len-1);


// 每个实例独立的变量
private final int threadLocalHashCode = nextHashCode();
// 每次创建新实例时，threadLocalHashCode都会依次递增
private static int nextHashCode() {
    return nextHashCode.getAndAdd(HASH_INCREMENT);
}
// 静态变量，初始值为0
private static AtomicInteger nextHashCode =
    new AtomicInteger();
// 每次创建新实例，threadLocalHashCode递增的值
private static final int HASH_INCREMENT = 0x61c88647;
```

很明显可以看出来，ThreadLocalMap的key对应的索引位计算并不依赖hashCode方法，而是使用了一个每次创建都会递增的一个值（0x61c88647这个值大家有兴趣可以去搜索了解一下）

在哈希冲突时，也没有使用equals方法进行后续比较，而是直接使用了==比较，因为它不需要像我们业务处理时根据根据特定逻辑判断是否相等，不同的实例值一定不能互相覆盖，所以直接判断是否是同一个实例即可

再就是发出真实冲突时，没有使用链表，而是接着此索引向后查找到第一个空的槽位，进行插入





下面再来看下上面标示3处的代码，这里主要处理的情况是在插入时，计算到的索引位已经有值，但是其中的key已经被回收掉了，这时候进行占用相关的操作

```java
if (k == null) {
    // 3. e不为null, k==null说明之前的key已经被垃圾回收了，可以替换赋值
    replaceStaleEntry(key, value, i);
    return;
}

// 进入这里时，可以确定索引位 staleSlot的槽位中的key已经被垃圾回收
// 这个方法主要功能如下
// 1. 先向前获取被垃圾回收key的槽位
// 2. 向后遍历，如果发现相同key的槽位，则将其前置到staleSlot位
//          并替换前面索引对应的值，之后从发现位索引开始向后进行key被垃圾回收的槽位清理
// 3. 如果向后没有找到要相同的key, 则简单替换staleSlot槽位的内容，之后进行key回收节点的清理等
private void replaceStaleEntry(ThreadLocal<?> key, Object value,
                               int staleSlot) {
    Entry[] tab = table;
    int len = tab.length;
    Entry e;

    // 向前遍历有数据(不为null)的槽位，查找到第一个被垃圾回收掉key的槽位的索引
    int slotToExpunge = staleSlot;
    for (int i = prevIndex(staleSlot, len);
         (e = tab[i]) != null;
         i = prevIndex(i, len))
        if (e.get() == null)
            slotToExpunge = i;

    // 向后遍历非空的槽位
    for (int i = nextIndex(staleSlot, len);
         (e = tab[i]) != null;
         i = nextIndex(i, len)) {
        ThreadLocal<?> k = e.get();

        // 如果在要替换的槽位后面又找到了当前ThreadLocal实例的key
        // 则对两个槽位的值进行替换，并将value的值进行覆盖
        if (k == key) {
            e.value = value;
            // 替换后，会导致 i 索引位置对应的key是已经被垃圾回收的槽位
            tab[i] = tab[staleSlot];
            tab[staleSlot] = e;

            // 如果staleSlot前面没有被垃圾回收的key，则从i索引位开始清理被垃圾回收的key
            if (slotToExpunge == staleSlot)
                slotToExpunge = i;
            // expungeStaleEntry 方法负责从i索引位开始清理被垃圾回收的key，
            //    直到遇到为null的槽位并返回对应索引
            // cleanSomeSlots 从索引开始，进行log2(len)次数的垃圾回收key探测
            //    探测到的槽位，也会进行清理操作
            cleanSomeSlots(expungeStaleEntry(slotToExpunge), len);
            return;
        }

        // 当遇到垃圾回收的key
        // 并且staleSlot前面没有被垃圾回收的key，则从i索引位开始清理被垃圾回收的key
        if (k == null && slotToExpunge == staleSlot)
            slotToExpunge = i;
    }

    // 如果后面没有当前ThreadLocal实例的槽位，则与staleSlot位的数据进行覆盖替换
    tab[staleSlot].value = null;
    tab[staleSlot] = new Entry(key, value);

    // 如果staleSlot前面有被垃圾回收的key，则从发现的前面的被垃圾回收key槽位的索引进行清理操作
    if (slotToExpunge != staleSlot)
        cleanSomeSlots(expungeStaleEntry(slotToExpunge), len);
}
```

前面的内容中还涉及了两个方法(`expungeStaleEntry` 和  `cleanSomeSlots`)，我们依次看下

```java
// 这个方法主要对staleSlot索引槽位进行清理
// 并对其后面的（直到遇到未赋值=null的槽位）不在计算索引位的值进行重定位
private int expungeStaleEntry(int staleSlot) {
    Entry[] tab = table;
    int len = tab.length;

    // 清理值
    tab[staleSlot].value = null;
    tab[staleSlot] = null;
    size--;

    // 从当前索引位向后查找所有被垃圾回收的key的槽位，进行清理（直到遇到未赋值=null的槽位）
    // 这个过程中如果遇到计算的索引与当前索引，则重新为其寻找位置（从计算的索引依次向后查找为null的槽位）
    // 返回为null的节点的索引
    Entry e;
    int i;
    for (i = nextIndex(staleSlot, len);
         (e = tab[i]) != null;
         i = nextIndex(i, len)) {
        ThreadLocal<?> k = e.get();
        if (k == null) {
            e.value = null;
            tab[i] = null;
            size--;
        } else {
            int h = k.threadLocalHashCode & (len - 1);
            if (h != i) {
                tab[i] = null;

                // Unlike Knuth 6.4 Algorithm R, we must scan until
                // null because multiple entries could have been stale.
                while (tab[h] != null)
                    h = nextIndex(h, len);
                tab[h] = e;
            }
        }
    }
    return i;
}
```

最后来看下`cleanSomeSlots`方法，这个方法比较简单

```java
// 从i+1位开始，进行log2(n)个数量的扫描
// 如果发现被垃圾回收key的槽位，则对其进行清理
private boolean cleanSomeSlots(int i, int n) {
    boolean removed = false;
    Entry[] tab = table;
    int len = tab.length;
    do {
        i = nextIndex(i, len);
        Entry e = tab[i];
        if (e != null && e.get() == null) {
            n = len;
            removed = true;
            i = expungeStaleEntry(i);
        }
    } while ( (n >>>= 1) != 0);
    return removed;
}
```



对于Map相关类，我们都知道扩容时会进行rehash，所以我们接下来就是看下`ThreadLocalMap`的 rehash 方法

```java
private void rehash() {
    // 遍历所有槽位，对key被垃圾回收的节点进行清理
    expungeStaleEntries();

    // 如果清理后仍达到rehash的阈值，则进行resize
    if (size >= threshold - threshold / 4)
        resize();
}

// 遍历所有槽位，对key被垃圾回收的节点进行清理
private void expungeStaleEntries() {
    Entry[] tab = table;
    int len = tab.length;
    for (int j = 0; j < len; j++) {
        Entry e = tab[j];
        if (e != null && e.get() == null)
            expungeStaleEntry(j);
    }
}

// 扩容两倍，重新计算索引位，遇到key被垃圾回收的节点直接丢弃
private void resize() {
    Entry[] oldTab = table;
    int oldLen = oldTab.length;
    int newLen = oldLen * 2;
    Entry[] newTab = new Entry[newLen];
    int count = 0;

    for (int j = 0; j < oldLen; ++j) {
        Entry e = oldTab[j];
        if (e != null) {
            ThreadLocal<?> k = e.get();
            if (k == null) {
                e.value = null; // Help the GC
            } else {
                int h = k.threadLocalHashCode & (newLen - 1);
                while (newTab[h] != null)
                    h = nextIndex(h, newLen);
                newTab[h] = e;
                count++;
            }
        }
    }

    setThreshold(newLen);
    size = count;
    table = newTab;
}
```

以上就是`set`方法的全部内容



最后我们来看下`get`方法

```java
// ThreadLocal
public T get() {
    Thread t = Thread.currentThread();
    ThreadLocalMap map = getMap(t);
    if (map != null) {
        // 调用 ThreadLocalMap.getEntry方法
        ThreadLocalMap.Entry e = map.getEntry(this);
        if (e != null) {
            T result = (T)e.value;
            return result;
        }
    }
    return setInitialValue();
}

// ThreadLocalMap.getEntry方法 内容如下
private Entry getEntry(ThreadLocal<?> key) {
    // 计算索引
    int i = key.threadLocalHashCode & (table.length - 1);
    Entry e = table[i];
    // 如果索引对应的内容存在，key也没有被垃圾回收，则返回对应的槽位内容
    if (e != null && e.get() == key)
        return e;
    else
        // 否则向后查找
        return getEntryAfterMiss(key, i, e);
}

private Entry getEntryAfterMiss(ThreadLocal<?> key, int i, Entry e) {
    Entry[] tab = table;
    int len = tab.length;
    // 向后查找,如果找到对应key，则返回
    // 如果遇到key被垃圾回收的槽位，则进行清理
    // 否则继续查找，直到遇到内容为null的节点，这时表示节点不存在，返回null
    while (e != null) {
        ThreadLocal<?> k = e.get();
        if (k == key)
            return e;
        if (k == null)
            expungeStaleEntry(i);
        else
            i = nextIndex(i, len);
        e = tab[i];
    }
    return null;
}
```



以上就是ThreadLocal的全部内容，如有错误欢迎指正
