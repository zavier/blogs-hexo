---
title: RestTemplate使用快速入门
date: 2024-06-03 21:40:51
tags: [spring, restTemplate, http]
---

现在对于调用外部http接口的包已经有很多了，比如 Java 原生的 HttpURLConnection，Apache的 HttpClient，Spring的 RestTemplate 以及 WebClient ，Square 的 OkHttp 以及Netflix 的 Feign，从简单到高级功能可以说是应有尽有

不过对于内部都是RPC进行交互的服务，只有一些简单的场景需要调用 HTTP 接口，考虑项目如果为为spring的项目，可以考虑直接使用 RestTemplate

<!-- more -->

这里以之前写的[费用分摊系统](https://github.com/zavier/share-expense)为例，展示一下使用 GET 和 POST 请求的方式

## GET方法

首先看下GET请求的查询项目列表接口，先看一下接口

<img src="/images/resttemplate-1.png" style="zoom:60%" />

现在开始写编写代码，首先根据返回结构定义好返回类型信息

```java
// 响应类
@Data
public class Resp<T> {
    private Integer status;
    private String errCode;
    private String msg;
    private T data;
}

// 分页结果
@Data
public class PageData<T> {
    private Integer total;
    private List<T> items;
}

// 分页list中的对象
@Data
public class ProjectData {
    private Long projectId;
    private String projectName;
    private String projectDesc;
}

// 分页结果响应
@EqualsAndHashCode(callSuper = true)
@Data
public static class ProjectPageResp extends Resp<PageData<ProjectData>> {}
```

现在可以使用 RestTemplate 发起请求，其相关的API定义如下

主要有 getForObject 和 getForEntity 两类，之间的区别就是 getForObject  只能获取返回的body部分，而 getForEntity 可以同时获取到对应的状态码、响应header信息

```java
// RestTemplate.java
public <T> T getForObject(String url, Class<T> responseType, Object... uriVariables);
public <T> T getForObject(String url, Class<T> responseType, Map<String, ?> uriVariables);
public <T> T getForObject(URI url, Class<T> responseType);

public <T> ResponseEntity<T> getForEntity(String url, Class<T> responseType, Object... uriVariables);
public <T> ResponseEntity<T> getForEntity(String url, Class<T> responseType, Map<String, ?> uriVariables);
public <T> ResponseEntity<T> getForEntity(URI url, Class<T> responseType);
```

因为分页接口有两个变量，所以可以简单使用第一个 API

```java
// 变量可以使用{variable}进行占位
String url = "http://localhost:8081/expense/project/list?page={page}&size={size}";
// ProjectPageResp 是接口响应类型，最后的 1 和 10 分别对应之前url中的变量 page 和 size
ProjectPageResp forObject = restTemplate.getForObject(url, ProjectPageResp.class, 1, 10);
```



## POST方法

这个以创建项目的接口来看一下使用方式

<img src="/images/resttemplate-2.png" style="zoom:60%" />

同样先定义好请求及响应类

```java
// 创建项目请求参数类
@Data
public class CreateProject {
    private List<String> members;
    private String projectName;
    private String projectDesc;
}

// 响应类可以直接使用之前定义好的 Resp即可
```

在发起 POST 请求前，看一下其提供的 API

```java
// RestTemplate.java
public URI postForLocation(String url, @Nullable Object request, Object... uriVariables);
public URI postForLocation(String url, @Nullable Object request, Map<String, ?> uriVariables);
public URI postForLocation(URI url, @Nullable Object request);

public <T> T postForObject(String url, @Nullable Object request, Class<T> responseType, Object... uriVariables);
public <T> T postForObject(String url, @Nullable Object request, Class<T> responseType, Map<String, ?> uriVariables);
public <T> T postForObject(URI url, @Nullable Object request, Class<T> responseType);

public <T> ResponseEntity<T> postForEntity(String url, @Nullable Object request, Class<T> responseType, Object... uriVariables);
public <T> ResponseEntity<T> postForEntity(String url, @Nullable Object request, Class<T> responseType, Map<String, ?> uriVariables);
public <T> ResponseEntity<T> postForEntity(URI url, @Nullable Object request, Class<T> responseType);
```

可以看到基本和 GET 的 API 类似，主要就是多了 postForLocation 相关的方法，这个主要用来获取 301、302状态码返回的重定向地址信息

我们这里可以使用 postForObject 即可

```java
// 创建请求类
final CreateProject createProject = new CreateProject();
createProject.setMembers(Lists.newArrayList("成员1", "成员2"));
createProject.setProjectName("测试项目");
createProject.setProjectDesc("哈哈");

// 请求获取响应结果
String url = "http://localhost:8081/expense/project/create";
final Resp resp = restTemplate.postForObject(url, createProject, Resp.class);
```



## Exchange方法

简单的方式我们直接使用之前的 GET 和 POST 方法即刻，但是有一些特殊的场景，比如有一些接口鉴权需要设置header或cookie等，则无法支持，这时候可以使用 Exchange方法

这里我们针对之前的两个方法，转换成使用 Exchange方法，同时设置cookie等信息

Exchange的方法定义如下

```java
public <T> ResponseEntity<T> exchange(String url, HttpMethod method, @Nullable HttpEntity<?> requestEntity, Class<T> responseType, Object... uriVariables);
public <T> ResponseEntity<T> exchange(String url, HttpMethod method, @Nullable HttpEntity<?> requestEntity, Class<T> responseType, Map<String, ?> uriVariables);
public <T> ResponseEntity<T> exchange(URI url, HttpMethod method, @Nullable HttpEntity<?> requestEntity, Class<T> responseType);
public <T> ResponseEntity<T> exchange(String url, HttpMethod method, @Nullable HttpEntity<?> requestEntity, ParameterizedTypeReference<T> responseType, Object... uriVariables);
public <T> ResponseEntity<T> exchange(String url, HttpMethod method, @Nullable HttpEntity<?> requestEntity, ParameterizedTypeReference<T> responseType, Map<String, ?> uriVariables);
public <T> ResponseEntity<T> exchange(URI url, HttpMethod method, @Nullable HttpEntity<?> requestEntity, ParameterizedTypeReference<T> responseType);
public <T> ResponseEntity<T> exchange(RequestEntity<?> requestEntity, Class<T> responseType);
public <T> ResponseEntity<T> exchange(RequestEntity<?> requestEntity, ParameterizedTypeReference<T> responseType);
```

下面看下使用方法

```java
// 设置请求header信息
HttpHeaders headers = new HttpHeaders();
headers.setContentType(MediaType.APPLICATION_JSON);
headers.set("Cookie", "cookie信息");
headers.set("Token", "token信息");


// GET 请求
String url = "http://localhost:8081/expense/project/list?page={page}&size={size}";
// 参数1: url,  参数2: 请求方法， 参数3:请求体(包含header等)，参数4:响应类型
ResponseEntity<ProjectPageResp> exchange = restTemplate.exchange(url, HttpMethod.GET, new HttpEntity<>(headers), ProjectPageResp.class, 1, 10);
System.out.println(exchange);


// POST 请求
// 创建请求body内容
final CreateProject createProject = new CreateProject();
createProject.setMembers(Lists.newArrayList("成员1", "成员2"));
createProject.setProjectName("测试项目");
createProject.setProjectDesc("哈哈");
// 创建POST请求体：HttpEntity(body, headers)
final HttpEntity<CreateProject> httpPostEntity = new HttpEntity<>(createProject, headers);
String url = "http://localhost:8081/expense/project/create";
// 发起请求，获取结果
final ResponseEntity<Resp> exchange1 = restTemplate.exchange(url, HttpMethod.POST, httpPostEntity, Resp.class);
```



RestTemplate 内部实际默认使用的是 JDK 的HttpURLConnection，同时也支持配置使用 Apache 的 HttpClient 以及 OkHttp3，可以按需配置使用

如使用OkHttp3, 需要添加依赖(maven)

```xml
<dependency>
    <groupId>com.squareup.okhttp3</groupId>
    <artifactId>okhttp</artifactId>
    <version>4.12.0</version>
</dependency>
```

这时可以进行RestTemplate的配置

```java
// 进行okhttp相关的配置
OkHttpClient client = new OkHttpClient.Builder()
        // 这里可以配置拦截器进行日志记录、或者对敏感数据加解密、签名等功能
        .addInterceptor(new LoggingInterceptor())
        .build();
// 构造RestTemplate
ClientHttpRequestFactory clientHttpRequestFactory = new OkHttp3ClientHttpRequestFactory(client);
final RestTemplate restTemplate = new RestTemplate(clientHttpRequestFactory);
```

使用 HttpClient  也是类似的方式～
