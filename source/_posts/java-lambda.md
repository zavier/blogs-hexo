---
title: 浅谈java Lambda表达式及其使用
date: 2019-06-07 13:50:06
tags: java
---

## 什么是 lambda表达式？

对于 Java 中的 lambda 表达式，我们可以把它简单的理解为一个函数。

比如，我们需要这样一个函数，它需要把两个数字相加，将结果返回 则可以这样定义

```java
int add(int a, int b);
```

但是我们知道，Java中函数是没有办法单独定义存在的，所以我们需要一个接口才能声明这个函数功能

```java
interface Function {
    int add(int a, int b);
}
```

当我们需要实现这个方法的时候，一种方法就是定义一个新的类来实现这个接口

```java
class Calc implements Function {
    @Override
    public int add(int a, int b) {
        return a + b;
    }
}
```

<!-- more -->

除此之外，还有一种方法就是使用匿名类

```java
Function addFunc = new Function() {
    @Override
    public int add(int a, int b) {
        return a + b;
    }
};
```

而在 Java8 中，我们又有了一种更简单的写法，这也就是lambda表达式

```java
Function addFunc1 = (a, b) -> a + b;
```

当然，既然是为了表达一个函数所创建的接口，所以定义的接口中就必须只能有一个方法。对于这类接口，它还有一个特殊的名字: **函数式接口**，我们可以在对应的接口上面添加`@FunctionalInterface`注解来表明它的身份。

## 如何使用?

上一节我们可以知道，lambda就是函数式接口的实现，所以要想使用lambda表示式，我们必须先定义一个函数式接口，这样任何需要函数式接口的地方，我们都可以传递lambda表达式进去。我们也可以自己定义方法，接受lambda表达式参数

JDK中已经定义了很多常用的函数式接口，比如`Comparator`接口

```java
@FunctionalInterface
public interface Comparator<T> {
    int compare(T o1, T o2);
}
```

这样我们在排序的时候，接受 Comparator接口的地方就可以传递lambda表达式了，非常方便

```java
List<String> list = ...;
list.sort((s1, s2) -> s1.compareTo(s2));
```

基本常用的函数式接口，JDK已经都帮我们内置好了，不需要自己定义，大致有以下几类

### 常用函数式接口

#### Predicate 

谓词 - 用来对数据进行判断，返回true或false

```java
@FunctionalInterface
public interface Predicate<T> {
    boolean test(T t);
}
```

#### Function

用于转换数据，将前一个参数的类型转为后面的类型

```java
@FunctionalInterface
public interface Function<T, R> {
    R apply(T t);
}
```

#### Supplier

生产者，用来生产数据，无参数，返回一个对象

```java
@FunctionalInterface
public interface Supplier<T> {
    T get();
}
```

#### Consumer

消费者，就是用来消费数据，接受一个数据，无返回值

```java
@FunctionalInterface
public interface Consumer<T> {
    void accept(T t);
}
```

## Lambda表达式复合使用

函数式接口的功能都比较单一，有时候无法满足我们的需求，这时候就需要将多个lambda表达式组合到一起使用来完成功能

### 比较器复合

```java
// 对于用户类，有两个比较器
Comparator<User> ageComparator = (u1, u2) -> u1.getAge().compareTo(u2.getAge());
Comparator<User> nameComparator = (u1, u2) -> u1.getAge().compareTo(u2.getAge());

// 如果我们需要按照年龄倒序排序
Comparator<User> comparator = ageComparator.reversed();
// 年龄相等时，我们需要再根据姓名进行比较
comparator = ageComparator.thenComparing(nameComparator);
```

上面只是为了方便理解，实际比较时，可以使用 `Comparator.comparing()`方法

如按照年龄排序: `Comparator<User> newAgeComparator = Comparator.comparing(User::getAge);`

### 谓词复合

谓词接口有三个方法，`negate`, `and` ,`or`来分别表示 非、与、或

```java
// 获取年龄大于18岁的用户
Predicate<User> userPred1 = u -> u.getAge() > 18;
// 获取体重大于80的人
Predicate<User> userPred2 = u -> u.getWeight() > 80;

// 同时获取年龄大于18 且 体重大于80的人
Predicate<User> newPred = userPred1.and(userPred2);
// 获取年龄大于18 或者 体重大于80的人
Predicate<User> newPred2 = userPred1.or(userPred2);
```

**注意：如果`and`和`or`在一起使用，则会按照书写顺序来定优先级**

### 函数复合

`Function`接口提供了两个方法`andThen`和`compose`用来组合函数

andThen用在执行完当然函数，将结果用户参数中的下一个函数

而 compose顺序则相反，是执行完参数中的函数，将结果用于当前调用函数

```java
Function<Integer, Integer> f = x -> x + 1;
Function<Integer, Integer> g = x -> x * 2;

// 先执行 f 再执行 g
Function<Integer, Integer> h = f.andThen(g);
// == (10 + 1) * 2 = 22
System.out.println(h.apply(10));

// 先执行 g 再执行 f
Function<Integer, Integer> compose = f.compose(g);
// == (10 * 2) + 1 = 21
System.out.println(compose.apply(10));
```



参考资料：《Java8 实战》