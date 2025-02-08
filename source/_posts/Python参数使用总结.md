---
title: Python参数使用总结
date: 2019-01-04 13:14:16
tags: python
---
Python 中参数的传递非常灵活，不太容易记住理解，特整理如下备忘：

### 普通参数

即按照函数所需的参数，对应位置传递对应的值，可以对应 Java 中的普通参数

```python
def max(a, b):
  if a > b:
    return a
  else:
    return b
 
max(5, 13) # = 13
```

<!-- more -->


### 默认参数

可以对位置参数中的某个参数设置默认值，设置了默认值的参数在调用时**可以**不传递

此时需要注意，**默认参数只能在必选参数后面**

```python
def max(a, b=0):
  if a > b:
    return a
  else:
    return b
  
max(5, 13) # = 13
max(5) # = 5
max(-6) # = 0
```

当有多个默认参数时，调用参数传递的值会按照顺序赋值，也可以通过指定参数值为特定参数赋值

```python
def position(x, y=1, z=0):
  print('x:', x, 'y:', y, 'z:', z)
  
position(5) # x=5, y=1, z=0
position(5, 6) # x=5, y=6, z=0
position(5, z=6) # x=5, y=1, z=6
```

### 可变参数

即传递的参数个数不确定，可以对应为 Java 中的可变参数，类似传递了一个 list 或 tuple

**可变参数只能出现在必选参数和默认参数后面**

```python
def max(*numbers):
  # 此处可以有更简单的写法
  sum = 0
  for number in numbers:
    sum += number
  return sum

print(max(1,2,3,4,5)) # = 15
# 对于 list 或 tuple, 如 nums = [1,2,3,4,5], 可以这样使用
nums = [1,2,3,4,5]
print(max(*nums)) # = 15
```



### 命名关键字参数

命名关键字有些像普通参数和默认参数的结合，在一个 * 后面的参数为命名关键字参数

和普通参数、默认参数的区别就是需要在传递参数时指定赋值给的参数名字

命名关键字参数只能出现在必选参数、默认参数、可变参数后面

```python
# 其中 age, sex的赋值必须指定变量名称
def person1(name, *, age, sex):
  print('name:', name, 'age:', age, 'sex:', sex)
 
# age和sex可以不赋值，但是如果赋值必须指定变量名称    
def person1=2(name, *, age=15, sex='F'):
  print('name:', name, 'age:', age, 'sex:', sex)
  
person1('zhang', age=15, sex='F') # 如果命名关键字参数没有设置默认值，则必须显示给每个参数赋值
person2('zhang') # 函数中已经对参数设置默认值
```

如果命名关键字参数前面有可变参数，则可省略 * 号

```python
# age 和 sex 均是命名关键字参数
def person(name, *args, age, sex):
  pass
```



### 关键字参数

**关键字参数必须出现在必选参数、默认参数、可变参数、命名关键字参数后面**

在可变参数的基础上，即不仅仅可以传递任意个参数，同时还可以对传递的各个参数**指定参数名**，可以理解为传递了一个 dict

```python
def person(name, **kw):
  print('name:', name)
  for k, v in kw.items():
    print(k, v)
  
person('zhang', age=15, sex='M') 
# name: zhang
# age 15
# sex M

# 对于 dict, 如 p={'age': 15, 'sex':'M'}, 可以这样使用
p={'age': 15, 'sex':'M'}
person('zhang', **p)
# name: zhang
# age 15
# sex M
```





### 总结一下

- 普通参数——必选参数
- 默认参数——参数有默认值，调用函数时可以传递也可以不传递，如果不传递则使用默认值
- 可变参数——传递数量不确定 (可以为0个) 的参数，类似传递一个 list
- 命名关键字参数 ——如果设置默认值，则同可选参数，否则必须传递，且传递时指定值对应的参数名
- 关键字参数——传递数量不确定 (可以为0) 的 键值对，类似传递一个 dict
