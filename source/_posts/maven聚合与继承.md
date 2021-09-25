---
title: maven聚合与继承
date: 2019-02-06 16:18:26
tags: [java, maven]
---

### maven聚合

聚合的目的是为了**快速构建项目**，当我们有几个maven模块，想要一次性构建，而不是到每个模块下面去执行maven命令，这时候就需要使用maven聚合（或者称为多模块）。

使用聚合的时候，我们需要新建一个maven项目，由它来控制构建其他的项目，其pom.xml配置与其他普通maven项目的区别主要在以下两个地方：

1. 打包类型（packaging）必须为pom
2. 需要在其中添加modules标签，在其中使用module标签包括需要同时构建的maven模块的名称路径，路径为相对于此pom.xml文件的路径（如果与pom.xml文件同级则直接写项目名，如果在上一级则写../项目名）。

这样当我们在此项目下执行构建的时候，就会同时构建其中配置的项目。

<!-- more -->

下面举一个配置文件的例子：

```xml
<project ......>
  <groupId>XXX.XXX</groupId>
  <artifactId>XXX</artifactId>
  <version>1.0</version>
  <packaging>pom</packaging>
  <modules>
    <module>XX1</module>
    <module>XX2</module>
  </modules>
</project>
```

 

### maven继承

继承的目的是为了**消除重复配置**，在项目中可以通过继承父模块的一些配置来简化配置文件，避免配置的重复。

#### 父模块

1. 使用继承的时候，父模块的配置文件（pom.xml）中打包类型必须同聚合一样，为pom。
2. 依赖管理：为了避免子模块继承没有不必要的依赖，所以在父模块中并不引入实际的依赖，而是使用dependencyManagement元素，在其中声明的的dependencies不会在其本身（父模块）中引入依赖，也不会给它的子模块引入依赖。如果在子模块需要使用其中配置的依赖，则可以在子模块中声明，但是不需要声明版本号和依赖范围（已在父模块中声明），这样可以统一不同模块中的依赖版本。
3. 插件管理：同依赖管理，Maven提供了类似的pluginManagement元素来帮助管理插件，使用方式也基本相同。

#### 子模块

子模块如果要继承父模块，则需在其pom.xml中需添加如下配置，同时其groupId和version会省略，直接继承父模块的配置。

```xml
<parent>
    <groupId>XXX.XXX</groupId>
    <artifactId>XX</artifactId>
    <version>1.0</version>
    <relativePath>XX/XX/pom.xml</relativePath>
</parent>
```

其中relativePath为父项目的pom.xml路径（如果没有配置此项，则默认为../pom.xml，即上级目录下的pom.xml），构建时会先根据relativePath查找，如果找不到，则会再从本地仓库查找。



**注：maven聚合和继承可以同时使用。**



