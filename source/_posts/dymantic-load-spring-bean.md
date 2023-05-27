---
title: 一种动态添加外部Jar包中SpringBean的方式
date: 2021-04-16 22:26:48
tags: [java, spring]
---



我们在日常写代码的过程中，经常会有一个扩展点接口，同时会有多种实现，类似策略模式，在运行时动态获取具体的实现

如果想在不需要重新部署项目的情况下，新增一种扩展点的实现并且能够生效使用，有什么方式呢？

先想个简单的例子来说明一下上面说的场景，比如价格计算

```java
interface PriceCalculater {
    BigDecimal calc(GoodsDetail detail);
}
```



```java
@Service
public class DirectReducePriceCalculator implements PriceCalculater {
    
    @Resource
    private ActivityService activityService;
    
    public BigDecimal calc(GoodsDetail goods) {
        // 随便写的，只是为了稍微贴近一点实际~~~~        
        Activity activity = activityService.getDirectReductActivity(goods);
        if (activity != null) {
            return detail.getPrice().subtract(activity.getReducePrice());
        }
        return detail.getPrice();
    }
}
```

并且有一个对应的工厂类，用于获取对应的计算器

<!-- more -->

```java
@Component
public class PriceCalculaterFactory implements ApplicationContextAware {
    private ApplicationContext applicationContext;
    
    private Map<String, PriceCalculater> priceCalculaterMap;
    
    @PostConstruct
    public void init() {
        priceCalculaterMap = applicationContext.getBeansOfType(PriceCalculater.class);
    }
    
    public PriceCalculater getPriceCalculatorByName(String name) {
        return priceCalculaterMap.get(name);
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }
}
```



这时候，要添加或更新一个外部jar包中定义的bean（如新的某种计算策略）到当前应用要如何做呢？

假设定义如下

```java
@Service
public class XyPriceCalculator implements PriceCalculater {
    
    @Resource
    private ActivityService activityService;
    
    public BigDecimal calc(GoodsDetail goods) {
        // TODO 
    }

}
```

首先能想到的是，因为可能更新，这样同名的类会无法加载，所以需要一个自定义的类加载器，我们来定义一个继承`URLClassLoader`的类加载器

```java
public class CustomizeClassLoader extends URLClassLoader {

    public CustomizeClassLoader() {
        super(new URL[0]);
    }
    
    public void addFile(File file) {
        try {
            addURL(file.getCanonicalFile().toURI().toURL());
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
```

加载外部jar包中定义的class

```java
CustomizeClassLoader classLoader = new CustomizeClassLoader();
classLoader.addFile(new File("xx/yy/cc.jar"));
```

接下来，我们要想办法初始化其中的bean，因为我们加载的只是一个class，还没有初始化为Spring容器中的bean

因为外部jar包中定义的类可能还需要依赖当前项目中的bean，所以一种可行的方式就是创建一个ApplicationContext，并将当前Spring的上下文设置为新创建的ApplicationContext的父上下文，这样当前上下文中找不到的bean会到父上下文中进行查找，可以顺利的添加依赖，完成bean的创建

但是这时候还有一个问题就是我们加载外部class用的是自定义的类加载器，而当前spring相关类都是由applicationClassLoader加载的，它无法读取自定义类加载器加载的class，这时候也有一种方式，就是**spring读取class的时候默认优先是从线程上下文类加载器进行加载的**，所以我们可以把自定义类加载器设置为当前线程的上下文类加载器即可

最后一步当然就是把创建好的bean添加到工厂中即可，总体代码如下

```java
@Component
public class PriceCalculaterFactory implements ApplicationContextAware {
    private ApplicationContext applicationContext;

    private Map<String, PriceCalculater> priceCalculaterMap;

    @PostConstruct
    public void init() {
        priceCalculaterMap = applicationContext.getBeansOfType(PriceCalculater.class);
    }

    public PriceCalculater getPriceCalculatorByName(String name) {
        return priceCalculaterMap.get(name);
    }

    public void refresh() {
        // 1. 创建自定义类加载器，并加载外部jar包
        CustomizeClassLoader classLoader = new CustomizeClassLoader();
        classLoader.addFile(new File("xx/yy/cc.jar"));
        // 2. 将自定义类加载器设置为当前线程上下文类加载器
        Thread.currentThread().setContextClassLoader(classLoader);
        // 3. 创建ApplicationContext, 设置父上下文为当前应用上下文，同时使用自定义类加载器加载解析外部定义bean
        final AnnotationConfigWebApplicationContext newContext = new AnnotationConfigWebApplicationContext();
        //    设置父上下文为当前应用上下文(用于查找外部定义的bean中依赖的当前应用中的bean)
        newContext.setParent(newContext);
        //    假设外部包中定义bean所在的类路径为xxx.yyy
        newContext.scan("xxx.yyy");
        //    读取解析并创建bean
        newContext.refresh();
        // 4. 将创建的bean注册到工厂中(这里可以注意下，子上下文的getBeansOfType方法获取不到父上下文中的bean)
        Map<String, PriceCalculater> newMap = newContext.getBeansOfType(PriceCalculater.class);
        if (!newMap.isEmpty()) {
            priceCalculaterMap.putAll(newMap);
        }
    }

    @Override
    public void setApplicationContext(ApplicationContext applicationContext) throws BeansException {
        this.applicationContext = applicationContext;
    }
}
```



上面只是一个简单的例子，抛砖引玉

对于之前提到的，Spring使用当前线程上下文类加载器加载类对应源码部分如下

```java
org.springframework.context.annotation.ClassPathBeanDefinitionScanner#scan
|- org.springframework.context.annotation.ClassPathBeanDefinitionScanner#doScan
  |- ClassPathScanningCandidateComponentProvider#findCandidateComponents
    |- ClassPathScanningCandidateComponentProvider#scanCandidateComponents
Resource[] resources = getResourcePatternResolver().getResources(packageSearchPath);
      |- ClassPathScanningCandidateComponentProvider#getResourcePatternResolver
        |- new PathMatchingResourcePatternResolver()
          |- new DefaultResourceLoader()
            |- ClassUtils.getDefaultClassLoader(); 
```



```java
// ClassUtils.java
public static ClassLoader getDefaultClassLoader() {
    ClassLoader cl = null;
    try {
        // 优先使用了线程上下文类加载器进行类加载！！！
        cl = Thread.currentThread().getContextClassLoader();
    }
    catch (Throwable ex) {
        // Cannot access thread context ClassLoader - falling back...
    }
    if (cl == null) {
        // No thread context class loader -> use class loader of this class.
        cl = ClassUtils.class.getClassLoader();
        if (cl == null) {
            // getClassLoader() returning null indicates the bootstrap ClassLoader
            try {
                cl = ClassLoader.getSystemClassLoader();
            }
            catch (Throwable ex) {
            // Cannot access system ClassLoader - oh well, maybe the caller can live with null...
            }
        }
    }
    return cl;
}
```



如果有错误的地方，或者大家有更好的方案，欢迎提出指正，谢谢
