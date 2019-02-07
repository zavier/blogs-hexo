---
title: Redis数据结构-SDS
date: 2019-01-26 12:27:31
tags: redis
---

## 基本结构

Redis中没有使用C语言原生的字符串，而是在其基础上包装了一个新的数据结构-SDS，其结构如下

```c
// 指向下面结构中的buf指针
typedef char *sds;

struct __attribute__ ((__packed__)) sdshdr8 {
	uint8_t len; // 使用到的空间
	uint8_t alloc; // 分配的C语言字符串空间，不包括头部和C字符串的中止符号null
    unsigned char flags; // 使用后三位表示是sdshdr8/sdshdr16的类型
    char buf[]; // 实际字符数组的空间
}
// 类似的还有 sdshdr16, sdshdr32等，用于节省空间
// 其中的所有方法都在此结构基础上实现
```

<!-- more -->

## 主要方法及实现

`sdslen(sds s) - 获取sds中已经使用的数组空间大小`

根据flags判断类型，将指向buf的指针前移到结构开始，转换为结构类型，获取len属性返回

源码如下

```c
// 由于s是指向sdshdr结构中buf数组，所有需要减去len,alloc,flags所占用的空间，到达结构在内存中的开始位置，进行类型转换
#define SDS_HDR(T,s) ((struct sdshdr##T *)((s)-(sizeof(struct sdshdr##T))))

static inline size_t sdslen(const sds s) {
    unsigned char flags = s[-1];
    switch(flags&SDS_TYPE_MASK) {
        case SDS_TYPE_5:
            return SDS_TYPE_5_LEN(flags);
        case SDS_TYPE_8:
            return SDS_HDR(8,s)->len;
        case SDS_TYPE_16:
            return SDS_HDR(16,s)->len;
        case SDS_TYPE_32:
            return SDS_HDR(32,s)->len;
        case SDS_TYPE_64:
            return SDS_HDR(64,s)->len;
    }
    return 0;
}
```

`size_t sdsavail(sds s) - 获取可用空间大小 = alloc - len`

`void sdssetlen(sds s, size_t newlen) - 设置len属性值=newlen`  

`void sdsinclen(sds s, size_t inc) - 修改len属性值=len+inc`

`size_t sdsalloc(sds s) - 返回alloc属性值`

`void sdssetalloc(sds s, size_t newlen) - 设置alloc属性值=newlen`



`sds sdsnewlen(void *init, size_t initlen) - 通过传递指针和长度创建sds`

根据长度initlen判断选择的sdshdr类型，分配空间，初始化 len, alloc, type属性，返回指向buf的指针

`sds sdsempty(void) - 创建一个空的sds字符串`

`sds sdsnew(const char *init) - 创建一个包含init字符的sds `

`sds sdsup(const sds s) - 复制一个sds字符串`

`void sdsfree(sds s) - 释放sds字符串内存空间`

`void sdsupdatelen(sds s) - 更新sds长度（用于去除字符中的中间\0字符）`

`void sdsclear(sds s) - 长度设为0，清空字符串（s[0]='\0'）`

`sds sdsMakeRoomFor(sds s, size_t addlen)  - 重新为sds中数组分配长度，确保能再添加addlen个长度数组`

`sds sdsRemoveFreeSpace(sds s)  - 释放未使用的空间`

等等......

