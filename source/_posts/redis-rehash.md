---
title: Redis Rehash源码分析
date: 2019-06-02 02:35:01
tags: redis
---

接着之前说过的 [Java HashMap的Rehash](/2019/06/01/java-rehash/)，这次我们来看看 Redis中的 hash结构(对应Java中的Map)是如何实现rehash的。

这次先说下结论，它的结构与HashMap基本一致，只是它有两个哈希表，平时只使用其中的第一个，在发生rehash时，会逐渐的将元素转移到另一个表中，全部转移完成后，再将引用赋值给第一个哈希表

下面我们来开始看代码

<!-- more -->

注：为了简化代码，只保留了源码中的主要字段，不是完整源码，需要的可以参看[Redis源码](https://github.com/antirez/redis/blob/unstable/src/dict.h)

```c
// 字典
typedef struct dict {
    // 哈希表（一共有两个，这是rehash的关键）
    dictht ht[2];
    long rehashidx; /* 没有在进行rehash时，rehashidx == -1 */
} dict;

// 哈希表
// 每个字典都使用两个哈希表，从而实现渐进式 rehash（从一个哈希表渐进转到另一个哈希表）
typedef struct dictht {
    dictEntry **table;
    unsigned long size;  // 哈希表的数组长度
    unsigned long sizemask; // 哈希表大小掩码，用于计算索引值，总是等于 size -1
    unsigned long used; // 共有元素节点数量
} dictht;

// 字典中的节点
typedef struct dictEntry {
    void *key;  // 键
    union {... } v; // 值
    struct dictEntry *next; // 链表指针(指向下一节点)
} dictEntry;
```

之前分析Java的HashMap时，我们知道rehash是比较消耗机器性能的，而Redis是单线程的，这个影响只会更大，甚至影响Redis的使用，所以它不是一次完成，而是有严格控制的分次，一点点的将`ht[0]`中的数据转移到`ht[1`]中来完成这个过程。当然，在这个过程中，如果要查询元素，则需要在`ht[0]`和`ht[1]`中都进行检索

```c
// n 表示一次最多转移的数组中索引数量(索引表示对应的整个链表)
int dictRehash(dict *d, int n) {
    int empty_visits = n*10; /* 查找不为空的索引的最大查找数量 */
    if (!dictIsRehashing(d)) return 0; // 如果已经在进行rehash则直接返回

  	// 用于控制转移索引的数量
    while(n-- && d->ht[0].used != 0) {
        dictEntry *de, *nextde;

        // 用于查找到第一个不为空的索引，如果查找到最大上限仍没找到非空索引则结束返回
        while(d->ht[0].table[d->rehashidx] == NULL) {
            d->rehashidx++;
            if (--empty_visits == 0) return 1;
        }
        // 获取ht[0]中的第一个非空索引中的元素
        de = d->ht[0].table[d->rehashidx];
        // 将索引对应的元素及后面的链表(如果存在)全部转移
        while(de) {
            uint64_t h;
            // 拿到要转移的元素后面的一个元素
            nextde = de->next;
            // 获取元素在ht[1]中的索引位置
            h = dictHashKey(d, de->key) & d->ht[1].sizemask;
            // 
            // 使用头插法将元素插入到新位置中
            de->next = d->ht[1].table[h];
            d->ht[1].table[h] = de;
            d->ht[0].used--;
            d->ht[1].used++;
            // 用于判断被转移的元素之前是否有后续链表，有则继续转移
            de = nextde;
        }
      	// 转移完成后，将ht[0]对应索引清空
        d->ht[0].table[d->rehashidx] = NULL;
        // rehashindex维护ht[0]中要进行转移的索引位置
        d->rehashidx++;
    }

    // 检查，如果全部完成后，则将h[1]中的数据赋值给h[0]，清空h[1]并重置rehashidx
    if (d->ht[0].used == 0) {
        zfree(d->ht[0].table);
        d->ht[0] = d->ht[1];
        _dictReset(&d->ht[1]);
        d->rehashidx = -1;
        return 0;
    }
    return 1;
}
```

Rehash的过程基本就是上面所说的了，看完后是不是很好奇，既然是分次转移，那么这个操作是如何触发的呢？

如果对此比较好奇的话，接着往下看



Redis虽然说是单线程的，但是它仍然有一些后台任务在悄悄的运行着

```c
/* This function handles 'background' operations we are required to do
 * incrementally in Redis databases, such as active key expiring, resizing,
 * rehashing. 
 */
// 大意就是：这个函数用来处理后台操作，比如过期key, resizing， rehashing
// 这里删掉一部分暂时不关注的代码
void databasesCron(void) {
    if (server.rdb_child_pid == -1 && server.aof_child_pid == -1) {

        /* Resize */
        // 如果插入数据量达到阈值，会触发resize
        // 初始化ht[1]为rehash后的大小，并将rehash标志位 rehashidx 置为0，表示开始进行了rehash
        for (j = 0; j < dbs_per_call; j++) {
            tryResizeHashTables(resize_db % server.dbnum);
            resize_db++;
        }

        /* Rehash */
        // 上一步只是分配了空间，打开标志为，真正转移数据的部分在下面代码中进行
        if (server.activerehashing) {
            for (j = 0; j < dbs_per_call; j++) {
                // 开始rehash转移数据！！！
                int work_done = incrementallyRehash(rehash_db);
                if (work_done) {
                    /* If the function did some work, stop here, we'll do
                     * more at the next cron loop. */
                    break;
                } else {
                    /* If this db didn't need rehash, we'll try the next one. */
                    rehash_db++;
                    rehash_db %= server.dbnum;
                }
            }
        }
    }
}

int incrementallyRehash(int dbid) {
    /* Keys dictionary */
    // 由于之前resize时已经将标志位打开，所以执行if中的函数
    if (dictIsRehashing(server.db[dbid].dict)) {
        // 使用 1ms 进行rehash
        dictRehashMilliseconds(server.db[dbid].dict,1);
        return 1; /* already used our millisecond for this loop... */
    }
    // 省略过期key的代码处理
    return 0;
}

int dictRehashMilliseconds(dict *d, int ms) {
    long long start = timeInMilliseconds();
    int rehashes = 0;
		// 每次移动 100个数组中的索引，如果用时不到之前指定的1ms则进行进行，否则不再执行
    while(dictRehash(d,100)) {
        rehashes += 100;
        if (timeInMilliseconds()-start > ms) break;
    }
    return rehashes;
}
```

再就是每次插入、删除或者查询时，也会进行rehash，主要代码如下：

```c
// 单步rehash，一次只转移一个索引对应的所有元素
static void _dictRehashStep(dict *d) {
    if (d->iterators == 0) dictRehash(d,1);
}

// 插入
dictEntry *dictAddRaw(dict *d, void *key, dictEntry **existing)
{
  if (dictIsRehashing(d)) _dictRehashStep(d);
  // ... 省略插入逻辑
}

// 查找
dictEntry *dictFind(dict *d, const void *key)
{
    // 如果dict在rehash过程中，则进行单步的数据转移(一个索引对应的所有元素)
    if (dictIsRehashing(d)) _dictRehashStep(d);
    h = dictHashKey(d, key);
    for (table = 0; table <= 1; table++) {
        idx = h & d->ht[table].sizemask;
        he = d->ht[table].table[idx];
        while(he) {
            if (key==he->key || dictCompareKeys(d, key, he->key))
                return he;
            he = he->next;
        }
        if (!dictIsRehashing(d)) return NULL;
    }
    return NULL;
}
```



本篇的主要内容已经讲完了，代码部分有些多，需要大家耐下心来看，都比较简单

内容如有错误之处，欢迎指正～