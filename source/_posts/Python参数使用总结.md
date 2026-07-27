---
title: Python参数使用总结
date: 2019-01-04 13:14:16
tags: python
---
Python 中参数的传递非常灵活，不太容易记住理解，特整理如下备忘。

## 位置参数（普通参数）

即按照函数所需的参数，按位置传递对应的值。这是最基础的参数形式——函数有固定数量的必需输入，调用时按定义顺序一一对应。

```python
def find_max(a, b):
    if a > b:
        return a
    else:
        return b

find_max(5, 13)  # 输出: 13
```

<!-- more -->

## 默认参数

某个参数在大多数调用中都取同一个值，每次都传一遍很啰嗦。给它一个默认值，调用时**可以**省略。

此时需要注意，**默认参数只能在必选参数后面**。

```python
def find_max(a, b=0):
    if a > b:
        return a
    else:
        return b

find_max(5, 13)  # 输出: 13
find_max(5)      # 输出: 5
find_max(-6)     # 输出: 0
```

当有多个默认参数时，调用时未指定参数名的值按位置顺序赋值，也可以通过 `参数名=值` 为特定参数赋值

```python
def position(x, y=1, z=0):
    print('x:', x, 'y:', y, 'z:', z)

position(5)         # x=5, y=1, z=0
position(5, 6)      # x=5, y=6, z=0
position(5, z=6)    # x=5, y=1, z=6
```

**常见陷阱：可变对象作为默认值**

默认参数的值只在函数定义时计算一次，而不是每次调用时重新计算。如果默认值是可变对象（如 list、dict），多次调用会共享同一个对象，导致意料之外的行为：

```python
# 错误写法
def add_item(item, lst=[]):
    lst.append(item)
    return lst

print(add_item(1))  # 输出: [1]
print(add_item(2))  # 输出: [1, 2] — 期望 [2]，但默认列表被共享了！
print(add_item(3))  # 输出: [1, 2, 3]

# 正确写法
def add_item(item, lst=None):
    if lst is None:
        lst = []
    lst.append(item)
    return lst

print(add_item(1))  # 输出: [1]
print(add_item(2))  # 输出: [2] — 每次调用重新创建列表
```

> **原则**：默认值尽量使用不可变类型（`None`、数字、字符串、元组），避免使用 `[]`、`{}` 等可变对象。

## 可变参数

有些函数天生不知道会收到多少个参数——`print()` 就是一个，你可以传 0 个、1 个、10 个。可变参数 `*args` 用来兜底这些多出来的位置参数：在函数内部，它是一个 `tuple`（元组），包含了所有传入的额外位置参数。

**可变参数只能出现在必选参数和默认参数后面**。适用于参数数量不固定的场景，如数学求和、日志函数、装饰器等。

```python
def sum_all(*numbers):
    # 等价于 return sum(numbers)，这里展开为手动迭代以便理解
    total = 0
    for number in numbers:
        total += number
    return total

print(sum_all(1, 2, 3, 4, 5))  # 输出: 15
# 对于 list 或 tuple，如 nums = [1, 2, 3, 4, 5]，可以这样使用
nums = [1, 2, 3, 4, 5]
print(sum_all(*nums))  # 输出: 15
```

## 命名关键字参数

命名关键字参数（keyword-only arguments）只能通过 `参数名=值` 的方式传递，不能按位置传参。在函数签名中，单独的 `*` 之后的参数即为命名关键字参数——`*` 本身不接收任何值，只起到分隔"可按位置传递"和"必须指定参数名"两部分的作用。

> **与关键字参数（`**kwargs`）的区别**：关键字参数是"来者不拒"——所有未匹配的具名参数被收集到一个 `dict` 中，参数名是动态的。命名关键字参数则是在函数签名中**预先声明的具体参数名**，调用者必须（或可以，视默认值）提供，但必须带名字。前者用于透传不确定的配置项，后者用于强制调用者明确意图。

命名关键字参数只能出现在必选参数、默认参数、可变参数后面。适用于需要强制调用者明确意图的参数，如 `connect(host, port, *, timeout)` 中，`timeout` 必须显式写成 `timeout=30`，避免调用者写成 `connect('localhost', 8080, 30)` 而含义不清。

```python
# person1: 命名关键字参数无默认值，调用时必须显式传参
def person1(name, *, age, sex):
    print('name:', name, 'age:', age, 'sex:', sex)

person1('zhang', age=15, sex='F')  # 必须指定 age=, sex=


# person2: 命名关键字参数有默认值，调用时可以省略
def person2(name, *, age=15, sex='F'):
    print('name:', name, 'age:', age, 'sex:', sex)

person2('zhang')                     # 使用默认值
person2('zhang', age=20)             # 覆盖部分默认值
```

如果命名关键字参数前面有可变参数，则可省略 `*` 号

```python
# age 和 sex 均是命名关键字参数
def person(name, *args, age, sex):
    pass
```

## 关键字参数

有时候参数名没法提前穷举——比如 HTTP 请求库要透传 headers、timeout、auth 等各种可选配置，谁知道调用方会传什么。关键字参数 `**kwargs` 就是干这个的：把多余的具名参数全收进一个 `dict`（字典）。

**关键字参数必须出现在必选参数、默认参数、可变参数、命名关键字参数后面。**

> 与命名关键字参数的区别见上一节。简单说：命名关键字参数是"我声明了 `age`，你必须传 `age=`"，关键字参数是"你传的任何 `key=value`，我都收进 dict"。

```python
def person(name, **kw):
    print('name:', name)
    for k, v in kw.items():
        print(k, v)

person('zhang', age=15, sex='M')
# 输出:
# name: zhang
# age 15
# sex M

# 对于 dict，如 p = {'age': 15, 'sex': 'M'}，可以这样使用
p = {'age': 15, 'sex': 'M'}
person('zhang', **p)
# 输出:
# name: zhang
# age 15
# sex M
```

## 总结一下

**参数定义时的完整顺序规则**（从前到后）：

```
必选参数 → 默认参数 → 可变参数(*args) → 命名关键字参数 → 关键字参数(**kwargs)
```

**综合示例**：将所有参数类型串在一起：

```python
def func(a, b=1, *args, c, d=2, **kwargs):
    print('a:', a)             # 必选
    print('b:', b)             # 默认
    print('args:', args)       # 可变 (tuple)
    print('c:', c)             # 命名关键字（必传）
    print('d:', d)             # 命名关键字（有默认值）
    print('kwargs:', kwargs)   # 关键字 (dict)

# 调用示例
func(1, 2, 3, 4, c=5, x=6, y=7)
# a: 1
# b: 2
# args: (3, 4)
# c: 5
# d: 2
# kwargs: {'x': 6, 'y': 7}
```

**五种参数对比**：

| 参数类型 | 是否必传 | 传参方式 | 函数内部类型 |
|---|---|---|---|
| 位置参数 | 是 | 按位置 | 对应类型 |
| 默认参数 | 否（有默认值） | 按位置或参数名 | 对应类型 |
| 可变参数 `*args` | 否（可为 0 个） | 按位置（剩余） | `tuple` |
| 命名关键字参数 | 取决于是否有默认值 | **必须**指定参数名 | 对应类型 |
| 关键字参数 `**kwargs` | 否（可为 0 个） | 指定参数名（剩余） | `dict` |
