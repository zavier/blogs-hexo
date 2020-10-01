---
title: Flyway简介
date: 2020-10-02 00:31:10
tags: flyway
---

平时我们写代码一般使用Git等工具来进行版本管理，而Flyway可以理解为是用来进行数据库的版本管理的，它的功能是比较强大的，详细内容可以参考[文档](https://flywaydb.org/)，这里简单介绍一下常用的使用方法


## 基本maven使用

### 引入依赖

```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
    <version>7.0.0</version>
</dependency>
```


### 创建SQL脚本并执行

在src/resources下创建 db/migration目录，在其中创建对应的SQL文件，其中又分为不同的文件类型，基于约定由于配置的原则，通过文件命名方式进行区分

![flyway](/images/flyway.png)

版本迁移以V开头，只会执行一次；回退迁移以U开头，一般不使用；可重复执行迁移以R开头，每次修改后都会重新执行

<!-- more -->

**版本迁移类型**

在db/migration目录下创建版本迁移文件 V1__CreateUser.sql

```sql
create table user (
  id bigint not null auto_increment,
  name varchar(50) not null,
  primary key (id)
)
```

以Java API方式调用执行

```java
public static void main(String[] args) {
    final Flyway flyway = Flyway.configure()
            .dataSource("jdbc:mysql://localhost:3306/test", "user", "password")
            .load();
    flyway.migrate();
}
```

执行后会发现，之前空的库里面多了两张表（SQL已经执行）

```
mysql> show tables;
+-----------------------+
| Tables_in_test        |
+-----------------------+
| flyway_schema_history |   // 用来记录数据库的各个版本信息
| user                  |   // 创建的用户表
+-----------------------+
2 rows in set (0.00 sec)
```

如果启动时没有flyway_schema_history(默认表名)表，则会初始创建一个

多次执行会发现，只有第一次会执行 V1__CreateUser.sql，后面就不会再次执行了



**可重复执行迁移类型**

在db/migration目录下创建版本迁移文件 R__AddUser.sql

```sql
insert into user (name) values ("test");
```

执行后发现user表中多了一条记录，再次执行也是只有一条记录，只有当我们修改内容后才会再次执行

这时我们修改文件内容为

```sql
insert into user (name) values ("test1");
```

再次执行代码发现SQL会再次执行

```
mysql> select * from user;
+----+-------+
| id | name  |
+----+-------+
|  1 | test  |
|  2 | test1 |
+----+-------+
```

这时我们来看下历史记录表，总共有三次执行记录

```
mysql> select * from flyway_schema_history;
+----------------+---------+-------------+------+--------------------+------------+--------------+---------------------+----------------+---------+
| installed_rank | version | description | type | script             | checksum   | installed_by | installed_on        | execution_time | success |
+----------------+---------+-------------+------+--------------------+------------+--------------+---------------------+----------------+---------+
|              1 | 1       | CreateUser  | SQL  | V1__CreateUser.sql | -171442567 | root         | 2020-10-01 23:54:35 |             23 |       1 |
|              2 | NULL    | AddUser     | SQL  | R__AddUser.sql     |  517863463 | root         | 2020-10-02 00:15:06 |             10 |       1 |
|              3 | NULL    | AddUser     | SQL  | R__AddUser.sql     | -267384455 | root         | 2020-10-02 00:15:47 |             11 |       1 |
+----------------+---------+-------------+------+--------------------+------------+--------------+---------------------+----------------+---------+
```



## Spring Boot使用

在Spring Boot项目中引入flyway依赖后，在配置文件中进行对应的配置，如

```properties
# 开启
spring.flyway.enabled=true
# 禁止清理数据表
spring.flyway.clean-disabled=true
# 版本控制信息表名，默认 flyway_schema_history
spring.flyway.table=flyway_schema_history
# 是否允许不按顺序迁移
spring.flyway.out-of-order=false
# 如果数据库不是空表，需要设置成 true，否则启动报错
spring.flyway.baseline-on-migrate=true
# 与 baseline-on-migrate: true 搭配使用，小于此版本的不执行
spring.flyway.baseline-version=0
# 使用的schema
spring.flyway.schemas=test
# 执行迁移时是否自动调用验证
spring.flyway.validate-on-migrate=true
```

之后配置对应的数据源信息，在项目启动时会**自动**根据情况执行对应的SQL

这个主要是因为spring-boot-autoconfigure包中包含对应的Flyway配置

![flyway-autoconfig](/images/flyway-autoconfig.jpg)

