---
title: maven-profiles
date: 2024-01-28 18:21:52
tags: [maven]
---

虽然maven的目标是使项目构建是可移植的，尽量使在任何机器下都可以构建且结果相同，但是仍然会有一些情况需要我们根据环境等信息来构建不同的内容，这时候就需要用到 [maven profiles](https://maven.apache.org/guides/introduction/introduction-to-profiles.html)

<!-- more -->

## Profiles配置激活

profiles可以在全局配置的setting.xml中配置，也可以在项目的pom.xml中进行配置，这里我们主要看下在项目中进行配置

```xml
<profiles>
    <!-- 定义一个profile -->
    <profile>
        <!-- 定义profile的ID，也就是唯一的名称 -->
        <id>dev</id>
        <!-- 这里可以配置激活此profile的配置，多个条件时需要同时满足 -->
        <activation>
            <!-- 在没有任何满足条件的profile时，是否默认使用此profile -->
            <activeByDefault>false</activeByDefault>
            <!-- 满足激活此profile的jdk版本 -->
            <jdk>17</jdk>
            <!-- 满足激活此profile的环境配置 -->
            <property>
                <!-- 具体的属性和值可以自己定义，这里要求配置变量 env=test -->
                <name>env</name>
                <value>test123</value>
            </property>
        </activation>
        
        <!-- 激活此profile后，会设置的属性值，可以设置多个 -->
        <properties>
            <!-- 这里会设置成 jdbc.url=jdbc:mysql://dev/db等 -->
            <jdbc.url>jdbc:mysql://dev/db</jdbc.url>
            <jdbc.username>name</jdbc.username>
            <jdbc.password>pwd</jdbc.password>
        </properties>
        
        <!-- 后面其实还可以配置这个profile单独的依赖，插件等信息 -->
        <!-- ... -->
    </profile>
    
    <!-- 可以配置多个 profile -->
    <profile>
        <id>local</id>
        <activation>
            <activeByDefault>true</activeByDefault>
        </activation>
        <properties>
            <jdbc.url>jdbc:mysql://local/db</jdbc.url>
            <jdbc.username>local-name</jdbc.username>
            <jdbc.password>local-pwd</jdbc.password>
        </properties>
    </profile>
</profiles>
```

这时候如何如果执行maven命令没有任何参数时，会激活 local（因为它的activeByDefault=true），如：

```shell
# 激活默认的 local
mvn compile
```

如果指定了环境变量，同时jdk版本为17，则会激活 dev（不会激活local, 有匹配到的是不会使用activeByDefault），如

```shell
# 如果jdk版本为17，则只会激活 dev，否则还是只会激活 local
mvn compile -Denv=test123
```

或者可以不管条件，通过-p参数手动强制指定要激活的profile，多个以逗号分隔，如

```shell
# 手动指定激活 local, dev
mvn compile -P local,dev
```

这样我们就实现了通过指定一个或者多个profile，设置对应的属性信息等配置



## Profiles使用

下面根据profile设置的信息，来进行使用，这里介绍一下不同环境连接不同的数据库

我们接着之前的配置，首先激活不同的profile时，会设置对应的数据库连接相关变量信息

一般我们会把数据库连接信息配置到配置文件中，如db.properties，这里将其对应的值设置为变量形式

```properties
jdbc.url=${jdbc.url}
jdbc.username=${jdbc.username}
jdbc.password=${jdbc.password}
```

下一步，需要进行maven resource的插件，来实现变量替换，在pom.xml中配置如下信息

```xml
<build>
    <resources>
        <resource>
            <directory>src/main/resources</directory>
            <!-- 配置为true会进行变量替换 -->
            <filtering>true</filtering>
        </resource>
    </resources>
</build>
```

变量替换相关可以参考[maven-resources-plugin Filtering](https://maven.apache.org/plugins/maven-resources-plugin/examples/filter.html)

这时候通过maven compile -P \<profile\>， 在 target中会发现结果文件中的 db.properties已经被替换成对应profile中的变量信息

