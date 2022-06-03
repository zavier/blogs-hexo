---
title: kotlin笔记
date: 2022-03-19 14:14:59
tags: [kotlin]
---



Kotlin可以认为是一种更好的Java，所以主要就来对比一下Kotlin中的一些不同的有意思的地方

这里根据kotlin教程中的[Kotlin Koans](https://kotlinlang.org/docs/koans.html) 例子整理而来



## 默认参数及命名参数

Java中如果同一个功能需要不同的参数的时候，一般是通过对方法的重载来实现

kotlin中的默认参数及命名参数也可以用来处理相关的逻辑

```kotlin
// separator 不传时，默认值为 ","
fun joinToString(coll: Collection<String>, separator: String = ","): String {
    val buffer = StringBuilder()
    var count = 0
    for (str in coll) {
        if (++count > 1) buffer.append(separator)
        buffer.append(str)
    }
    return buffer.toString()
}

// 使用
val list = listOf("AA", "BB", "CC")
println(join(list))
println(join(list, separator = "|"))
println(join(list, "|"))
```





## Data Classes

Java中的POJO类的定义，一般就是一些属性，然后需要生成一堆的getter, setter等方法，代码很长作用又很小，

而在kotlin中为此提供了专门的数据类，只需要一行代码即可，会自动生成getter，setter及equals等方法

```kotlin
data class User(val name: String, val age: Int)
```


