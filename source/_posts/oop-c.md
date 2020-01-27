---
title: C语言实现的封装，继承，多态
date: 2020-01-27 13:22:36
tags: c
---

提到面向对象编程，我们想到的就是封装、继承、多态，但是其实这几个特性并不是面向对象编程所独有的，C语言也是基本支持这三个特性的，下面我们来具体看下

## 封装

```c
// point.h
struct Point;
struct Point* makePoint(double x, double y);
double distance(struct Point *p1, struct Point *p2);
```

```c
// point.c
#include "point.h"
#include <stdlib.h>
#include <math.h>

struct Point {
  double x, y;
};

struct Point* makePoint(double x, double y) {
  struct Point* p = malloc(sizeof (struct Point));
  p->x = x;
  p->y = y;
  return p;
}

double distance(struct Point* p1, struct Point* p2) {
  double dx = p1->x - p2->x;
  double dy = p1->y - p2->y;
  return sqrt(dx*dx + dy*dy);
}
```

<!-- more -->

这样使用`point.h` 的程序就不知道 Point 的内部结构，实现了数据的封装，外部只能使用声明的两个函数，如：

```c
// 使用 demo
#include <stdio.h>
#include "point.h"

int main() {
  struct Point* p1 = makePoint(5, 6);
  struct Point* p2 = makePoint(6, 7);
  printf("%lf",distance(p1, p2));
}
```



## 继承

接着上面的代码

```c
#include <stdio.h>
#include <stdlib.h>
#include "point.h"

struct NamedPoint {
  double x, y;
  char* name;
};

struct NamedPoint* makeNamedPoint(double x, double y, char* name) {
  struct NamedPoint* p = malloc(sizeof(struct NamedPoint));
  p->x = x;
  p->y = y;
  p->name = name;
  return p;
}
    

  
int main() {
  struct NamedPoint* p1 = makeNamedPoint(0, 0, "origin");
  struct NamedPoint* p2 = makeNamedPoint(3, 4, "new");
  // 本来接受的参数只能是 Point类型的指针，这里是把 NamedPoint的指针进行强转
  printf("%lf",distance((struct Point*)p1, (struct Point*)p2));
}
```

这是能够进行强转调用，是因为 NamedPoint 结构体的前两个成员的顺序与 Point 结构体的完全一致，所以可以进行强转，这其实就可以算是一个单继承



## 多态

最后我们来看一下多态，这个C语言也是可以实现的，通过使用函数指针

先看一个简单的例子

```c
#include <stdio.h>
#include <stdlib.h>

// 定义函数指针
typedef int (*myFunc)(int, int);

// 定义函数1
int add(int n, int m) {
  return n + m;
}

// 定义函数2
int substract(int n, int m) {
  return n - m;
}

int main() {
  // 为函数指针使用不同的函数实现进行调用
  myFunc f  = &add;
  printf("%d\n", f(1, 2));

  f = &substract;
  printf("%d\n", f(1, 2));
}

```



上面的例子如果大家感受还不太明显的话，接下来看一个 redis 源码中的使用

````c
// dict.h
typedef struct dictType {
    uint64_t (*hashFunction)(const void *key);
    void *(*keyDup)(void *privdata, const void *key);
    void *(*valDup)(void *privdata, const void *obj);
    int (*keyCompare)(void *privdata, const void *key1, const void *key2);
    void (*keyDestructor)(void *privdata, void *key);
    void (*valDestructor)(void *privdata, void *obj);
} dictType;
````

上面这个结构中都是函数指针，可以类比为 Java 中的接口及对应函数声明



```c
// uint64_t (*hashFunction)(const void *key) 实现函数
uint64_t dictSdsHash(const void *key) {
    return dictGenHashFunction((unsigned char*)key, sdslen((char*)key));
}

// int (*keyCompare)(void *privdata, const void *key1, const void *key2) 实现函数
int dictSdsKeyCompare(void *privdata, const void *key1, const void *key2) {
    int l1,l2;
    DICT_NOTUSED(privdata);

    l1 = sdslen((sds)key1);
    l2 = sdslen((sds)key2);
    if (l1 != l2) return 0;
    return memcmp(key1, key2, l1) == 0;
}

// ================= 具体的类型实现 =================
/* Set dictionary type. Keys are SDS strings, values are ot used. */
dictType setDictType = {
    dictSdsHash,               /* hash function */
    NULL,                      /* key dup */
    NULL,                      /* val dup */
    dictSdsKeyCompare,         /* key compare */
    dictSdsDestructor,         /* key destructor */
    NULL                       /* val destructor */
};

/* Sorted sets hash (note: a skiplist is used in addition to the hash table) */
dictType zsetDictType = {
    dictSdsHash,               /* hash function */
    NULL,                      /* key dup */
    NULL,                      /* val dup */
    dictSdsKeyCompare,         /* key compare */
    NULL,                      /* Note: SDS string shared & freed by skiplist */
    NULL                       /* val destructor */
};

/* Db->dict, keys are sds strings, vals are Redis objects. */
dictType dbDictType = {
    dictSdsHash,                /* hash function */
    NULL,                       /* key dup */
    NULL,                       /* val dup */
    dictSdsKeyCompare,          /* key compare */
    dictSdsDestructor,          /* key destructor */
    dictObjectDestructor   /* val destructor */
};
```

这几个类型都可以类比看做上面的接口的具体实现类，每个类有自己对应的函数实现



所以不是使用了面向对象的语言，写出的代码就是面向对象的，而使用了面向过程的语言写出来的代码就不行，只不过面向对象的语言对面向对象提供了更好的支持，写起来更方便，更安全而已。代码质量的好坏不是仅仅靠使用了什么高级语言就可以的，要想提升代码质量还是需要我们去不断思考和实践的