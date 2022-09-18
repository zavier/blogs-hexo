---
title: Java对象比对实现
date: 2022-09-17 14:53:53
tags: [java, diff]
---

有时候我们需要对于同一个类的两个实例对象进行一下数据内容的比对，找出他们的差异，比如用来做单测或者同一份数据多版本的内容比对，这里主要介绍使用apache的commons-lang3的工具类来进行功能实现

<!-- more -->

首先需要引入如下包依赖

```xml
<dependency>
    <groupId>org.apache.commons</groupId>
    <artifactId>commons-lang3</artifactId>
    <version>3.12.0</version>
</dependency>
```

使用时需要实现`Diffable`接口，并使用`DiffBuilder`来构建比对结果

```java
public class Person implements Diffable<Person> {
    String name;
    int age;
    boolean smoker;

    public DiffResult diff(Person obj) {
        // obj可能为null，这里可以自行判断处理
        return new DiffBuilder(this, obj, ToStringStyle.JSON_STYLE)
            .append("name", this.name, obj.name)
            .append("age", this.age, obj.age)
            .append("smoker", this.smoker, obj.smoker)
            .build();
    }
}
```

运行测试一下

```java
final Person aa = new Person("aa", 12, true);
final Person bb = new Person("bb", 12, false);
final DiffResult diff = aa.diff(bb);
System.out.println(diff);

// 结果输出如下
// {"name":"aa","smoker":true} differs from {"name":"bb","smoker":false}
```

这种对于简单的属性是OK的，对于嵌套的可比较类可以使用如下方式

```java
// 使用 DiffBuilder#append(String, DiffResult<T>)
public class Person implements Diffable<Person> {
    String name;
    int age;
    boolean smoker;
    // Address是一个可比较的类
    Address address;

    public DiffResult diff(Person obj) {
        // obj可能为null，这里可以自行判断处理
        return new DiffBuilder(this, obj, ToStringStyle.JSON_STYLE)
            .append("name", this.name, obj.name)
            .append("age", this.age, obj.age)
            .append("smoker", this.smoker, obj.smoker)
            // 这里可以直接设置比对结果到address中
            .append("address", this.address.diff(obj.getAddress()))
            .build();
    }
}

@Data
public class Address implements Diffable<Address> {
    private String province;
    private String city;
    @Override
    public DiffResult diff(Address obj) {
        return new DiffBuilder(this, obj, ToStringStyle.MULTI_LINE_STYLE)
                .append("province", this.getProvince(), obj.getProvince())
                .append("city", this.getCity(), obj.getCity())
                .build();
    }
}
```

结果样例如下

```json
{"age":13,"address.city":"c1"} differs from {"age":14,"address.city":"c2"}
```

整体功能到这里基本就实现了，但是对于其中的diff方法中的很多append手写起来比较麻烦，我们可以写一个工具类来简化代码

```java
public class DiffUtils<T> {

    public static <T> DiffResult<T> buildResult(T baseObj, T compareObj, String... excludeFields) {
        try {
            final DiffBuilder<T> diffBuilder = new DiffBuilder<>(baseObj, compareObj, ToStringStyle.JSON_STYLE);

            // 这里使用的JavaBean相关的工具类，所以要去比对对象需要符合JavaBean的规范
            // 也可以替换成使用反射相关方法，来支持非JavaBean的比较
            final BeanInfo beanInfo = Introspector.getBeanInfo(baseObj.getClass());
            final PropertyDescriptor[] propertyDescriptors = beanInfo.getPropertyDescriptors();
            for (PropertyDescriptor propertyDescriptor : propertyDescriptors) {
                if (isExcludeField(propertyDescriptor.getName(), excludeFields)) {
                    continue;
                }

                final Method readMethod = propertyDescriptor.getReadMethod();

                final Object obj1 = readMethod.invoke(baseObj);
                final Object obj2 = readMethod.invoke(compareObj);
                if (obj1 instanceof Diffable) {
                    Diffable diffable1 = (Diffable) obj1;
                    Diffable diffable2 = (Diffable) obj2;
                    diffBuilder.append(propertyDescriptor.getName(), diffable1.diff(diffable2));
                } else {
                    diffBuilder.append(propertyDescriptor.getName(), obj1, obj2);
                }
            }

            return diffBuilder.build();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static boolean isExcludeField(String fieldName, String... excludeFields) {
        if (excludeFields == null || excludeFields.length == 0) {
            return false;
        }
        for (String excludeField : excludeFields) {
            if (excludeField.equalsIgnoreCase(fieldName)) {
                return true;
            }
        }
        return false;
    }
}
```

这样实现的代码就可以简化为

```java
public class Person implements Diffable<Person> {
    String name;
    int age;
    boolean smoker;

    public DiffResult diff(Person obj) {
        // 使用工具类来构建
        return DiffUtils.buildResult(this, obj);
    }
}
```

目前还有一个问题，就是其中属性如果是对象的集合，那么比较起来会有点问题，效果大致是这样的

```json
{"addressList":["Address(province=aa, city=bb)","Address(province=bb, city=cc)"],"name":"aa","smoker":true} differs from {"addressList":["Address(province=aa, city=bb)","Address(province=bb, city=dd)"],"name":"bb","smoker":false}
```

这种可能就需要我们根据实际的需求，进行相关的功能改造来进行支持，或者将commons-lang3中的相关代码复制出来进行改造
