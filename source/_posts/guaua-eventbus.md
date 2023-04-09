---
title: Guava EventBus
date: 2020-10-01 21:35:12
tags: [java, guava]
---

在我们日常开发中经常有这种类型的场景：

1. 新建用户后，需要进行一些操作，如发送优惠券等（和创建用户本身无关的操作）
2. 数据变更时，对应的展示表格等信息需要进行对应的更新

即当一个对象的状态发生改变时，所有依赖于它的对象都得到通知并被自动更新

观察者模式（发布-订阅）就是这种情况下的一种解决方案，使用这种方式可以让解耦发布者和订阅者，互相不需要知道对方，之前一篇文档中简单介绍过[Spring中的事件使用](/2019/11/30/practical-spring-function/)，这次介绍一种非Spring环境下Guava提供的[EventBus](https://github.com/google/guava/wiki/EventBusExplained)的使用



<!-- more -->



### 使用

下面简单介绍一下EventBus的使用，使用起来其实是比较简单的，代码如下

**创建事件类**

```java
// 一个简单的普通类
public class UserCreateEvent {
  // 定义需要的属性
}
```

**定义监听者**

```java
// 定义一个发送短信通知的服务
public class SendSmsService {
    // 使用 @Subscribe 标识此方法用来处理事件消息
    @Subscribe
    // 方法参数只能为1个，且为对应要处理的事件类
    public void listen(UserCreateEvent event) {
        // todo send sms
        System.out.println(this.getClass().getSimpleName() + "-" + event);
    }
}

// 定义一个发送优惠券的服务
public class SendCouponService {
    @Subscribe
    public void listen(UserCreateEvent event) {
        // todo send coupon
        System.out.println(this.getClass().getSimpleName() + "-" + event);
    }
}
```

**初始化EventBus**

```java
// 初始化EventBus(异步处理需使用AsyncEventBus), 注册监听者
EventBus eventBus = new EventBus();
eventBus.register(new SendCouponService());
eventBus.register(new SendSmsService());
```

**事件触发**

```java
// 直接使用EventBus的post发送事件即可
eventBus.post(new UserCreateEvent());
```



### 原理

使用其实挺简单的，下面我们可以想下它是怎么实现的

解析：首先在register注册监听者时解析对应监听类，获取@Subscribe注解方法及对应参数中的监听类信息

注册：需要维护一个注册表，记录被监听事件及对应的处理方法集合

派发执行：当调用EventBus发送事件时，可能根据同步或异步方式进行消息分发



**解析注册**

Guava的解析注册的类为SubscriberRegistry

```java
// 总的维护的订阅信息表
private final ConcurrentMap<Class<?>, CopyOnWriteArraySet<Subscriber>> subscribers =
      Maps.newConcurrentMap();

void register(Object listener) {
    // 获取监听者监听的事件类及对应的监听方法信息
    Multimap<Class<?>, Subscriber> listenerMethods = findAllSubscribers(listener);
    for (Entry<Class<?>, Collection<Subscriber>> entry : listenerMethods.asMap().entrySet())     {
        Class<?> eventType = entry.getKey();
        Collection<Subscriber> eventMethodsInListener = entry.getValue();
        // 使用CopyOnWriteArraySet在添加的同时可以不影响读（快照读）
        CopyOnWriteArraySet<Subscriber> eventSubscribers = subscribers.get(eventType);
        if (eventSubscribers == null) {
          CopyOnWriteArraySet<Subscriber> newSet = new CopyOnWriteArraySet<>();
          eventSubscribers =
              MoreObjects.firstNonNull(subscribers.putIfAbsent(eventType, newSet), newSet);
        }
        eventSubscribers.addAll(eventMethodsInListener);
    }
}

private Multimap<Class<?>, Subscriber> findAllSubscribers(Object listener) {
    Multimap<Class<?>, Subscriber> methodsInListener = HashMultimap.create();
    Class<?> clazz = listener.getClass();
    // 获取 @Subscribe注解的所有方法
    for (Method method : getAnnotatedMethods(clazz)) {
        // 第一个参数为监听的事件
        Class<?>[] parameterTypes = method.getParameterTypes();
        Class<?> eventType = parameterTypes[0];
        // 记录事件的监听者信息，包括实例类及对应的方法（后面可以反射调用）
        methodsInListener.put(eventType, Subscriber.create(bus, listener, method));
    }
    return methodsInListener;
}
```



**消息派发**

```java
public void post(Object event) {
    // 获取事件的所有订阅者
    Iterator<Subscriber> eventSubscribers = subscribers.getSubscribers(event);
    if (eventSubscribers.hasNext()) {
        // 消息派发
        dispatcher.dispatch(event, eventSubscribers);
    } else if (!(event instanceof DeadEvent)) {
        // 没有订阅者时发送DeadEvent事件
        post(new DeadEvent(this, event));
    }
}
```

消息派发目前提供了三种实现

- PerThreadQueuedDispatcher   每个线程一个队列派发
- LegacyAsyncDispatcher   异步派发使用
- ImmediateDispatcher 立即派发(无队列)

下面依次看下

```java
// PerThreadQueuedDispatcher（同步EventBus默认使用）
// 同步使用时不同线程发送事件处理不会互相影响
private static final class PerThreadQueuedDispatcher extends Dispatcher {
    // 使用ThreadLocal，一个线程一个队列
    private final ThreadLocal<Queue<Event>> queue =
            new ThreadLocal<Queue<Event>>() {
                @Override
                protected Queue<Event> initialValue() {
                    return Queues.newArrayDeque();
                }
            };

    private final ThreadLocal<Boolean> dispatching =
            new ThreadLocal<Boolean>() {
                @Override
                protected Boolean initialValue() {
                    return false;
                }
            };

    @Override
    void dispatch(Object event, Iterator<Subscriber> subscribers) {
        // 先获取当前线程的队列
        Queue<Event> queueForThread = queue.get();
        // 将每个事件和所有的订阅者作为一个节点入队
        queueForThread.offer(new Event(event, subscribers));

        if (!dispatching.get()) {
            dispatching.set(true);
            try {
                Event nextEvent;
                while ((nextEvent = queueForThread.poll()) != null) {
                    while (nextEvent.subscribers.hasNext()) {
                        // 派发事件消息
                        nextEvent.subscribers.next().dispatchEvent(nextEvent.event);
                    }
                }
            } finally {
                dispatching.remove();
                queue.remove();
            }
        }
    }
    
}
```



```java
// LegacyAsyncDispatcher(异步AsyncEventBus默认使用)
private static final class LegacyAsyncDispatcher extends Dispatcher {
  // 全局队列
    private final ConcurrentLinkedQueue<Dispatcher.LegacyAsyncDispatcher.EventWithSubscriber> queue =
            Queues.newConcurrentLinkedQueue();

    @Override
    void dispatch(Object event, Iterator<Subscriber> subscribers) {
        while (subscribers.hasNext()) {
            // 一个事件和一个订阅者作为一个节点入队
            queue.add(new Dispatcher.LegacyAsyncDispatcher.EventWithSubscriber(event, subscribers.next()));
        }

        Dispatcher.LegacyAsyncDispatcher.EventWithSubscriber e;
        while ((e = queue.poll()) != null) {
            e.subscriber.dispatchEvent(e.event);
        }
    }
    
}
```



```java
// ImmediateDispatcher
private static final class ImmediateDispatcher extends Dispatcher {
    private static final ImmediateDispatcher INSTANCE = new ImmediateDispatcher();

    @Override
    void dispatch(Object event, Iterator<Subscriber> subscribers) {
        checkNotNull(event);
        while (subscribers.hasNext()) {
            subscribers.next().dispatchEvent(event);
        }
    }
}
```



最后我们看下dispatchEvent方法

```java
final void dispatchEvent(final Object event) {
    // 同步和异步在构造时使用不同的executor
    executor.execute(
            new Runnable() {
                @Override
                public void run() {
                    try {
                        invokeSubscriberMethod(event);
                    } catch (InvocationTargetException e) {
                        bus.handleSubscriberException(e.getCause(), context(event));
                    }
                }
            });
}

// 同步Executor实现如下
enum DirectExecutor implements Executor {
    INSTANCE;

    @Override
    public void execute(Runnable command) {
        // 同步调用
        command.run();
    }
}
```





