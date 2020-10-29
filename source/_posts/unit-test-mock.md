---
title: 单元测试之Mock
date: 2020-10-29 21:05:01
tags: java
---

单元测试是对我们写的代码的最小单元进行测试，一般来说就是对函数(方法)进行测试，大家都知道写单元测试的好处，但是具体要怎么写呢？被测试的类可能依赖外部的类或服务，这个依赖的外部接口如何Mock，依赖注入的类如何替换成自己Mock的类等等，下面就介绍一下常用的Mock方式

<!-- more -->

首先，既然是单元测试，那么要做的第一件事就是屏蔽掉对外部的依赖，不让它们对我们要测试的方法产生影响。屏蔽的方式一般就是通过Mock，这里简单介绍一种Mock框架 [Mockito](https://site.mockito.org/#intro)

首先需要引入对应的依赖，如果使用Maven则需要在pom.xml中添加如下内容

```xml
<dependency>
	<groupId>org.mockito</groupId>
	<artifactId>mockito-all</artifactId>
	<version>1.10.19</version>
	<scope>test</scope>
</dependency>
```

创建测试类

```Java
public class UserTest {

    @Test
    public void test() {
        // 创建Mock对象
        final UserService mockUserService = Mockito.mock(UserService.class);

        // 设置mock对象的行为
        final User user = new User();
        user.setName("Test");
        Mockito.when(mockUserService.getUser(Mockito.anyInt())).thenReturn(user);

        Assert.assertEquals("Test", mockUserService.getUser(1).getName());
    }
}

// 创建Mock对象也可以使用注解的方式
public class UserTest {
    @Mock
    private UserService mockUserService;
    @Before
    public void init() {
        MockitoAnnotations.initMocks(this);
    }

    @Test
    public void test() {
        final User user = new User();
        user.setName("Test");
        Mockito.when(mockUserService.getUser(Mockito.anyInt())).thenReturn(user);
        Assert.assertEquals("Test", mockUserService.getUser(1).getName());
    }
}

// 或者这样写，都是可以的，如果需要调用真实对象，将Mock改为Spy，去掉when..then逻辑即可
@RunWith(MockitoJUnitRunner.class)
public class UserTest {
    @Mock
    private UserService mockUserService;

    @Test
    public void test() {
        final User user = new User();
        user.setName("Test");
        Mockito.when(mockUserService.getUser(Mockito.anyInt())).thenReturn(user);
        Assert.assertEquals("Test", mockUserService.getUser(1).getName());
    }
}
```

Mock了依赖的对象后，接下来就是将依赖的类替换成这个Mock类，一般我们项目都会使用Spring，如果是通过构造器注入或者Setter注入的方式的话，可以直接将Mock对象传递进去即可，如果使用了@Autowired 或者 @Resource注解方式来进行注入的话，则可以使用@InjectMocks注解来将依赖对应设置进去

```Java
@RunWith(MockitoJUnitRunner.class)
public class UserTest {

    @InjectMocks
    private UserService userService;

    // 会自动注入到 UserService 中
    @Mock
    private UserDao userDao;

    @Test
    public void test() {
        final UserDao userDao = userService.getUserDao();
        Assert.assertNotNull(userDao);
    }
}

public class UserService {
    private UserDao userDao;

    public UserDao getUserDao() {
        return userDao;
    }
}
```



