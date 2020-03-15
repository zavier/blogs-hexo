---
title: Redis RDB与AOF
date: 2020-03-15 00:13:37
tags: redis
---

Redis的存储是基于内存的，这就有意味着，如果服务重启那面之前所有的数据都会丢失，这是我们不能接受的，为此，Redis提供了 RDB 与 AOF 两种持久化机制

## 简介

**RDB**:  对于RDB，我们可以把它理解一个定时的快照，就是每隔一段时间（或其他策略），它会创建一个当时所有数据的一个快照，默认存储到的文件为  dump.rdb

**AOF**: 因为RDB创建的是所有数据的快照，这点就决定了它不可能进行高频率的执行，但是如果不经常性的执行，那么当出现如服务器宕机等情况时，会丢失从上次快照到当前的所有操作数据。为了解决这个问题，AOF应运而生，它会在每次执行操作的时候，将这个操作命令进行持久化存储，默认存储到的文件为 appendonly.aof，这样恢复的时候，可以将 aof文件中的所有命令重新执行一遍，即可恢复数据

<!-- more -->

## 配置及使用

RDB和AOF的配置都在redis的配置文件redis.conf中进行配置，我们看下主要的配置

**RDB的主要配置如下**

```
rdbcompression yes   # 是否使用 LZF算法 压缩字符串
dbfilename dump.rdb  # 持久化存储的文件名称

# save <seconds> <changes>, 表示在多少秒内发生了指定次数的数据变化，那么就会进行RDB持久化
save 900 1      # 900秒内有 1 次修改，就进行RDB持久化
save 300 10     # 300秒内有 10 次修改，就进行RDB持久化
save 60 10000   # 60秒内有 10000 次修改，就进行RDB持久化
```

同时，我们也可以通过执行`save` (同步执行，会阻塞请求) 和`bgsave` (另起子进程执行，可以同时接受其他命令执行) 手动触发数据快照的创建



**AOF的主要配置为**

```
appendonly yes  # 是否开启aof,默认关闭
appendfilename "appendonly.aof"   # 持久化存储的文件名

## 触发AOF重写配置（需要同时满足）
auto-aof-rewrite-percentage 100  # 代表当前AOF文件的大小和上一次重写后的文件大小的比值
auto-aof-rewrite-min-size 64mb   # 表示触发AOF重写是的文件最小体积

## 同步文件配置（选择其中一个）
# appendfsync always    # 命令写入aop后，让操作系统同步文件到硬盘中
appendfsync everysec    # 命令写入aop后，每秒种 让操作系统同步文件到硬盘中（默认）
# appendfsync no        # 命令写入aop后，让操作系统自行决定何时同步文件到硬盘中

```

对于AOF，有个重写的概念，因为它保存的是所有指定的修改数据指令，其中有许多是可以精简的，举个例子，比如有如下命令

```
set k1 v1
del k1
```

我们看一眼就知道最终redis中是没有k1这个数据的，但是aof却要存储这两个指令，其实完全可以将这两个命令删除掉，当然还有很多其他情况下，也是可以对命令进行精简的

我们可以通过配置`auto-aof-rewrite-percentage`和`auto-aof-rewrite-min-size`来控制重新的触发条件，或者可以手动执行`bgrewriteaof`来触发AOF重写

重写时，会根据现有的数据，重新生成新的AOF文件，之后将在重写过程中产出的命令追加到AOF文件中，最后替换老的文件



其中还有一个同步文件配置，是因为调用操作系统写入时，并不一定会实时写入硬盘，而是写入到一个内存缓冲区，之后由操作系统不定时写入到硬盘。这本来是操作系统提升写入速度的机制，但是对于Redis来说却有可能导致数据的丢失，所以可以通过配置`appendfsync`控制刷到硬盘的频率，但这也需要平衡，每次都刷到硬盘会导致性能的下降，一般默认每秒一次即可



RDB和AOF配置及状态也可以通过执行`info persistence`查看



## 重启恢复

在Redis重新启动时，因为aof数据相比rdb会更新一些，所以如果开启了AOF，并且aof文件存在，那么使用aof文件进行数据恢复，服务端日志打印

`* DB loaded from append only file: 0.000 seconds`



如果AOF关闭，rdb文件存在则加载rdb文件恢复数据，服务端打印如下日志

`* DB loaded from disk: 0.000 seconds`





## 文件结构

对于持久化的文件结构，我们可以简单看下

### RDB文件

先来看下RDB的 dump.rdb 文件，RDB的文件格式有许多版本，最新的 redis5.0 使用的是 *版本9*，具体版本可以参考[RDB_Version_History](https://github.com/sripathikrishnan/redis-rdb-tools/blob/master/docs/RDB_Version_History.textile)，而关于 RDB文件结构的文档，目前只找到了关于 [版本7](https://github.com/sripathikrishnan/redis-rdb-tools/wiki/Redis-RDB-Dump-File-Format) 的，最新的版本并没有找到对应的文档资料

我们就找个简单的例子来看一下，具体的大家可以参考上面的资料

我本地安装的redis版本是5.0的，就先看下对应的RDB文件吧，先`flushall`清空数据后，执行`set kk vv`，使用16进制的格式打开rdb文件，内容如下

```
00000000: 5245 4449 5330 3030 39fa 0972 6564 6973  REDIS0009..redis
00000010: 2d76 6572 0535 2e30 2e33 fa0a 7265 6469  -ver.5.0.3..redi
00000020: 732d 6269 7473 c040 fa05 6374 696d 65c2  s-bits.@..ctime.
00000030: 22e4 6c5e fa08 7573 6564 2d6d 656d c2f0  ".l^..used-mem..
00000040: 0710 00fa 0c61 6f66 2d70 7265 616d 626c  .....aof-preambl
00000050: 65c0 00fe 00fb 0100 0002 6b6b 0276 76ff  e.........kk.vv.
00000060: 3545 3136 adb7 3b22                      5E16..;"
```

这里我们就结合源码来看一下，对应源码部分为（为了简单，已删除大部分内容）

```C
int rdbSaveRio(rio *rdb, int *error, int flags, rdbSaveInfo *rsi) {

    snprintf(magic,sizeof(magic),"REDIS%04d",RDB_VERSION);
    // 1. 首先是写入魔术 REDIS 后面再加 4位的版本号
    if (rdbWriteRaw(rdb,magic,9) == -1) goto werr;
    // 2. 写入Aux部分（不知道作用...）
    if (rdbSaveInfoAuxFields(rdb,flags,rsi) == -1) goto werr;

    for (j = 0; j < server.dbnum; j++) {
        redisDb *db = server.db+j;
        dict *d = db->dict;
        if (dictSize(d) == 0) continue;
        di = dictGetSafeIterator(d);

        // 3. 写入选择DB操作类型
        if (rdbSaveType(rdb,RDB_OPCODE_SELECTDB) == -1) goto werr;
        // 4. 写入具体DB的数值
        if (rdbSaveLen(rdb,j) == -1) goto werr;

        uint64_t db_size, expires_size;
        db_size = dictSize(db->dict);
        expires_size = dictSize(db->expires);
        // 5. 写入 RESIZEDB 操作类型
        if (rdbSaveType(rdb,RDB_OPCODE_RESIZEDB) == -1) goto werr;
        // 6. 写入db中key数量
        if (rdbSaveLen(rdb,db_size) == -1) goto werr;
        // 7. 写入db中有过期时间的key数量
        if (rdbSaveLen(rdb,expires_size) == -1) goto werr;

        // 其余部分省略
    }

}
```

各个操作码对应的值为：

```
/* Special RDB opcodes (saved/loaded with rdbSaveType/rdbLoadType). */
#define RDB_OPCODE_MODULE_AUX 247   /* Module auxiliary data. */
#define RDB_OPCODE_IDLE       248   /* LRU idle time. */
#define RDB_OPCODE_FREQ       249   /* LFU frequency. */
#define RDB_OPCODE_AUX        250   /* RDB aux field. */
#define RDB_OPCODE_RESIZEDB   251   /* Hash table resize hint. */
#define RDB_OPCODE_EXPIRETIME_MS 252    /* Expire time in milliseconds. */
#define RDB_OPCODE_EXPIRETIME 253       /* Old expire time in seconds. */
#define RDB_OPCODE_SELECTDB   254   /* DB number of the following keys. */
#define RDB_OPCODE_EOF        255   /* End of the RDB file. */
```

这里我们就可以和前面的文件内容进行对照了，最开始部分为 REDIS0009 为魔术 REDIS及版本9，后面的为aux域，这里我们先跳过，直接到我们关心的数据相关部分，内容为

所以现在直接跳过这部分内容，到数据部分，内容为

```
二进制：  fe  00fb 0100 0002 6b6b 0276 76ff 3545 3136 adb7 3b22
对应值：                   2 k k   2 v  v
```

一个一个顺序看下

`FE 00`  FE对应的10进制是254，即RDB_OPCODE_SELECTDB, 结合后面的00就表示 select 0

`FB 01 00`这个对应的是 RDB_OPCODE_RESIZEDB 表示 DB中的key数量为1个，有过期时间的key为0个

`0002 6B6B 0276 76`中，最开始的 00 通过`0 = “String Encoding”`可以得知表示值类型为string，后面的 02 表示的是长度为2，之后的两个字节 6B6B 表示的是我们之前设置的键: kk，再之后的 02 表示的也是长度为2， 对应的 7676 表示的是设置的值：vv

紧接后面的 FF 对应的是RDB_OPCODE_EOF，标识RDB文件结束了

最后的都是`3545 3136 adb7 3b22` 为8为校验码



### AOF

最后看下AOF的文件格式，这次我们不用16进制打开，而是使用文本编辑器直接打开，内容如下

```
➜  cat appendonly.aof
REDIS0009�	redis-ver5.0.3�
redis-bits�@�ctime�m
                    m^used-mem�
                               aof-preamble���kkvv��/�X�*2
$6
SELECT
$1
0
*3
$3
set
$2
kk
$2
vv
```

其实可以很明显的看到，前面的一段和RDB格式基本相同，而后面的其实就是我们执行的命令对应的RESP协议内容，这里就不再过多介绍了，不太了解的可以参考文档[Redis Protocol specification](https://redis.io/topics/protocol)， 或者我之前写的[Redis服务端-客户端通信协议](https://zhengw-tech.com/2019/06/08/redis-resp/)



内容到这里就介绍完了，如有错误，欢迎指正


