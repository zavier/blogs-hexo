---
title: spring-beans 中 Bean解析创建过程（上）
date: 2019-05-01 17:59:43
tags: [java, spring]
---



spring-beans虽然是一个很基础的包，但是它已经包括了很多的功能，我们先看下如何在只使用spring-beans包的情况下，解析并拿到xml中配置的bean实例

spring-bean.xml

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.springframework.org/schema/beans 			                http://www.springframework.org/schema/beans/spring-beans.xsd">

    <bean class="com.zavier.spring.beans.SimpleBean" id="simpleBean" />

</beans>
```

解析代码

```java
// 1.创建一个BeanFactory
DefaultListableBeanFactory beanFactory = new DefaultListableBeanFactory();
// 2.创建读取Bean定义的Reader
XmlBeanDefinitionReader beanDefinitionReader = new XmlBeanDefinitionReader(beanFactory);
// 3.使用Reader来读取指定的资源信息
ClassPathResource resource = new ClassPathResource("spring-bean.xml");
beanDefinitionReader.loadBeanDefinitions(resource);
// 4.之后就可以从工厂中正常获取对应的bean实例
SimpleBean bean = beanFactory.getBean(SimpleBean.class);
```

<!-- more -->

让我们来一步一步分析一下上面几行代码的底层的实际执行逻辑

先看一下最重要的BeanFactory实现类 `DefaultListableBeanFactory`的继承关系

![](/images/DefaultListableBeanFactory.png)

在这个图中，我们能看出其主要是实现了两个接口

- BeanFactory  - Bean的工厂类，负责创建Bean实例等
- BeanDefinitionRegistry - Bean定义的注册器，可以将Bean的定义信息注册到其中

DefaultListableBeanFactory实现后，就可以通过beanDefinitionReader读取解析xml等配置文件中的信息，将Bean的信息BeanDefinition通过registry注册，之后可以通过 beanFactory创建bean



这篇文章中我们先看一下Bean信息的读取注册过程，也就是BeanDefinitionRegistry 接口的功能实现

先看一下 `XmlBeanDefinitionReader`具体是如何解析xml文件，并将配置的bean信息注册给registry呢

XmlBeanDefinitionReader.loadBeanDefinition

​    委托给 DefaultBeanDefinitionDocumentReader.registerBeanDefinition

​        委托给 BeanDefinitionParserDelegate 负责最终的处理



而BeanDefinitionParseDelegate对于默认的标签（bean、import、alias等）和自定义的标签有不同的处理逻辑

### 一、自定义标签

```java
// 对应的方法如下，用来处理如 <mvc:annotation-driven /> 之类的其他命名空间的标签
// 这次我们先不进入细看，感兴趣的可以进入看下
delegate.parseCustomElement(root)
```



### 二、 beans默认标签（bean、import、alias等）

BeanDefinitionParserDelegate的parseBeanDefinitionElement方法，它的执行流程大体如下

1.解析bean标签中的ID和name属性，将beanName=id，并校验次beanName是否已经存在

2.解析bean标签中的class等属性，创建 AbstractBeanDefinition (Bean的定义包装类)

```java
GenericBeanDefinition bd = new GenericBeanDefinition();
bd.setBeanClass(ClassUtils.forName(className, classLoader));
```

3.解析bean标签属性(scope, lazy-init, init-method, destroy-method等)，并赋值给AbstractBeanDefinition中对应的属性

```java
// BeanDefinitionParserDelegate.parseBeanDefinitionAttributes方法
AbstractBeanDefinition bd = ...;
bd.setScope(..);
bd.setAbstract(..);
bd.setLazyInit(..);
bd.setAutowireMode(..);
bd.setDependencyCheck(..);
bd.setDependsOn(..);
bd.setAutowireCandidate(..);
bd.setPrimary(..);
bd.setInitMethodName(..);
bd.setDestroyMethodName(..);
bd.setFactoryMethodName(..);
bd.setFactoryBeanName(..);

// 同时，我们可以简单看下AbstractBeanDefinition中包含的主要属性
class AbstractBeanDefinition extends BeanMetadataAttributeAccessor
		implements BeanDefinition, Cloneable {
    private volatile Object beanClass;  // bean的实际class
    private String scope = SCOPE_DEFAULT;
    private boolean abstractFlag = false;
    private boolean lazyInit = false;
    private int autowireMode = AUTOWIRE_NO;
    private int dependencyCheck = DEPENDENCY_CHECK_NONE;
    private String[] dependsOn;
    private boolean autowireCandidate = true;
    private boolean primary = false;
    private final Map<String, AutowireCandidateQualifier> qualifiers =
    		new LinkedHashMap<String, AutowireCandidateQualifier>(0);
    private boolean nonPublicAccessAllowed = true;
    private boolean lenientConstructorResolution = true;
    private String factoryBeanName;
    private String factoryMethodName;
    private ConstructorArgumentValues constructorArgumentValues;
    private MutablePropertyValues propertyValues;
    private MethodOverrides methodOverrides = new MethodOverrides();
    private String initMethodName;
    private String destroyMethodName;
    private boolean enforceInitMethod = true;
    private boolean enforceDestroyMethod = true;
    private boolean synthetic = false;
    private int role = BeanDefinition.ROLE_APPLICATION;
    private String description;
    private Resource resource;    
}
```

4.处理bean标签中的子标签，如constructor-args, property等，并赋值给AbstractBeanDefinition中对应的属性

```java
AbstractBeanDefinition bd = ...;
bd.setConstructorArgumentValues(..);  // constructor-args
bd.setPropertyValues(..);  // property
```

5.创建BeanDefinitionHolder(对BeanDefinition的包装类，主要是包含了 alias属性)

```java
new BeanDefinitionHolder(beanDefinition, beanName, aliasesArray);

// BeanDefinitionHolder 的定义
public class BeanDefinitionHolder implements BeanMetadataElement {
    private final BeanDefinition beanDefinition;
    private final String beanName;
    private final String[] aliases;
}
```

6.最后调用BeanDefinitionReaderUtils.registerBeanDefinition注册到DefaultListableBeanFactory

```java
public static void registerBeanDefinition(
    BeanDefinitionHolder definitionHolder, BeanDefinitionRegistry registry)
    throws BeanDefinitionStoreException {

    // Register bean definition under primary name.
    String beanName = definitionHolder.getBeanName();
    registry.registerBeanDefinition(beanName, definitionHolder.getBeanDefinition());

    // Register aliases for bean name, if any.
    String[] aliases = definitionHolder.getAliases();
    if (aliases != null) {
        for (String alias : aliases) {
            registry.registerAlias(beanName, alias);
        }
    }
}

// DefaultListableBeanFactory 对应的存储结构
private final Map<String, BeanDefinition> beanDefinitionMap = new ConcurrentHashMap<>(256);
```



至此，我们就完成了一个xml文件的读取，解析并赋值给DefaultListableBeanFactory（BeanDefinitionRegistry接口的实现）的过程

之前我们说过 DefaultListableBeanFactory 主要实现的是两个接口，BeanDefinitionRegistry与 BeanFactory，现在我们只说了BeanDefinitionRegistry 读取注册Bean相关的功能，下一篇我们来接续讲解一下BeanFactory也是bean实例创建的部分，谢谢～
