---
title: Redis数据结构概览
date: 2019-02-07 16:54:28
tags: redis
---

Redis支持的主要有5种数据类型，`string`, `list`,  `set`,  `zset`  , `hash`，但是对于每种数据类型，Redis都不是简单的使用一种数据结构来实现，而是根据数据量等因素使用多种数据结构（SDS、双向链表、hashtable等），来达到提高效率、节省空间的目的，可以使用`object encoding <key>` 来查看数据的内部结构

<!-- more -->

![](/images/redis-datastruct.jpg)

（注：对于Redis的早期版本，list 结构内部是使用双向链表实现的）

