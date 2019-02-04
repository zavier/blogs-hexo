---
title: JavaScript数组常用方法
date: 2019-02-04 11:51:54
tags: javascript
---

- push 方法

将元素添加到数组尾部

```javascript
var values = [1,2,3,4,5]
values.push(6,7) // values = [1,2,3,4,5,6,7]
```


- pop 方法

将数组尾部元素弹出

```javascript
var values = [1,2,3,4,5]
values.pop() // values = [1,2,3,4]
```


- shift 方法

弹出数组头元素

```javascript
var values = [1,2,3]
values.shift() // values = [2,3]
```

<!-- more -->

- unshift 方法

将元素添加到数组头部

```javascript
var values = [1,2,3]
values.unshift(-1, -2) // values = [-1, -2, 1, 2, 3]
```


- reverse 方法

反转数组

```javascript
var values = [1, 4, 5, 2]
values.reverse() // values = [2, 5, 4, 1]
```


- sort 方法

对数组进行排序

```javascript
var values = [1, 4, 5, 2]
values.sort() // values = [1, 2, 4, 5]
values.sort(function(a, b) {
    return a - b;
}) // values = [5, 4, 3, 2, 1]
```


- concat 方法

连接两个数组，生成一个新数组

```javascript
var values1 = [1, 2, 3]
var values2 = ["A", "B"]
var res = values1.concat(values2) // res = [1, 2, 3, "A", "B"]
```


- slice 方法

剪切数组，索引可为负数

```javascript
var values = ["aa", "bb", "cc", "dd"]
var res1 = values.slice(1) // res1 = ["bb", "cc", "dd"]
var res2 = values.slice(1, 3) // res2 = ["bb", "cc"]
var res3 = values.slice(-1) // res3 = ["dd"]
```


- splice 方法

删除、插入、替换数组元素

```javascript
// 删除 splice(开始删除的索引，删除的数量)
var colors = ["red", "green", "blue"]
var removed = colors.splice(0, 2)
// colors = ["blue"]
// removed = ["red", "green"]

// 插入/替换 splice(开始位置，删除的数量[可为0，此时为插入]，插入的元素)
var colors = ["red", "green", "blue"]
var removed = colors.splice(1, 1, "yellow", "orange")
// colors = ["red", "yellow", "orange", "blue"]
// removed = ["green"]    删除的元素
```


- indexOf / lastIndexOf

查找元素索引位置

```javascript
// indexOf(要查找的元素, [其实查找位置])
var colors = [1, 2, 3, 4, 1]
colors.indexOf(1) // = 0
colors.indexOf(1, 1) // = 4
colors.indexOf(10) // = -1
```



### 迭代方法

- every() : 对数组中的每一项运行给定的函数，如果都返回true, 则返回true
- filter() : 对数组中的每一项运行给定函数，返回该函数会返回true的项组成的数组
- forEach() : 对数组中的每一项运行给定函数，这个方法无返回值
- map() : 对数组中的每一项运行给定的函数，返回每次函数调用的结果组成的函数
- some() : 对数组中的每一项运行给定的函数，如果该函数对任一项返回true，则返回true

传入这些方法的函数会接收三个参数：数组项的值，该项在数组中的位置，数组对象本身

```javascript
var numbers = [1, 2, 3, 4, 5, 4, 3, 2 ,1];
var everyResult = numbers.every(function(item, index, array) {
    return item > 2;
}); // everyResult = false

var someResult = numbers.some(function(item, index, array) {
    return item > 2;
}); // someResult = true

var filterResult = numbers.filter(function(item, index, array) {
    return item > 2;
}); // filterResult = [3, 4, 5, 4, 3]

var mapResult = numbers.map(function(item, index, array) {
    return item * 2;
}); // mapResult = [2, 4, 6, 8, 10, 8, 6, 4, 2]

numbers.forEach(function(item, index, array) {
    // 执行一些操作
})
```



- reduce/ reduceRight 方法

传入此方法的函数接收4个参数：前一个值，当前值，项的索引，数组对象

```javascript
var values = [1, 2, 3, 4, 5]
var sum = values.reduce(function(prev, cur, index, array) {
    return prev + cur;
}); // sum = 15
```

