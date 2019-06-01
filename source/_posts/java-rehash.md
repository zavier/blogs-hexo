---
title: 漫谈 Java HashMap的Rehash
date: 2019-06-01 10:34:08
tags: java
---

我们都知道Java中的HashMap是使用数组，结合链表来实现的，其结构如下：

<img src="/images/hashmap.jpg" style="zoom:60%" />

如果加入的元素数量达到了设定的阈值，那么必然会涉及到扩容重新分配空间，将元素重新插入到新的空间中，也就是发生了rehash。这个过程其实是很耗时的，这也是为什么我们写代码时，最好指定的HashMap的初始空间大小的原因，就是为了避免或者减少发生rehash的次数。下面我们来看看这个过程的具体实现。

JDK是一直在升级的，其中的代码也在不断优化调整，我们这次主要就看下`JDK1.7`和 `JDK1.8`中的实现

<!-- more -->

## JDK1.7

了解实现就免不了看源码，我们先来看下put方法的主要源码（为了方便阅读，省略了部分代码）

```java
public V put(K key, V value) {
    int hash = hash(key.hashCode());
    // 计算数组索引，插入
    int i = indexFor(hash, table.length);
    addEntry(hash, key, value, i);
    return null;
}

void addEntry(int hash, K key, V value, int bucketIndex) {
    Entry<K,V> e = table[bucketIndex];
    table[bucketIndex] = new Entry<>(hash, key, value, e);
    if (size++ >= threshold)
        // 插入后总数量达到了阈值，发生rehash，扩容一倍
        resize(2 * table.length);
}

void resize(int newCapacity) {
    Entry[] newTable = new Entry[newCapacity];
    // 创建新的数组，并将老的数据转换过去
    transfer(newTable);
    // 查新指定引用空间
    table = newTable;
}

/**
 * 具体转换数据的实现
 * 依次遍历数组元素，重新计算索引插入
 * 如果数组对应元素有链表，那么处理完这个链表后进行下一个索引数据的处理
 */
void transfer(Entry[] newTable) {
    Entry[] src = table;
    int newCapacity = newTable.length;
    // 遍历主数组
    for (int j = 0; j < src.length; j++) {
        Entry<K,V> e = src[j];
        // 如果数组索引对应的元素是个链表，那么将这个链表处理完成再处理下一个索引
        if (e != null) {
            src[j] = null;
            do {
                Entry<K,V> next = e.next;
                int i = indexFor(e.hash, newCapacity);
                // 使用头插法插入到新的空间(可能是链表)中
                e.next = newTable[i];
                newTable[i] = e;
                e = next;
            } while (e != null);
        }
    }
}
```

如果大家对上面的大段代码比较头疼，我就用文字来简单概括一下：

当map中的元素数量达到阈值时，会重新创建一个新的数组，长度为旧数组的两倍(如果长度没有达到上限的话)，这时会依次对旧数组(包括其中的链表)按顺序重新计算索引插入，之后重新赋值引用即可



而我们通常说的HashMap线程不安全，其实主要原因就在上面`transfer`方法中的链表处理逻辑里

简单描述一下，就是当一个线程1持有链表中的一个元素`e`和下一个元素的引用`next`时，如果此时当前线程时间片用完

这时另一个线程2启动，它将整个链表重新rehash完毕，碰巧这几个链表元素还在同一个索引位置，因为链表插入使用头插入，这时的链表顺序和之前就是相反的

此时如果线程1启动，很明显的它持有的`e`和`next`位置被调换了，`next`竟然会持有`e`的引用，这时继续处理的结果就是在这两个元素之前成环状，一旦调用`get`方法处理到这个地方，就会发生死循环

主要的思路就这些，大家如果有兴趣可以继续查看一下其它的资料

下面我们接着来看`JDK1.8`的rehash



## JDK1.8

JDK1.8的HashMap相比1.7进行了比较多的改动，当然，代码量也是增加了很多～

我们还是尽量只看主逻辑

```java
public V put(K key, V value) {
    return putVal(hash(key), key, value, false, true);
}

final V putVal(int hash, K key, V value, boolean onlyIfAbsent,
               boolean evict) {
    Node<K,V>[] tab; Node<K,V> p; int n, i;
    if ((tab = table) == null || (n = tab.length) == 0)
        // 初始化空间
        n = (tab = resize()).length;
    if ((p = tab[i = (n - 1) & hash]) == null)
        // 数组空闲，可以直接插入
        tab[i] = newNode(hash, key, value, null);
    else {
        // 插入链表，这部分逻辑比较复杂
      	// 相比1.7多了一步：如果链表元素过长（达到8个），就会将链表转为红黑树
    }
    ++modCount;
    if (++size > threshold)
        resize();
    afterNodeInsertion(evict);
    return null;
}

final Node<K,V>[] resize() {
    Node<K,V>[] oldTab = table;
    int oldCap = (oldTab == null) ? 0 : oldTab.length;
    int oldThr = threshold;
    int newCap, newThr = 0;

    Node<K,V>[] newTab = (Node<K,V>[])new Node[newCap];
    table = newTab;
    if (oldTab != null) {
        for (int j = 0; j < oldCap; ++j) {
            Node<K,V> e;
            if ((e = oldTab[j]) != null) {
                oldTab[j] = null;
                if (e.next == null)
                    newTab[e.hash & (newCap - 1)] = e;
                else if (e instanceof TreeNode)
                    ((TreeNode<K,V>)e).split(this, newTab, j, oldCap);
                else { // preserve order(这里是关键)
                    Node<K,V> loHead = null, loTail = null;
                    Node<K,V> hiHead = null, hiTail = null;
                    Node<K,V> next;
                    do {
                        next = e.next;
                      	// (1) 确定新索引位置
                        if ((e.hash & oldCap) == 0) {
                            if (loTail == null)
                                loHead = e;
                            else
                                loTail.next = e;
                            loTail = e;
                        }
                        else {
                            if (hiTail == null)
                                hiHead = e;
                            else
                                hiTail.next = e;
                            hiTail = e;
                        }
                    } while ((e = next) != null);
                    if (loTail != null) {
                        loTail.next = null;
                        newTab[j] = loHead;
                    }
                    if (hiTail != null) {
                        hiTail.next = null;
                        newTab[j + oldCap] = hiHead;
                    }
                }
            }
        }
    }
    return newTab;
}
```

我们具体看下其中的链表处理部分，把这部分代码拿出来分析一下

在这之前，我们需要先证明一个结论：

**HashMap rehash重新计算索引后，新索引要么等于原索引位置，要么等于原索引值+原数组大小**

说一下HashMap的几个相关知识点

1. HashMap的数组大小一定是2的N次幂（这是由HashMap自己保证）
2. HashMap的索引计算方式为 hash(key) & (size - 1)，由1可知，size-1的二进制低位都为1
3. HashMap扩容时一般为增大一倍，即size = size * 2，相当于 size = size << 1

其实hash(key) & (size -1)，由于size-1在范围内的值二进制都是1，所以结果就是hash值在数组范围内的值，size值影响的只是取hash值的低位二进制的位数而已，它本身相当于不参与计算。如果不太好理解，再举个例子

如果size=16，size-1的二进制就是`1111`，与hash结果进行按位与运算，就是取hash结果自己的低**4**位值

而如果扩容后size=32，size-1的二进制就是`11111`，与hash结果进行按位与运算，就是取hash结果自己的低**5**位值

这样其实我们就可以得到之前的结论了，对于上面的例子，如果hash结果的倒数第5位是0，那么重新hash后他还在原位置，否则就会在原基础上增加的二进制值是`10000`（oldSize），即 oldIndex + oldSize

基本已经就绪，我们来看代码

```java
// loHead对应的是rehash后还在原位置的，hiHead对应的是newIndex = oldIndex + oldSize
Node<K,V> loHead = null, loTail = null;
Node<K,V> hiHead = null, hiTail = null;
Node<K,V> next;
do {
    next = e.next;
  	// 确定新索引位置,对应之前例子就是判断第5位的值是不是0，如果是0就是rehash后还在原位置的
    if ((e.hash & oldCap) == 0) {
        if (loTail == null)
            loHead = e;
        else
            // 尾插法，保证顺序和之前在前面的元素现在还在前面
            loTail.next = e;
        loTail = e;
    }
    // 这个else表明hash结果对应的位是1，即newIndex = oldIndex + oldSize
    else {
        if (hiTail == null)
            hiHead = e;
        else
            hiTail.next = e;
        hiTail = e;
    }
} while ((e = next) != null);
// 将两个链表插入到对应的新数组位置中
if (loTail != null) {
    loTail.next = null;
    newTab[j] = loHead;
}
if (hiTail != null) {
    hiTail.next = null;
    newTab[j + oldCap] = hiHead;
}
```

总结一下1.8的链表处理部分，因为rehash后新索引只有两种情况

- newIndex = oldIndex
- newIndex = oldIndex + oldSize

这个可以通过`(e.hash & oldCap) == 0`判断，在遍历链表的过程中，使用尾插法(保证前后顺序)将链表分组插入到临时链表中，最后再将链表引用赋值到对应的数组空间中

这种方法其实就解决了1.7中的链表rehash成环的问题



好了，基本内容就是这些，如有错误之处，欢迎指正～