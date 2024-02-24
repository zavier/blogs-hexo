---
title: Spring通过@Value注入外部配置值
date: 2024-02-24 15:04:14
tags: [spring]
---

在spring项目中我们可以通过@Value注解使用配置文件中的值，但是有时候我们想注入外部系统（如配置中心）中配置的值，这时候可以通过读取配置中心的值并作为`PropertySource`注入到Spring的 `Environment`中来实现

<!-- more -->

1. 先定义一个实现ApplicationContextInitializer接口的类，用于读取配置并添加到Environment中

```java
public class DynamicConfigInitializer implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    @Override
    public void initialize(ConfigurableApplicationContext applicationContext) {
        final ConfigurableEnvironment environment = applicationContext.getEnvironment();

        final MutablePropertySources propertySources = environment.getPropertySources();

        // TODO 这里可以调用配置中心的api等方式来获取配置KV信息
        Map<String, Object> map = new HashMap<>();
        map.put("d.key1", "this is dynamic test value");

        final MapPropertySource mapPropertySource = new MapPropertySource("dynamic", map);

        // 将配置中心的PropertySource添加到最后，也可以调用 addFirst方法添加到最前面
        // 读取的时候是按照顺序读取的，前面的PropertySource中如果已经有值就会用前面的配置值
        // 可以根据自己的需求调用 addLast / addFirst
        propertySources.addLast(mapPropertySource);
    }
}
```

2. 将DynamicConfigInitializer添加到spring.factories配置中自动读取

META-INF/spring.factories

```text
org.springframework.context.ApplicationContextInitializer=\
com.zavier.bootdemo.config.DynamicConfigInitializer
```

3. 这时候可以写一个Controller来验证一下

```java
@RestController
public class DemoController {

    @Value("${d.key1}")
    private String dKey1;

    @GetMapping("/getKey")
    public String getKey() {
        return dKey1;
    }
}
```

下面来请求验证一下，可以看到读取的是外部设置的值

```shell
(base) ➜  ~ curl "http://localhost:8080/getKey"
this is dynamic test value
```

这时候如果我们在application.properties 或者 application.yml中也配置一个相同的key

```
# application.properties
d.key1=this is config by file
```

重启服务后，再次请求，这时候因为我们是使用 addLast 添加的值，所以application.properties文件中的配置优先

```shell
(base) ➜  ~ curl "http://localhost:8080/getKey"
this is config by file
```

如果我们把 addLast 改为 addFirst 会发现又读取到了外部配置的值

```shell
(base) ➜  ~ curl "http://localhost:8080/getKey"
this is dynamic test value
```

