---
title: spring循环依赖分析
date: 2022-01-08 18:22:58
tags: [java, spring]
---

我们在使用Spring开发的时候，可能有的时候不小心就会写出来循环依赖，但是大部分情况下都能正常运行，不需要我们特别关注，这是因为Spring进行了相关的处理等

循环依赖的处理还依赖于bean的作用范围，bean的注入方式等，这里我们就以单例模式，属性注入的方式来分析一下Spring对于循环依赖的处理

<!-- more -->

我们以如下场景为例来进行分析，有ServiceA和ServiceB两个Bean, 它们互相依赖

```java
@Service
public class ServiceA {
    @Resource
    private ServiceB serviceB;
}

@Service
public class ServiceB {
    @Resource
    private ServiceA serviceA;
}
```

先说结论，然后再进行操作和分析，spring的创建过程大致如下

<img src="/images/bean-create.png" style="zoom:50%" />

处理循环依赖的关键就是其中的注册单例Bean工厂（singletonFactories）相关功能

1. 首次获取ServiceA这个bean时，单例工厂中不存在，这时候会进行实例化并将结果添加到bean工厂中
2. 处理ServiceA中属性注入的ServiceB，这时候会从bean工厂中获取ServiceB的bean
3. 单例工厂中不存在的ServiceB, 这时候会进行实例化ServiceB并将结果添加到bean工厂中
4. 处理ServiceB中属性注入的ServiceA，这时候会从bean工厂中获取ServiceA的bean
5. 发现单例工厂中存在ServiceA对应的工厂，从工厂获取bean返回，ServiceB中属性注入完成
6. SeriveA中属性注入完成，循环依赖处理完成

## 源码分析

因为之前已经初步分析过Bean的创建过程，所以这次我们只关注相关的代码，针对上述过程看一下源码

### Bean获取过程

```java
// org.springframework.beans.factory.support.AbstractBeanFactory

protected <T> T doGetBean(String name, Class<T> requiredType, Object[] args, boolean typeCheckOnly) throws BeansException {

    final String beanName = transformedBeanName(name);
    Object bean;

    // 检查单例工厂中是否存在，存在的获取并返回
    Object sharedInstance = getSingleton(beanName);
    if (sharedInstance != null && args == null) {
        bean = getObjectForBeanInstance(sharedInstance, name, beanName, null);
    }
}

public Object getSingleton(String beanName) {
    return getSingleton(beanName, true);
}

// 这个是处理循环依赖的关键
protected Object getSingleton(String beanName, boolean allowEarlyReference) {
    Object singletonObject = this.singletonObjects.get(beanName);
    if (singletonObject == null && isSingletonCurrentlyInCreation(beanName)) {
        synchronized (this.singletonObjects) {
            singletonObject = this.earlySingletonObjects.get(beanName);
            if (singletonObject == null && allowEarlyReference) {
                // 获取对应工厂，存在的获取实例返回
                ObjectFactory<?> singletonFactory = this.singletonFactories.get(beanName);
                if (singletonFactory != null) {
                    singletonObject = singletonFactory.getObject();
                    this.earlySingletonObjects.put(beanName, singletonObject);
                    this.singletonFactories.remove(beanName);
                }
            }
        }
    }
    return singletonObject;
}
```

### Bean创建过程

```java
// org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory
// 为了简化过程，对源码进行了部分删减
protected Object doCreateBean(String beanName, RootBeanDefinition mbd, Object[] args)
        throws BeanCreationException {

    // 反射实例化Bean
    BeanWrapper instanceWrapper = createBeanInstance(beanName, mbd, args);
    final Object bean = instanceWrapper.getWrappedInstance();

    // 单例并且运行循环依赖时，将其注册添加到单例bean工厂中
    boolean earlySingletonExposure = (mbd.isSingleton() && this.allowCircularReferences &&
            isSingletonCurrentlyInCreation(beanName));
    if (earlySingletonExposure) {
        addSingletonFactory(beanName, () -> getEarlyBeanReference(beanName, mbd, bean));
    }

    Object exposedObject = bean;
    try {
        // Bean中属性等处理（包括属性注入依赖的其他Bean）
        populateBean(beanName, mbd, instanceWrapper);
        exposedObject = initializeBean(beanName, exposedObject, mbd);
    }
    catch (Throwable ex) {
        // 忽略异常处理
    }

    // 创建结束并返回结果
    return exposedObject;
}

// 注册单例Bean工厂
protected void addSingletonFactory(String beanName, ObjectFactory<?> singletonFactory) {
    Assert.notNull(singletonFactory, "Singleton factory must not be null");
    synchronized (this.singletonObjects) {
        if (!this.singletonObjects.containsKey(beanName)) {
            // 添加到 singletonFactories
            this.singletonFactories.put(beanName, singletonFactory);
            this.earlySingletonObjects.remove(beanName);
            this.registeredSingletons.add(beanName);
        }
    }
}
```

### Bean中属性注入依赖处理

这里需要提一下，Bean中属性注入的依赖，是由以下两个BeanPostProcessor来分别进行处理的

org.springframework.context.annotation.CommonAnnotationBeanPostProcessor(处理@Resource)

org.springframework.beans.factory.annotation.AutowiredAnnotationBeanPostProcessor(处理@Autowired)

处理底层是一样的，这次我们就以CommonAnnotationBeanPostProcessor为例进行分析

```java
// org.springframework.beans.factory.support.AbstractAutowireCapableBeanFactory
// populateBean(beanName, mbd, instanceWrapper);

// 方法中代码较多，进行了大量删减，我们只关注一些相关部分
protected void populateBean(String beanName, RootBeanDefinition mbd, BeanWrapper bw) {
    boolean hasInstAwareBpps = hasInstantiationAwareBeanPostProcessors();
    PropertyDescriptor[] filteredPds = null;
    if (hasInstAwareBpps) {
        // 获取所有BeanPostProcessor
        for (BeanPostProcessor bp : getBeanPostProcessors()) {
            if (bp instanceof InstantiationAwareBeanPostProcessor) {
                InstantiationAwareBeanPostProcessor ibp = (InstantiationAwareBeanPostProcessor) bp;
                // 这里会有 CommonAnnotationBeanPostProcessor 进行处理，注入依赖Bean
                PropertyValues pvsToUse = ibp.postProcessProperties(pvs, bw.getWrappedInstance(), beanName);
            }
        }
    }
}
```



```java
// org.springframework.context.annotation.CommonAnnotationBeanPostProcessor

public PropertyValues postProcessProperties(PropertyValues pvs, Object bean, String beanName) {
    // 这里会获取有@Resource注解的属性或方法，此次就不进入细看了
    InjectionMetadata metadata = findResourceMetadata(beanName, bean.getClass(), pvs);
    try {
        // 我们关注一下这个方法
        metadata.inject(bean, beanName, pvs);
    }
    catch (Throwable ex) {
        // 忽略异常处理
    }
    return pvs;
}
```



```java
// org.springframework.beans.factory.annotation.InjectionMetadata

public void inject(Object target, String beanName, PropertyValues pvs) throws Throwable {
    Collection<InjectionMetadata.InjectedElement> checkedElements = this.checkedElements;
    Collection<InjectionMetadata.InjectedElement> elementsToIterate =
            (checkedElements != null ? checkedElements : this.injectedElements);
    if (!elementsToIterate.isEmpty()) {
        for (InjectionMetadata.InjectedElement element : elementsToIterate) {
            // 继续跟进这个方法
            element.inject(target, beanName, pvs);
        }
    }
}

// org.springframework.beans.factory.annotation.InjectionMetadata.InjectedElement
protected void inject(Object target, @Nullable String requestingBeanName, @Nullable PropertyValues pvs) throws Throwable {

    // 属性处理
    if (this.isField) {
        Field field = (Field) this.member;
        ReflectionUtils.makeAccessible(field);
        // 看一下getResourceToInject这个方法，会从BeanFactory获取/创建对应的Bean后进行赋值
        field.set(target, getResourceToInject(target, requestingBeanName));
    }
    else {
        if (checkPropertySkipping(pvs)) {
            return;
        }
        try {
            // 方法处理
            Method method = (Method) this.member;
            ReflectionUtils.makeAccessible(method);
            method.invoke(target, getResourceToInject(target, requestingBeanName));
        }
        catch (InvocationTargetException ex) {
            throw ex.getTargetException();
        }
    }
}
```



getResourceToInject会调用到CommonAnnotationBeanPostProcessor.ResourceElement中的对应方法

```java
protected Object getResourceToInject(Object target, @Nullable String requestingBeanName) {
    // 没有添加@Lazy注解等时会调用 getResource 方法
    return (this.lazyLookup ? buildLazyResourceProxy(this, requestingBeanName) :
            getResource(this, requestingBeanName));
}

// org.springframework.context.annotation.CommonAnnotationBeanPostProcessor#getResource
protected Object getResource(CommonAnnotationBeanPostProcessor.LookupElement element, String requestingBeanName) throws NoSuchBeanDefinitionException {
    return autowireResource(this.resourceFactory, element, requestingBeanName);
}

protected Object autowireResource(BeanFactory factory, CommonAnnotationBeanPostProcessor.LookupElement element, String requestingBeanName)
        throws NoSuchBeanDefinitionException {

    Object resource;
    Set<String> autowiredBeanNames;
    String name = element.name;

    if (this.fallbackToDefaultTypeMatch && element.isDefaultName &&
            factory instanceof AutowireCapableBeanFactory && !factory.containsBean(name)) {
        // 先忽略，有兴趣可以看下对应代码
    }
    else {
        // 会从BeanFactory中获取对应属性的Bean, 这样又可以走开头的流程
        resource = factory.getBean(name, element.lookupType);
        autowiredBeanNames = Collections.singleton(name);
    }

    return resource;
}
```

以上就是一个简单的循环依赖处理过程



