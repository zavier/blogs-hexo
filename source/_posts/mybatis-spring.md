---
title: MyBatis(一)配置详解
date: 2019-03-31 18:22:50
tags: [java, mybatis, spring]
---

## MyBatis 基本用法


MyBatis是我们常用的ORM框架，先看一下它的基本用法(省略了Mapper相关的配置项):

```java
// 读取MyBatis配置文件
InputStream inputStream = Resources.getResourceAsStream("mybatis-config.xml");
// 从配置文件中构建 SqlSessionFactory (全局只有一个，用于构建 SqlSession)
SqlSessionFactory sessionFactory = new SqlSessionFactoryBuilder().build(inputStream);
// 使用 SqlSessionFactory 创建 SqlSession(请求作用域，用后销毁)
SqlSession session = sessionFactory.openSession(true);
// 获取对应 Mapper
UserMapper mapper = session.getMapper(UserMapper.class);
// 执行查询
User user = mapper.findById(1);
// 关闭 session
session.close();
```

## MyBatis-Spring

工作中最常用的还是与Spring结合，使用mybatis-spring

```xml
<dependency>
  <groupId>org.mybatis</groupId>
  <artifactId>mybatis-spring</artifactId>
  <version>2.0.1</version>
</dependency>
```

<!-- more -->


看一下mybatis-spring的主要配置及使用

spring-mybatis.xml
```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans.xsd">

    <!-- 使用Spring提供的简单的DataSource -->
    <bean id="dataSource" class="org.springframework.jdbc.datasource.DriverManagerDataSource">
        <property name="url" value="jdbc:mysql://localhost:3306/demo" />
        <property name="driverClassName" value="com.mysql.jdbc.Driver" />
        <property name="username" value="root" />
        <property name="password" value="root" />
    </bean>

    <!-- 声明 SqlSessionFactoryBean -->
    <bean id="sqlSessionFactoryBean" class="org.mybatis.spring.SqlSessionFactoryBean">
        <!-- 指定数据源 -->
        <property name="dataSource" ref="dataSource" />
        <!-- 指定Mapper文件所在的路径 -->
        <property name="mapperLocations" value="classpath:mapper/*.xml" />
        <!-- 加载配置文件 -->
        <property name="configLocation" value="mybatis-config.xml" />
    </bean>

    <!-- 声明扫描的包，创建对应的 MapperFactoryBean -->
    <bean class="org.mybatis.spring.mapper.MapperScannerConfigurer">
        <property name="basePackage" value="com.zavier.demo.dao" />
    </bean>

</beans>
```

main方法

```java
ClassPathXmlApplicationContext applicationContext = new ClassPathXmlApplicationContext("spring-mybatis.xml");
UserMapper userMapper = applicationContext.getBean("userMapper", UserMapper.class);

UserDO userDO = new UserDO();
userDO.setUserName("testname");
userDO.setUserAge(1);
userMapper.save(userDO);

userDO = userMapper.findById(1);
System.out.println(userDO);
```

下面分析一下上面的配置

MyBatis-Spring对于mybatis中关键的 `SqlSessionFactoryBuilder`、`SqlSession`、`Mapper接口`等提供了替代的Bean，避免了手动创建管理的麻烦，只需要配置对应的类即可注入使用，很方便


一、 对于`SqlSessionFactoryBuilder`，使用`sqlSessionFactoryBean` （实现了Spring的FactoryBean）替代，用来创建 `SqlSessionFactory`


```xml
<!-- 使用SqlSessionFactoryBean 替代 SqlSessionFactoryBuilder -->
<bean id="sqlSessionFactory" class="org.mybatis.spring.SqlSessionFactoryBean">
  <!-- 指定数据源 -->
  <property name="dataSource" ref="dataSource" />
  <!-- 使用 mapper 对应的xml文件路径 -->
  <property name="mapperLocations" value="classpath*:sample/config/mappers/**/*.xml" />
  <!-- 还可注入其他属性，如configLocation等 -->
</bean>
```



二、 对于`SqlSession`，提供`SqlSessionTemplate`，它线程安全（可以简单理解为每次创建新的SqlSession），提供了执行SQL方法，翻译异常功能

```java
// =============================主要源码===========================================
public class SqlSessionTemplate implements SqlSession, DisposableBean {
  private final SqlSessionFactory sqlSessionFactory;
  private final ExecutorType executorType;
  private final SqlSession sqlSessionProxy;
  public SqlSessionTemplate(SqlSessionFactory sqlSessionFactory, ExecutorType executorType, PersistenceExceptionTranslator exceptionTranslator) {
  // SqlSessionInterceptor代理SqlSession的方法
  this.sqlSessionProxy = (SqlSession) newProxyInstance(
        SqlSessionFactory.class.getClassLoader(),
        new Class[] { SqlSession.class },
        new SqlSessionInterceptor());
  }
  // 实现了sqlSession的执行操作方法
  @Override
  public <T> T selectOne(String statement) {
    return this.sqlSessionProxy.selectOne(statement);
  }
  // ...
}

private class SqlSessionInterceptor implements InvocationHandler {
  @Override
  public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
    // 获取sqlSession，反射调用，获取的时候会从TransactionSynchronizationManager中获取线程相关的类
    SqlSession sqlSession = getSqlSession(
        SqlSessionTemplate.this.sqlSessionFactory,
        SqlSessionTemplate.this.executorType,
        SqlSessionTemplate.this.exceptionTranslator);
    try {
      Object result = method.invoke(sqlSession, args);
      return result;
    } catch (Throwable t) {
      Throwable unwrapped = unwrapThrowable(t);
      // 包装处理异常
      throw unwrapped;
    }
  }
}
```

使用（只需注入 SqlSessionFactory）

```xml
<bean id="sqlSession" class="org.mybatis.spring.SqlSessionTemplate">
  <constructor-arg index="0" ref="sqlSessionFactory" />
</bean>
```

之后可以注入此 sqlSession正常使用，但是我们一般也不需要使用此配置项创建session，通过session来获取mapper进行执行查询等操作，而是直接创建mapper的bean，让容器注入到对应位置，直接执行。
我们接着往下看



三、对于Mapper接口，提供了 MapperFactoryBean（可以为每个mapper声明一个MapperFactoryBean）

SqlSessionDaoSupport

```java
// 主要方法如下，可以实现此类，通过 getSqlSession 方法获取 sqlSessionTemplate 执行
// 通常的实现类是 MapperFactoryBean 
public abstract class SqlSessionDaoSupport extends DaoSupport {
  private SqlSessionTemplate sqlSessionTemplate;

  protected SqlSessionTemplate createSqlSessionTemplate(SqlSessionFactory sqlSessionFactory) {
    return new SqlSessionTemplate(sqlSessionFactory);
  }

  public SqlSession getSqlSession() {
    return this.sqlSessionTemplate;
  }
}
```

MapperFactoryBean

```java
public class MapperFactoryBean<T> extends SqlSessionDaoSupport implements FactoryBean<T> {
  private Class<T> mapperInterface;

  @Override
  public T getObject() throws Exception {
    return getSqlSession().getMapper(this.mapperInterface);
  }
}
```

使用（提供SqlSessionFactory 与要实现的接口）

```xml
<bean id="userMapper" class="org.mybatis.spring.mapper.MapperFactoryBean">
  <!-- 指定接口，接口对应的mapper文件需要在sqlSessionFactory中指定 -->
  <property name="mapperInterface" value="org.mybatis.spring.sample.mapper.UserMapper" />
  <property name="sqlSessionFactory" ref="sqlSessionFactory" />
</bean>
```

MapperFactoryBean 是一个 FactoryBean, 它会返回传入的 UserMapper 接口的实例，之后可以使用此方法

```java
public class FooServiceImpl implements FooService {
  private UserMapper userMapper;

  public void setUserMapper(UserMapper userMapper) {
    this.userMapper = userMapper;
  }

  public User doSomeBusinessStuff(String userId) {
    return this.userMapper.getUser(userId);
  }
}
```

但是这样还是很麻烦，我们需要为每一个Mapper添加对应配置，有没有办法可以自动完成这个操作，而不用手动创建Mapper Bean呢，
答案当然是肯定的，继续来看


四、使用 MapperScannerConfigurer 来简化多个 MapperFactoryBean 声明，配置扫描的包，其下的接口会被自动创建成对应的 MapperFactoryBean

```xml
<!-- 扫描路径下的所有接口，自动将它们创建成 MapperFactoryBean -->
<bean class="org.mybatis.spring.mapper.MapperScannerConfigurer">
  <property name="basePackage" value="org.mybatis.spring.sample.mapper" />
</bean>
```

使用时可以直接注入对应的Mapper接口使用，具体可以回头看看之前的配置信息和使用例子


五、mybatis-spring配置总结

使用mybatis-spring，我们需要配置的项有三个

- Datasource
- SqlSessionFactoryBean
- MapperScannerConfigurer


附一个简单的配置例子供参数： [mybatis-spring-demo](https://github.com/zavier/mybatis-spring-demo)

另：

如果需要使用Spring的事务处理功能，需要添加如下配置

```xml
<bean id="transactionManager" class="org.springframework.jdbc.datasource.DataSourceTransactionManager">
  <constructor-arg ref="dataSource" />
</bean>
```

同时，如果要使用Spring的注解式事务，别忘了添加
```xml
<tx:annotation-driven transaction-manager="transactionManager" proxy-target-class="false"/>
```
这样就可以在需要事务的方法上添加`@Transactional`注解来实现事务了



