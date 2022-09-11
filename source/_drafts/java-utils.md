---
title: Java常用工具类
date: 2022-08-28 11:48:28
tags: [java]
---

对于日常开发中的很多相对基础且使用频率较高的功能，这时候就可以通过使用或实现自己的工具类来避免这类重复代码，同时使用成熟的工具类开箱即用还可以极大的提升我们的开发效率，下面简单罗列了一些比较常用的功能，有一些是java本身提供的，对于一些java没有提供的，还有一些三方包提供的功能，如apache的commons系列以及google的guava（本例中的java版本为1.8）

<!-- more -->

## 对象操作

java提供

```java
// 比较对象是否相同, 防止自己使用equals需要判断空指针的问题
Objects.equals(Object, Object);
```

commons-lang3提供

```java
// 判断对象是否为空（支持判断是否为null, 是否为空字符串，是否为空集合，是否为空map）
ObjectUtils.isEmpty(Object);
ObjectUtils.isNotEmpty(Object);
// 获取一个对象的值，在对象为null时可以提供一个值
ObjectUtils.getIfNull(T object, Supplier<T> defaultSupplier);
```

## 字符串操作

commons-lang3提供

```java
// 判断字符串是否为空，全是空格的字符串也是空
StringUtils.isBlank(CharSequence);
StringUtils.isNotBlank(CharSequence);
// 字符串压缩，如过长时使用 ... 来进行展示，其他相关重载函数可以参考文档
StringUtils.abbreviate(String, int);
// 首字母转成大写
StringUtils.capitalize(String);
// 获取字符串，如果为空时使用默认值
StringUtils.defaultIfBlank(String, String)
```

commons-text提供

```java
// java字符串转移
StringEscapeUtils.escapeJava(String);
StringEscapeUtils.unescapeJava(String);
// html字符串转义
StringEscapeUtils.escapeHtml4(String);
StringEscapeUtils.unescapeHtml4(String);
```

## 数组操作

java提供

```java
// 数组转集合(注意返回的集合是不能进行添加元素等操作的)
Arrays.asList(T... a)
```

## 集合操作

jdk提供

```java
// 反转集合
Collections.reverse(List<?> list);
// 对集合元素进行排序(会改变集合中元素位置)，可以提供自己的比较函数
Collections.sort(List<?> list);
// 获取集合中的最大/最小元素，可以提供自己的比较函数
Collections.max(List<?> list);
Collections.min(List<?> list);
```

commons-collections4提供

```java
// 判断集合为空/不为空（会处理为null的情况）
CollectionUtils.isEmpty(Collection<?> coll);
CollectionUtils.isNotEmpty(Collection<?> coll);
// 获取集合元素数据(集合为null时返回0)
CollectionUtils.size(final Object object)
// 获取两个集合的并集
CollectionUtils.union(Iterable<? extends O> a, Iterable<? extends O> b);
// 获取两个集合的交集
CollectionUtils.intersection(Iterable<? extends O> a, Iterable<? extends O> b);
// 返回从集合a中去除集合b中存在的元素（不会修改集合本身，a或b）
CollectionUtils.subtract(Iterable<? extends O> a, Iterable<? extends O> b);
// 返回从集合中去除要删除的集合中的元素后的集合（不会修改collection集合本身）
CollectionUtils.removeAll(Collection<E> collection, Collection<?> remove);
// 返回集合中在retain中存在的元素集合（不会修改collection集合本身）
CollectionUtils.retainAll(Collection<E> collection, Collection<?> retain);
```

guava提供

```java
// 字符串转集合(例子：Splitter.on(",").omitEmptyStrings().trimResults().splitToList(String)
Splitter.splitToList(String);
// 集合转字符串(例子：Joiner.on(",").skipNulls().join(Object[] parts))
Joiner.join(Object[] parts);
```

## IO操作

commons-io提供

```java
// 读取文件内容为一个字符串
FileUtils.readFileToString(File);
// 读取文件每一行内容，转换为一个字符串集合
FileUtils.readLines(File);
// 将字符串写入文件
FileUtils.writeStringToFile(File, String);
// 文件复制(将文件复制到另一个地方，目标文件不存在则创建，存在则覆盖)
FileUtil.copyFile(File, File);
// 删除文件
FileUtils.forceDelete(File);
```



这里只是抛砖引玉，以上所提供的内容只是九牛一毛，大家可以看下相关包中的提供的api来查看更多的内容

在写代码时，如果感觉这个功能比较常用，或者其他人可能会遇到的时候，就可以查看下是否有相关的工具类

上述很多的三方包中提供的工具类，很多都是对当前语言中的内容进行的扩展，有的随着语言本身的迭代，本身已经提供了相关的功能

当语言本身或者其他工具类帮助我们封装了越来越多的底层细节实现时，我们就可以更加专注于自己本身的业务逻辑，避免一些问题的同时也能提升开发效率

当有一天我们不再满足于某一种语言时，就可以看看对于同一个功能其他语言（比如kotlin，哈哈～）的写法是否是更简洁一些，毕竟语言的表达能力越强，需要写的代码越少，同时写的越少犯错的可能性也越小，同时阅读和维护起来成本也更低，更容易些



附：以上内容使用的包的maven坐标如下

```xml
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-lang3</artifactId>
    <version>3.12.0</version>
</dependency>
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-collections4</artifactId>
    <version>4.4</version>
</dependency>
<dependency>
    <groupId>com.google.guava</groupId>
    <artifactId>guava</artifactId>
    <version>31.1-jre</version>
</dependency>
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-io</artifactId>
    <version>1.3.2</version>
</dependency>
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-text</artifactId>
    <version>1.9</version>
</dependency>
```

