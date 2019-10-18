---
title: Redis内存优化小技巧
date: 2019-06-21 01:07:59
tags: redis
---

在Redis中，相同的数据，如果我们使用不同的数据结构来存储，它们使用的内存大小差异可能是非常大的，要想更多的节省空间，我们不仅仅需要了解Redis的几种常用数据类型，还需要了解他们内部在不同情况下使用的具体数据结构

之前曾整理过一篇[Redis每种数据类型及对应的内部结构](https://zhengw-tech.com/2019/02/07/Redis数据结构概览/)，如果对此不太了解的同学可以先大致看一下



## 压缩数据结构

Redis为`hash`、`set`、`zset`都提供了对应的节约空间的数据结构存储方式，合理使用它们可以大大节约内存空间

下面以`hash`结构举例，其他的结构也是类似的

<!-- more -->

`hash`内部有两种结构

### hashtable -哈希表

这是我们比较熟悉的一种结构，内部使用数组与链表结合，正常使用数组，如果遇到冲突则使用链表

查找迅速但是比较占用空间

### ziplist - 压缩列表

使用条件：

1. 键和值的长度都不能超过64字节（可通过 hash-max-ziplist-value配置）
2. 键值对数量小于512个（可通过 hash-max-ziplist-entries配置）

ziplist的使用条件虽然苛刻了一些，但是如果满足条件后，则可以节省很多的空间

它内部使用的是一段连续内存空间，将键值对紧挨着排列在其中，这样虽然查询的时候需要顺序遍历，但是如果数据量不大其实并没有什么影响，这也是空间和时间的平衡



我们来看一个具体的例子：

假设我们目前由10万个键值对要保存到Redis中，形式如：`key=object:123 value=val`，一种比较简单且容易想到的做法就是使用string结构，都以key-value的形式存储到Redis中，这种做法有什么问题呢？

首先，db中的key其实也都是以字典表的形式存储的，如果db中的key数量不断增多，会需要不断重新rehash分配空间，效果和都放到一个hash结构中差不多，而且应该也能想象的到，字典表为了快速查找且降低key冲突，它需要一些额外的空间，所以它并不节省内存。其实我们可以尝试将这些键值对分组，打散到多个小的hash结构中去



我们可以先来测试一下，分别以string和hash来存储相同数据，看一下效果

```go
// 存储 object:[1-100000]  val 的键值对
func main() {
    client := redis.NewClient(&redis.Options{
        Addr: "127.0.0.1:6379",
    })

    fmt.Println("start kvUsedMemory test")
    kvUsedMemory(client)

    fmt.Println("=========================")
    fmt.Println("start hashUserMemory test")
    hashUserMemory(client)
}

// 使用hash结构，field中字符串长度最大为2
func hashUserMemory(client *redis.Client) {
    // 先清空数据
    client.FlushAll()

    info := client.Info("memory")
    fmt.Print("before add used memory: ")
    printUsedMemory(info.Val())

    client.Pipelined(func(pipeliner redis.Pipeliner) error {
        for i := 0; i < 100000; i++ {
            if i < 100 {
                pipeliner.HSet("object:", string(i), "val")
            } else {
                v := strconv.Itoa(i)
                pipeliner.HSet("object:" + v[:len(v)-2], v[len(v)-2:], "val")
            }
        }
        return nil
    })
    fmt.Print("after add 100_000 hash used memory:")
    info = client.Info("memory")
    printUsedMemory(info.Val())
}

// 使用string存储
func kvUsedMemory(client *redis.Client) {
    // 先清空数据
    client.FlushAll()

    info := client.Info("memory")
    fmt.Print("before add used memory: ")
    printUsedMemory(info.Val())

    client.Pipelined(func(pipeliner redis.Pipeliner) error {
        for i := 0; i < 100000; i++ {
            pipeliner.Set("object:" + strconv.Itoa(i), "val", -1);
        }
        return nil
    })
    fmt.Print("after add 100_000 kv used memory:")
    info = client.Info("memory")
    printUsedMemory(info.Val())
}

// 获取打印 memoryinfo中的使用内存信息
func printUsedMemory(memoryinfo string) {
    fmt.Println(strings.Split(strings.Split(memoryinfo, "\r\n")[2], ":")[1])
}

```

结果如下

```txt
start kvUsedMemory test        // 大约使用6M空间
before add used memory: 2.00M
after add 100_000 kv used memory:7.89M
=========================
start hashUserMemory test     // 使用了不到1M空间
before add used memory: 2.00M
after add 100_000 hash used memory:2.84M
```

具体结果可能略有差异，但是仍然可以很明显的看出，使用 hash结构比string节省了很多的空间



## 分片结构

分片简单来说，就是将数据按照一定规则分为许多小部分

上面我们说到的压缩结构，可以节省内存空间，但它往往存在一些限制：只有在数据满足特定情况（一般是数据长度比较小，数量比较少时）才会使用压缩的数据结构，如果数据量大了就不会使用了。这时我们就可以使用分片，将大的数据拆成一个一个小的数据结构，这样就可能会触发使用压缩结构的条件，同时还避免了大key的问题

在分片时，可以尽量让分片后的结构向压缩结构的条件上面靠，甚至可以略微调整触发它的条件

对于hash结构，我们需要写一个根据key计算出分片键的函数

```java
public String shardKey(String base, String key, int shardNumber) {
    CRC32 crc32 = new CRC32();
    crc32.update(key.getBytes());
    int shardId = (int)(crc32.getValue() % shardNumber);
    return String.format("%s:%s", base, shardId);
}
```

这样查询和获取的时候，先通过key计算出分片键，使用其作为存储的key

```java
public Long shardHash(String base, String key, String value, int shardNumber) {
    String shardKey = shardKey(base, key, shardNumber);
    return jedis.hset(shardKey, key, value);
}
```







