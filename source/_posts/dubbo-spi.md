---
title: Dubbo扩展点加载使用简述
date: 2019-11-09 21:45:19
tags: [java, dubbo]
---

扩展点加载机制主要是为了实现接口和实现的解耦，接口的具体实现并不在代码中指定，而是通过通过外部配置实现，Dubbo的扩展点加载是对JDK的SPI扩展点加强而来，大家如果不了解JDK的SPI也没有关系，这里我们主要来看一下Dubbo的实现

在Dubbo的实现中，主要有三个注解，`@SPI`、`@Adaptive`和`@Activate`，下面我们来结合例子分别看一下它们的使用

<!-- more -->

首先我们来定义一个接口和几个对应的实现

```java
// @SPI注解表示这是一个扩展点，可以有不同的实现
// 指定实现时，其中的名字需要与配置文件中的key相同
@SPI("simple")
public interface DemoService {
    String echo(URL url, String s);
}
```

```java
public class SimpleServiceImpl implements DemoService {
    @Override
    public String echo(URL url, String s) {
        return "SimpleService";
    }
}
```

```java
public class ComplexServiceImpl implements DemoService {
    @Override
    public String echo(URL url, String s) {
        return "ComplexService";
    }
}
```

使用时，我们需要在类路径下的`META-INF/dubbo/`或`META-INF/dubbo/internal/`路径下(也可以在java spi的`/META-INF/services/下`)创建与接口全路径相同的文件名，在其中以key-value形式指定各个实现类的全路径及对应名称（名称可以自己随意起），对于上面的例子我们可以这样写

```txt
## 文件名：com.test.spi.DemoService
simple=com.test.spi.SimpleServiceImpl
complex=com.test.spi.ComplexServiceImpl
```

由于上面我们在接口的SPI注解上指定了simple的实现，即`SimpleServiceImpl`实现类，写了测试类来验证一下

```java
@Test
public void testDefaultExtension() {
    final DemoService defaultExtension = ExtensionLoader.getExtensionLoader(DemoService.class)
      .getDefaultExtension();
    assertTrue(defaultExtension instanceof SimpleServiceImpl);
    final String echo = defaultExtension.echo(null, null);
    assertSame("SimpleService", echo);
}
```

测试通过～， 简单的使用就是这样，如果要切换不同的实现，修改@SPI注解中的值为对应实现即可



但这时有一个问题，就是这样我们还是在代码里写死了具体的实现，如果我们想在运行时再决定使用哪一个实现该怎么半？这时就要靠`@Adaptive`注解了，我们来看一下

其实我们要动态选择的其实不是实现类，而是实现类的方法，所以现在我们将接口修改如下

```java
@SPI("simple")
public interface DemoService {

    @Adaptive("service") // 和上面的区别在这里
    String echo(URL url, String s);
}
```

到这里，不得不提一下dubbo中的URL类，它是dubbo中的配置关键类，几乎所有的配置想都是在其中以参数键值对的形式存在，SPI的配置当然也不例外

我们在@Adaptive的注解中指定了一个值（可以任意指定，也可不指定，不过不指定则是对应类名的转换，如DemoService则转为 demo.service）这个值有什么用呢，它会从URL中找到和它一样的key对应的value值，这个value值就是要使用的实现类的key(配置文件中设置的key)

上面我们指定了@Adaptive值为"service", 如果url中有"?service=complex",那么执行时则是使用`complex=com.test.spi.ComplexServiceImpl`对应的类来执行

如果没有找到怎么办呢？那就使用SPI注解中的实现--"simple"做为默认实现

Dubbo处理有@Adaptive注解的类时，会默认使用javassist生成一个类，对应上面的类，生成的类内容大致简化如下`DemoService$Adaptive`

```java
public class DemoService$Adaptive implements com.test.spi.DemoService {
    public String echo(URL arg0, String arg1) {
        URL url = arg0;
        // 调用方法时，会通过URL中的参数值，获取对应类来执行
        String extName = url.getParameter("service", "simple");
        DemoService extension = (DemoService)ExtensionLoader.getExtensionLoader(DemoService.class).getExtension(extName);
        return extension.echo(arg0, arg1);
    }
}
```

看了这段代码，相信大家也明白了这个动态功能的实现，下面我们写一个测试类来验证一下

```java
@Test
public void testAdaptive() {
    final DemoService adaptiveExtension = ExtensionLoader.getExtensionLoader(DemoService.class)
            .getAdaptiveExtension(); // 注意这处的不同
    // service = complex
    // URL构造器 String protocol, String host, int port, String path, String... pairs
    final URL url = new URL("", "", 100, "", "service", "complex");
    final String echo = adaptiveExtension.echo(url, null);
    assertSame("ComplexService", echo);
}
```



到这里其实已经差不多够用了，但是还有一种情况，就是即使我们使用了@Adaptive注解，但是它只能选择一个类来执行，如果我们想匹配多个，并让它们都能得到执行怎么办呢？（如Dubbo中的过滤器）这时就需要`@Activate`出马了, 我们来修改一下代码

先新创建两个实现类，并添加@Activate注解

```java
@Activate(group = "act", value = "actone", order = 1)
public class ActivateOneServiceImpl implements DemoService {
    @Override
    public String echo(URL url, String s) {
        return "ActivateOneService";
    }
}
```

```java
@Activate(group = "act", value = "actTwo", order = 2)
public class ActivateTwoServiceImpl implements DemoService {
    @Override
    public String echo(URL url, String s) {
        return "ActivateTwoService";
    }
}
```

将它们添加到配置文件中去，这时的配置文件如下

```txt
simple=com.test.spi.SimpleServiceImpl
complex=com.test.spi.ComplexServiceImpl
actone=com.test.spi.ActivateOneServiceImpl
acttwo=com.test.spi.ActivateTwoServiceImpl
```

同样的，我们写个测试类来测试一下

```java
@Test
public void testActivateTwo() {
    // select = actone,acttwo(resources中的配置key)
    final URL url = new URL("", "", 100, "", "select", "actone,acttwo");
    final List<DemoService> activateExtension = ExtensionLoader.getExtensionLoader(DemoService.class)
            // 第二个参数执行获取url中的配置key是什么，第三个参数为执行的group
            .getActivateExtension(url, "select", "act");
    assertEquals(2, activateExtension.size());
    final DemoService demoService1 = activateExtension.get(0);
    assertTrue(demoService1 instanceof ActivateOneServiceImpl);
    final DemoService demoService2 = activateExtension.get(1);
    assertTrue(demoService2 instanceof ActivateTwoServiceImpl);
}
```



好了，基本的内容就介绍到这里，这里只是简单介绍了一下使用，还有许多内容没有说到，比如

- 自动包装：可以定义接口实现时，构造器仍然为一个此接口的参数，这时dubbo会认为它是一个wrapper（可以理解设计模式中的装饰器模式），对于所有类的实现，都会通过这个包装类

- @Adaptive中的注解值可以指定多个，执行时会依次进行匹配

- @Activate的匹配方式还有许多，不止是上面提到的那种，比如URL值的参数键和@Activate中的value匹配上的话也会激活

等等等等，大家有兴趣的话可以继续研究下去