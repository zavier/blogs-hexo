---
title: Java字节码结构
date: 2019-12-21 10:09:47
tags: java
---



我们都知道java实现跨平台靠的是虚拟机技术，将源文件编译成与操作系统无关的，只有虚拟机能识别并执行的字节码文件，由各个操作系统上的jvm来负责执行，屏蔽了底层具体的操作系统。这里我们就来认识一下这个只有jvm才认识的字节码文件的真实样子。

为了节省空间，类文件中没有任何分隔符，各个数据项都是一个挨着一个紧凑排列的，所以其中无论是顺序还是数量等都是严格规定的，哪个字节代表什么含义，长度是多少，先后顺序如何，都不允许改变。下面我们先看一下类文件的整体结构：

<!-- more -->

Class文件结构

![class_struct](/images/class_struct.png)

 

 

 其中常量、接口、字段、方法和属性在其中按各自的结构紧密排列，个数由其前面的数量字段决定。同时类文件中最小单位为1个字节，超过一个字节的数据以大端方式存储。

 下面依次介绍其中的每个部分：

### 魔数

魔数是用来确定文件的类型是否是class文件，因为只靠文件扩展名来确定文件类型并不可靠。

这个魔数占文件的开始4个字节，为CA FE BA BE。（注意：这里的字面代表的是十六进制数，而不是ASCII码）

### 版本号

接下来的4个字节为class文件版本号，其中前两个字节表示的是次版本号，后两个字节表示的是主版本号（从45开始）。

虚拟机可以向下兼容运行class文件，但不能运行高于其版本的class文件。

### 常量池

由于常量池中的常量数量是不确定的，所以在常量池的入口需要有两个字节用来代表常量池容量计数值（常量池索引从1开始）。

一共有14种常量类型，有着各自对应的结构，但开始的一个字节同样都是表示标志位，用来区分不同的类型。

下面为14种常量的具体类型和对应的标志位：

![img](/images/class_constant_type.png)

每种类型的结构如下（其中u1表示1个字节，u2表示2个字节，其他同理）：

![img](/images/class_constant_info.png)

 

 

读取常量池的时候首先读取标志位，判断常量类型，就可以知道对应的结构，获取对应的信息了。

### 访问标志

 常量池之后的两个字节代表访问标志，即这个class是类还是接口，是否为public等的信息。不同的含义有不同的标志值（没有用到的标志位一律为0。），具体信息如下：

 ![img](/images/class_access_flag.png)

###  类索引

类索引占两个字节，分别指向常量池中的CONSTANT_Class_info类型的常量，这个类型的常量结构见常量池中的图表，其中包含一个指向全限定名常量项的索引。

### 父类索引

因为java只允许单继承，所以只有一个父类，具体内容同上-类索引。

###  接口索引

接口索引开始两个字节用来表示接口的数量，之后的每两个字节表示一个接口索引，用法同类索引与父类索引。

### 字段

字段用于描述接口或者类中声明的变量，包括类级变量以及实例变量，但不包括局部变量。

字段域的开始两个字节表示字段数量，之后为紧密排列的字段结构体数据，其结构如下：

![img](/images/class_field.png)

其中的字段和方法的描述符，对于字段来说用来描述**字段的数据类型**；而对于方法来说，描述的就是**方法的参数列表（包括数量、类型以及顺序）和返回值**，这个描述顺序也是固定的，必须是参数列表在前，返回值在后，参数列表必须放在一组小括号内。同时为了节省空间，各种数据类型都使用规定的一个字母来表示，具体如下：

![img](/images/class_type_short.png)

对象使用L加上对象的全限定名来表示，而数组则是在每一个维度前添加一个"["来描述。

属性表在之后进行介绍。

### 方法

class文件中对方法的描述与以前对字段的描述几乎采用了完全一致的方式，唯一的区别就是访问类型不完全一致。

### 属性

java7中预定义了21项属性，具体内容限于篇幅不再列出。

对于每个属性的结构，没有特别严格的要求，并且可以自定义属性信息，jvm运行时会忽略不认识的属性。

符合规范的属性表基本结构如下：

![img](/images/class_attribute.png)

其中前两个字节为指向常量池中的CONSTANT_Utf8_info类型的属性名称，之后4个字节表示属性值所占用的位数，最后就是具体属性了。

 其中有一个比较重要的名称为「Code」的属性为方法的代码，即字节码指令。

Code属性表结构如下：

 ![img](/images/class_code.png)

 

 

以上只列出了一些Class文件最基本的结构，如有错误欢迎指正。

另：目前准备写一个基于字节码，分析方法（类、包）间的调用关系工具，项目地址：https://github.com/zavier/jclass-relation ，欢迎有兴趣的同学PR
