---
title: MyBatis插件开发使用
date: 2022-12-24 10:25:13
tags: [mybatis]
---

MyBatis允许我们在其执行过程中对特定的一些方法进行拦截代理，实现一些特定的通用功能，如分页插件或者租户插件，允许进行拦截的类及对应方法基本如下

- Executor (update, query, flushStatements, commit, rollback, getTransaction, close, isClosed)
- ParameterHandler (getParameterObject, setParameters)
- ResultSetHandler (handleResultSets, handleOutputParameters)
- StatementHandler (prepare, parameterize, batch, update, query)

<!-- more -->

这部分可以在源码中找到

```java
// Configuration.java
public ParameterHandler newParameterHandler(MappedStatement mappedStatement, Object parameterObject, BoundSql boundSql) {
    ParameterHandler parameterHandler = mappedStatement.getLang().createParameterHandler(mappedStatement, parameterObject, boundSql);
    // 对类进行代理拦截
    parameterHandler = (ParameterHandler) interceptorChain.pluginAll(parameterHandler);
    return parameterHandler;
}

public ResultSetHandler newResultSetHandler(Executor executor, MappedStatement mappedStatement, RowBounds rowBounds, ParameterHandler parameterHandler,
                                            ResultHandler resultHandler, BoundSql boundSql) {
    ResultSetHandler resultSetHandler = new DefaultResultSetHandler(executor, mappedStatement, parameterHandler, resultHandler, boundSql, rowBounds);
    // 对类进行代理拦截
    resultSetHandler = (ResultSetHandler) interceptorChain.pluginAll(resultSetHandler);
    return resultSetHandler;
}

public StatementHandler newStatementHandler(Executor executor, MappedStatement mappedStatement, Object parameterObject, RowBounds rowBounds, ResultHandler resultHandler, BoundSql boundSql) {
    StatementHandler statementHandler = new RoutingStatementHandler(executor, mappedStatement, parameterObject, rowBounds, resultHandler, boundSql);
    // 对类进行代理拦截
    statementHandler = (StatementHandler) interceptorChain.pluginAll(statementHandler);
    return statementHandler;
}

public Executor newExecutor(Transaction transaction, ExecutorType executorType) {
    executorType = executorType == null ? defaultExecutorType : executorType;
    Executor executor;
    if (ExecutorType.BATCH == executorType) {
        executor = new BatchExecutor(this, transaction);
    } else if (ExecutorType.REUSE == executorType) {
        executor = new ReuseExecutor(this, transaction);
    } else {
        executor = new SimpleExecutor(this, transaction);
    }
    if (cacheEnabled) {
        executor = new CachingExecutor(executor);
    }
    // 对类进行代理拦截
    executor = (Executor) interceptorChain.pluginAll(executor);
    return executor;
}
```

要想更好的使用MyBatis的插件功能，首先需要对拦截到的类和方法进行了解，以一次查询为例我们看一下相关流程

<img src="/images/mybatis-query.jpg" style="zoom:60%" />

Executor: Executor是SqlSession中执行功能使用到的类，如查询时，首先从Configuration或获取MappedStatement（可以认为是对应的mapper.xml中的 SELECT节点信息），之后和具体的参数值一起传递给Executor的query方法使用

```java
// Executor.java
<E> List<E> query(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler) throws SQLException;
```

StatementHandler: Executor具体执行时，默认会使用StatementHandler的prepare对要执行的SQL创建预编译的Statement，之后使用parameterize设置参数

```java
// SimpleExecutor.java
public <E> List<E> doQuery(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler, BoundSql boundSql) throws SQLException {
    Statement stmt = null;
    try {
        Configuration configuration = ms.getConfiguration();
        StatementHandler handler = configuration.newStatementHandler(wrapper, ms, parameter, rowBounds, resultHandler, boundSql);
        stmt = prepareStatement(handler, ms.getStatementLog());
        return handler.query(stmt, resultHandler);
    } finally {
        closeStatement(stmt);
    }
}

private Statement prepareStatement(StatementHandler handler, Log statementLog) throws SQLException {
    Statement stmt;
    Connection connection = getConnection(statementLog);
    // 预编译
    stmt = handler.prepare(connection, transaction.getTimeout());
    // 设置参数
    handler.parameterize(stmt);
    return stmt;
}
```

在StatementHandler执行parameterize，默认会使用ParameterHandler#setParameters来对预编译结果继续进行参数设置

之后再调用StatementHandler#query方法来进行查询，最后使用ResultSetHandler#handleResultSets对查询结果进行处理

分析了流程之后，我们就可以根据自己的需求在指定方法上面进行拦截处理，如我们想要统一在数据库层面设置某一个字段值(如创建人信息)，那么就可以拦截Executor#update方法，对其中的参数进行修改赋值

这里我们以一个最简单的分页插件功能为例，看一下如何实现使用一个插件

一般分页我们可以拦截Executor相关的方法，但是这里为了简单，我们就处理StatementHandler#prepare方法，在进行预编译sql前，将sql进行修改，这样执行的就是分页后的sql了

```java
// 需要添加拦截器注解
@Intercepts({
        // 这里需要声明拦截的类，方法名称、参数信息
        @Signature(type = StatementHandler.class, method = "prepare", args = {Connection.class, Integer.class})
})
public class DemoInterceptor implements Interceptor {
    private static ThreadLocal<Page> pageThreadLocal = new ThreadLocal<>();

    public static void page(Integer page, Integer size) {
        final Page p = new Page();
        p.setPage(page);
        p.setSize(size);
        pageThreadLocal.set(p);
    }

    @Override
    public Object intercept(Invocation invocation) throws Throwable {
        final Page page = pageThreadLocal.get();
        if (page == null) {
            return invocation.proceed();
        }

        try {
            final int offset = (page.getPage() - 1) * page.getSize();

            final StatementHandler statementHandler = (StatementHandler) invocation.getTarget();
            final BoundSql boundSql = statementHandler.getBoundSql();
            final String sql = boundSql.getSql();
            // 修改SQL数据后重新赋值回去
            String newSql = sql + " limit " + page.getSize() + " offset " + offset;
            final MetaObject metaObject = SystemMetaObject.forObject(boundSql);
            metaObject.setValue("sql", newSql);

        } finally {
            pageThreadLocal.remove();
        }

        return invocation.proceed();
    }

    static class Page {
        private Integer page;
        private Integer size;

        public Integer getPage() {
            return page;
        }

        public void setPage(Integer page) {
            this.page = page;
        }

        public Integer getSize() {
            return size;
        }

        public void setSize(Integer size) {
            this.size = size;
        }
    }
}
```

之后在mybatis的配置文件中配置上此插件

```xml
<plugins>
    <plugin interceptor="com.zavier.demo.interceptor.DemoInterceptor" />
</plugins>
```

再执行查询前，如果设置了分页信息则最终SQL会有相关的分页信息