---
title: 如何优雅的遍历表中数据
tags:
  - java
date: 2023-08-30 00:04:32
---


日常工作中，有一些功能如状态更新等需要遍历表中数据，如果数据量比较少的情况下，我们可以正常的使用数据库如mysql提供的limit和offset来实现分页的功能，但是如果数据量比较大，这时候就会有深分页的问题，产生慢SQL, 为了解决这个问题，一种实现方式就是通过主键ID+查询条件来过滤数据，使用类似如下语句

```sql
SELECT * FROM task WHERE id > $minId AND status = 1 ORDER BY id LIMIT 200
```

如果有其他条件导致需要扫描很大的行数才能扫描到的话，可能还需要限制id上限

```sql
SELECT * FROM task WHERE id > $minId AND id < $maxId AND status = 1 ORDER BY id LIMIT 200
```


之后每次使用查询的最大值更新变量minId，直到查询不出数据为止，具体对应到Java代码中大致如下：

```java
public class TaskStatusUpdater {
    // 执行入口
    public void execute() {
        int limit = 200;
        int minId = 0;
        
        while (true) {
            // 查询
            List<Task> tasks = taskDao.listByMinId(minId, limit);
            if (CollectionUtils.isEmpty(tasks)) {
                break;
            }
            // 更新查询参数, 获取查询到的最大的ID
            minId = tasks.stream()
                    .max(Comparator.comparing(Task::getId))
                    .map(Task::getId)
                    .get();
            for (Task task : tasks) {
                // 处理
                operateTask(task);
            }
        }
    }
    
    private void operateTask(Task task) {
        // 进行业务逻辑处理
    }
}
```

这里可以看到，执行方法中大部分都是一些业务无关的控制代码，如果有不同的处理逻辑需要遍历，那么都要复制一下这一大坨的控制代码，是否有更好的写法呢？

<!-- more -->

### Consumer

首先想到的就是使用java8提供的函数接口-Consumer, 这时候我们可以将代码修改如下，将处理逻辑作为参数传递进方法，这样不同的处理逻辑，都可以复用这个方法

```java
// 将消费逻辑包装成Consumer传递进来
public void consumeAllData(Consumer<Task> taskConsumer) {
    int limit = 200;
    int minId = 0;

    while (true) {
        // 查询
        List<Task> tasks = taskDao.listByMinId(minId, limit);
        if (CollectionUtils.isEmpty(tasks)) {
            break;
        }
        // 更新查询参数
        minId = tasks.stream()
                .max(Comparator.comparing(Task::getId))
                .map(Task::getId)
                .get();

        for (Task task : tasks) {
            taskConsumer.accept(task);
        }
    }
}

// 使用代码如下
consumeAllData(task -> {
    // 逻辑处理1
});

consumeAllData(task -> {
    // 逻辑处理2
});

```

### Iterator/Iterable

那么除了使用Consumer这个函数接口，是否还有其他的方式呢？那就是使用Iterable接口，这里我们将代码修改如下

```java
@Component
public class TaskIterable implements Iterable<Task> {
    
    @Resource
    private TaskDao taskDao;
    
    @NotNull
    @Override
    public Iterator<Task> iterator() {
        return new TaskIterator(taskDao);
    }

    static class TaskIterator implements Iterator<Task> {
        private TaskDao taskDao;
        
        private int minId = 0;
        private int limit = 200;
        
        private List<Task> currentDataList = new ArrayList<>(limit);
        private int currentIndex = 0;

        public TaskIterator(TaskDao taskDao) {
            this.taskDao = taskDao;
            fetchNextPage();
        }
        
        private void fetchNextPage() {
            currentDataList = this.taskDao.listByMinId(minId, limit);
            if (CollectionUtils.isNotEmpty(currentDataList)) {
                minId = maxId(currentDataList);
            }
            currentIndex = 0;
        }

        @Override
        public boolean hasNext() {
            if (currentIndex >= CollectionUtils.size(currentDataList)) {
                fetchNextPage();
            }
            return currentIndex < CollectionUtils.size(currentDataList);
        }

        @Override
        public Task next() {
            if (!hasNext()) {
                throw new NoSuchElementException();
            }
            return currentDataList.get(currentIndex++);
        }

        private int maxId(List<Task> taskList) {
            return currentDataList.stream()
                    .max(Comparator.comparing(Task::getId))
                    .map(Task::getId)
                    .get();
        }
    }
}
```

这个相比之前的方式代码量有所上升，但是我们来看一下使用的方式

```java
@Service
public class TaskService {

    @Resource
    private TaskIterable taskIterable;
    
    public void execute() {
        // 直接遍历处理
        for (Task task : taskIterable) {
            
        }
    }

    public void otherExecute() {
        // 直接遍历处理
        for (Task task : taskIterable) {

        }
    }
}
```

这里可以看到，使用起来非常的简单，直接通过spring注入后，使用foreach语法直接进行遍历即可，不需要关注具体的数据量，而且不同的业务逻辑也可以直接使用

### Stream

如果喜欢Stream，也可以将上面的Iterator换成Stream的方式

```java
// 将Iterator 转换成 Stream进行处理使用
public Stream<Task> taskStream() {
    final Iterator<Task> iterator = taskIterable.iterator();
    return StreamSupport.stream(Spliterators.spliteratorUnknownSize(
            iterator,
            Spliterator.ORDERED | Spliterator.IMMUTABLE), false);
}
```



以上就是实现的大致思路，抛砖引玉～
