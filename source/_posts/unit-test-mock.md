---
title: 单元测试之Mock
date: 2020-10-29 21:05:01
tags: [java, 单元测试]
---

单元测试是对我们写的代码的最小单元进行测试，一般来说就是对函数(方法)进行测试，大家都知道写单元测试的好处，但是具体要怎么写呢？被测试的类可能依赖外部的类或服务，这个依赖的外部接口如何Mock，依赖注入的类如何替换成自己Mock的类等等，下面就介绍一种常用的Mock方式

<!-- more -->

首先，既然是单元测试，那么要做的第一件事就是屏蔽掉对外部的依赖，不让它们对我们要测试的方法产生影响。屏蔽的方式一般就是通过Mock，将调用的真实方法替换为我们设置好的mock类，这里简单介绍一种Mock框架 [Mockito](https://site.mockito.org/#intro)

首先需要引入对应的依赖，如果使用Maven则需要在pom.xml中添加如下内容

```xml
<dependency>
    <groupId>org.mockito</groupId>
    <artifactId>mockito-all</artifactId>
    <version>1.10.19</version> <!-- 可以替换最新的版本号 -->
    <scope>test</scope>
</dependency>
```

### 创建Mock类

为了进行mock, 第一部我们就需要创建一个mock的类，用来后续替换真实的类

1. 通过编程式创建mock类

```java
// 使用Mockito.mock根据接口/类，创建一个mock实例
UserService mockUserService = Mockito.mock(UserService.class);
```

2. 通过注解方式创建mock类

```java
public class UserTest {
    @Mock // 注意这里需要设置的是实现类，不能写接口类型，不然无法构造实例
    private UserService mockUserService;
}
```

但是这种写法需要有一个契机来对注解属性进行mock赋值，这里也有两种方式：

一种是通过在类上面添加`@RunWith(MockitoJUnitRunner.class)`注解

还有一种就是通过Junit的@Before注解方法中调用`MockitoAnnotations.initMocks(this)`来实现

实现的时候根据情况选择其中一种方式即可

```java
@RunWith(MockitoJUnitRunner.class) // 初始化方式一
public class UserTest {
    @Mock
    private UserService mockUserService;
    
    @Before
    public void init() {
        // 初始化方式二
        MockitoAnnotations.initMocks(this);
    }
}
```



### 将Mock类注入到要测试的类中

我们创建mock类，是为了在有依赖的地方可以直接调用mock类，而不是实际的类，所以需要进行替换

假设实际业务代码如下：

```java
@Service
public class UserService {
    // 我们需要进行替换的类
    private UserDao userDao;
    
    public User findUserById(Long id) {
        // 这里是我们需要mock的方法，替换之后可以返回一个需要的类实例信息
        return userDao.selectByPrimaryKey(id);
    }
}
```

对于上述场景，可以通过在要测试的类上添加 InjectMocks 注解即可

```java
@RunWith(MockitoJUnitRunner.class)
public class UserTest {

    // 在需要测试的类上添加 InjectMocks 注解即可
    @InjectMocks
    private UserService userService;

    // 会自动注入到 UserService 中
    @Mock
    private UserDao userDao;
}
```



### 管理mock类的方法

创建并设置好mock类之后，我们来管理mock的方法来实现我们要测试覆盖的场景



使用when...thenReturn... , 来实现调用简单方法时返回特定的值

```java
final User user = new User();
user.setName("Test");
// 当调用mock的UserService的getUser方法时，会返回固定的user信息
Mockito.when(mockUserService.getUser(Mockito.anyLong())).thenReturn(user);
```



使用 when ... thenAnswer 可以实现根据参数值返回不同的内容

```java
Mockito.when(mockUserService.getUser(Mockito.anyLong())).thenAnswer(new Answer<User>() {
    @Override
    public User answer(InvocationOnMock invocation) throws Throwable {
        // 获取请求的第一个参数id值
        Long id = invocation.getArgument(0);
        // 这里可以根据参数的值进行判断，返回不同的内容
        User user = new User();
        return user
    }
});
```



使用verify等验证方法调用次数及参数值

```java
// 构造一个用于获取参数的ArgumentCaptor，其范型类型为参数的类型
ArgumentCaptor<Long> argumentCaptor = ArgumentCaptor.forClass(Long.class);
// 使用verify, 验证 getUser方法只调用了一次
Mockito.verify(mockUserService, Mockito.times(1)).getUser(argumentCaptor.capture());
// 最后验证一下参数值, 从argumentCaptor中获取参数值，进行断言
final Long id = argumentCaptor.getValue();
Assert.assertEquals(1000L, id.longValue());
```

verify需要在实际方法调用之后处理，同时可以配合对应方法的when...then..使用，不会互相影响

也就是说可以通过when...then...对一个方法进行mock返回值

同时还可以使用verify验证参数信息

```java
// mock返回
final User user = new User();
user.setName("Test");
Mockito.when(mockUserService.getUser(Mockito.anyLong())).thenReturn(user);
// 实际调用&结果验证
User u = mockUserService.getUser(1L);
Assert.assertEquals("Test", u.getName());
// 参数验证
ArgumentCaptor<Long> argumentCaptor = ArgumentCaptor.forClass(Long.class);
Mockito.verify(mockUserService, Mockito.times(1)).getUser(argumentCaptor.capture());
final Long id = argumentCaptor.getValue();
Assert.assertEquals(1L, id.longValue());
```



