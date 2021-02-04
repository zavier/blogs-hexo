---
title: SpringMVC自定义参数解析
date: 2021-02-01 23:18:45
tags: [java, spring]
---

我们日常开发过程中，入参出参基本都是与后端对应的类结构完全一致，SpringMVC自动帮我们处理了参数转换的过程，GET 和 POST 的几种常见传参方式如下
```Java
// HTTP请求参数名需要与属性名userName相同
@GetMapping("/listUser")
public List<User> listUser(String userName) {
    return new ArrayList<>();
}

@GetMapping("/listUser")
// HTTP请求参数名需要与注解中的名称username相同相同
public List<User> listUser1(@RequestParam("username") String userName) {
    return new ArrayList<>();
}

@GetMapping("/listUser")
// 参数太多则可以使用类接收，url中的参数会自动转化赋值到SearchUserParam类中的同名属性上
public List<User> listUser2(SearchUserParam searchUserParam) {
    return new ArrayList<>();
}


// POST方式基本同上，post body中的json串会被反序列化到对应的参数user类
@PostMapping("/save")
public Long save(@RequestBody User user) {
    return 1L;
}
```
上面的几种用法基本能满足我们大部分的需求，但是仍有一些特殊情况无法满足

<!-- more -->

## 使用

先来看下GET方法，入参太多时我们会定义类，但是类中的属性必须是和参数名一致，也不能进行嵌套，不然就无法转换，比如下面这种定义

```Java
public class SearchUserParam {
    // 基本信息查询
    private Integer age;
    private String name;
    // 假设我们能支持动态的一些属性查询支持，但是又不想每次专门修改结构，所以定义一个扩展的map
    private Map<String, String> ext;
}
```
对于上面的扩展参数，如果有一天我们需要支持根据地区进行查询，对于HTTP GET请求中的此次增加的入参如regionId=100这种情况，后端就会接收不到这个参数

一种解决方法当然是我们可以通过修改类结构增加参数来处理，这里主要来说说如果不修改类结构我们如何处理这种情况

这里就需要用到 SpringMVC 提供的 HandlerMethodArgumentResolver 类，所有的参数处理都是这个接口的实现，我们可以利用它来自定义我们的参数解析实现，如

```Java
@Component
public class SearchUserHandlerMethodArgumentResolver implements HandlerMethodArgumentResolver {

    private Set<String> supportParams = new HashSet<>();

    @PostConstruct
    public void init() {
        supportParams.add("name");
        supportParams.add("age");
    }

    // 设置支持解析的参数类型
    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.getParameterType() == SearchUserParam.class;
    }

    // 进行http请求参数的解析转换
    @Override
    public Object resolveArgument(MethodParameter parameter,
            ModelAndViewContainer mavContainer,
            NativeWebRequest webRequest,
            WebDataBinderFactory binderFactory) throws Exception {
        Map<String, Object> result = new HashMap<>();
        Iterator<String> parameterNames = webRequest.getParameterNames();
        Map<String, Object> extMap = new HashMap<>();
        while (parameterNames.hasNext()) {
            String paramName = parameterNames.next();
            if (supportParams.contains(paramName)) {
                result.put(paramName, webRequest.getParameter(paramName));
            } else {
                extMap.put(paramName, webRequest.getParameter(paramName));
            }
        }
        result.put("ext", extMap);
        return JSON.parseObject(result, SearchUserParam.class);
    }
}
```

Spring中的 PageableHandlerMethodArgumentResolver 也是利用了这个原理，会将请求参数中的分页参数填充到请求参数接收类 Pageable 中，如：

```Java
public Page<User> pageUsers(Pageable pageable, QueryUser query) {
    // 注册了 PageableHandlerMethodArgumentResolver 后， 请求url中的page、size参数会自动填充到 pageable 对应的实例中
}
```

我们可以利用这个特性在接收参数中定义一些需要用到的类，然后通过参数解析器进行添加，如用户信息等


上面说的是对于 GET 请求，接下来看下 POST 请求的处理，POST请求我们一般都是使用 json 这种格式作为入参和出参，而 SpringMVC 默认使用 jackson 进行响应的序列化和反序列化

所以 POST 请求的处理我们直接借助于 jackson 提供的方法即可，通过实现 JsonSerializer 或 JsonDeserializer 来实现对应属性的序列化与反序列化，在借由 SpringMVC 提供的 @JsonComponent 注解等方式进行设置即可，下面举一个简单的例子

```Java
@JsonComponent
public class UserCodec {

    public static class UserSerializer extends JsonSerializer<User> {
        @Override
        public void serialize(User user, JsonGenerator gen, SerializerProvider serializers) throws IOException {
            gen.writeStartObject();
            gen.writeStringField("user-name", user.getName());
            gen.writeNumberField("user-age", user.getAge());
            gen.writeEndObject();
        }
    }

    public static class UserDeserializer extends JsonDeserializer<User> {

        @Override
        public User deserialize(JsonParser p, DeserializationContext ctxt) throws IOException, JsonProcessingException {
            JsonNode node = p.getCodec().readTree(p);
            User user = new User();
            user.setName(node.get("user-name").asText());
            IntNode ageNode = (IntNode) node.get("user-age");
            user.setAge(ageNode.intValue());
            return user;
        }
    }
}
```
之后在对应类上面添加注解
```Java
@Data
@JsonSerialize(using = UserSerializer.class)
@JsonDeserialize(using = UserDeserializer.class)
public class User {
    private String name;
    private Integer age;
}

```
这样就实现了自定义的序列化与反序列化，当然我们也可以根据自己的实际需求实现更复杂的转换



## 原理

这个参数解析的原理比较简单，主要就是有一个参数解析器链，以类似责任链的方式进行处理，哪个解析器能处理就进行对应的处理，下面我们具体看下

SpringMVC主要依靠 HandlerMapping 和 HandlerAdapter 来实现路由到方法的映射和方法调用的实现, HandlerMapping 用来处理请求和 Controller 中的方法映射关系及匹配，而 HandlerAdapter 则是用来在匹配到方法后进行实际的方法调用，包括其中的参数处理(使用 HandlerMethodArgumentResolver)
这里我们主要看下最常用的 RequestMappingHandlerAdapter的处理过程

```Java
public class RequestMappingHandlerAdapter extends AbstractHandlerMethodAdapter
        implements BeanFactoryAware, InitializingBean {

    // 初始化过程中会注册所有的参数解析器
    @Override
    public void afterPropertiesSet() {
        initControllerAdviceCache();

        if (this.argumentResolvers == null) {
            List<HandlerMethodArgumentResolver> resolvers = getDefaultArgumentResolvers();
            this.argumentResolvers = new HandlerMethodArgumentResolverComposite().addResolvers(resolvers);
        }
        if (this.initBinderArgumentResolvers == null) {
            List<HandlerMethodArgumentResolver> resolvers = getDefaultInitBinderArgumentResolvers();
            this.initBinderArgumentResolvers = new HandlerMethodArgumentResolverComposite().addResolvers(resolvers);
        }
        if (this.returnValueHandlers == null) {
            List<HandlerMethodReturnValueHandler> handlers = getDefaultReturnValueHandlers();
            this.returnValueHandlers = new HandlerMethodReturnValueHandlerComposite().addHandlers(handlers);
        }
    }

    // 获取参数解析器
    private List<HandlerMethodArgumentResolver> getDefaultArgumentResolvers() {
        List<HandlerMethodArgumentResolver> resolvers = new ArrayList<>(30);

        // 基于参数注解的参数解析器
        resolvers.add(new RequestParamMethodArgumentResolver(getBeanFactory(), false));
        resolvers.add(new RequestParamMapMethodArgumentResolver());
        resolvers.add(new PathVariableMethodArgumentResolver());
        resolvers.add(new PathVariableMapMethodArgumentResolver());
        resolvers.add(new MatrixVariableMethodArgumentResolver());
        resolvers.add(new MatrixVariableMapMethodArgumentResolver());
        resolvers.add(new ServletModelAttributeMethodProcessor(false));
        resolvers.add(new RequestResponseBodyMethodProcessor(getMessageConverters(), this.requestResponseBodyAdvice));
        resolvers.add(new RequestPartMethodArgumentResolver(getMessageConverters(), this.requestResponseBodyAdvice));
        resolvers.add(new RequestHeaderMethodArgumentResolver(getBeanFactory()));
        resolvers.add(new RequestHeaderMapMethodArgumentResolver());
        resolvers.add(new ServletCookieValueMethodArgumentResolver(getBeanFactory()));
        resolvers.add(new ExpressionValueMethodArgumentResolver(getBeanFactory()));
        resolvers.add(new SessionAttributeMethodArgumentResolver());
        resolvers.add(new RequestAttributeMethodArgumentResolver());

        // 基于参数类型的参数解析器
        resolvers.add(new ServletRequestMethodArgumentResolver());
        resolvers.add(new ServletResponseMethodArgumentResolver());
        resolvers.add(new HttpEntityMethodProcessor(getMessageConverters(), this.requestResponseBodyAdvice));
        resolvers.add(new RedirectAttributesMethodArgumentResolver());
        resolvers.add(new ModelMethodProcessor());
        resolvers.add(new MapMethodProcessor());
        resolvers.add(new ErrorsMethodArgumentResolver());
        resolvers.add(new SessionStatusMethodArgumentResolver());
        resolvers.add(new UriComponentsBuilderMethodArgumentResolver());
        if (KotlinDetector.isKotlinPresent()) {
            resolvers.add(new ContinuationHandlerMethodArgumentResolver());
        }

        // 这里是我们自定义的参数解析器
        if (getCustomArgumentResolvers() != null) {
            resolvers.addAll(getCustomArgumentResolvers());
        }

        // Catch-all 其他的参数解析器
        resolvers.add(new RequestParamMethodArgumentResolver(getBeanFactory(), true));
        resolvers.add(new ServletModelAttributeMethodProcessor(true));

        return resolvers;
    }
}
```
上面主要是一些初始化注册的逻辑，接下来看一下实际调用过程的处理

```Java
// RequestMappingHandlerAdapter.java （代码进行了简化）
protected ModelAndView invokeHandlerMethod(HttpServletRequest request,
        HttpServletResponse response, HandlerMethod handlerMethod) throws Exception {

    ServletWebRequest webRequest = new ServletWebRequest(request, response);
    try {
        // 1. 创建调用方法
        ServletInvocableHandlerMethod invocableMethod = createInvocableHandlerMethod(handlerMethod);

        // 2. 实际调用方法
        invocableMethod.invokeAndHandle(webRequest, mavContainer);

        return getModelAndView(mavContainer, modelFactory, webRequest);
    }
    finally {
        webRequest.requestCompleted();
    }
}

protected ServletInvocableHandlerMethod createInvocableHandlerMethod(HandlerMethod handlerMethod) {
    // 创建调用方法
    return new ServletInvocableHandlerMethod(handlerMethod);
}

```

调用方法处理在 ServletInvocableHandlerMethod 的父类 InvocableHandlerMethod 中
```Java
public class InvocableHandlerMethod extends HandlerMethod {
    // resolvers中是参数解析器的组合，具体后面看下
    private HandlerMethodArgumentResolverComposite resolvers = new HandlerMethodArgumentResolverComposite();

    public Object invokeForRequest(NativeWebRequest request, ModelAndViewContainer mavContainer,
            Object... providedArgs) throws Exception {

        // 将请求中的参数转换为方法调用的参数
        Object[] args = getMethodArgumentValues(request, mavContainer, providedArgs);
        if (logger.isTraceEnabled()) {
            logger.trace("Arguments: " + Arrays.toString(args));
        }
        // 调用实际方法
        return doInvoke(args);
    }

    protected Object[] getMethodArgumentValues(NativeWebRequest request, @Nullable ModelAndViewContainer mavContainer,
            Object... providedArgs) throws Exception {

        MethodParameter[] parameters = getMethodParameters();
        if (ObjectUtils.isEmpty(parameters)) {
            return EMPTY_ARGS;
        }

        Object[] args = new Object[parameters.length];
        for (int i = 0; i < parameters.length; i++) {
            MethodParameter parameter = parameters[i];
            parameter.initParameterNameDiscovery(this.parameterNameDiscoverer);
            args[i] = findProvidedArgument(parameter, providedArgs);
            if (args[i] != null) {
                continue;
            }
            // 1. 判断参数解析器中是否有支持此参数的解析
            if (!this.resolvers.supportsParameter(parameter)) {
                throw new IllegalStateException(formatArgumentError(parameter, "No suitable resolver"));
            }
            try {
                // 2. 找到后调用对应解析器进行参数处理
                args[i] = this.resolvers.resolveArgument(parameter, mavContainer, request, this.dataBinderFactory);
            }
            catch (Exception ex) {
                throw ex;
            }
        }
        return args;
    }

    protected Object doInvoke(Object... args) throws Exception {
        Method method = getBridgedMethod();
        ReflectionUtils.makeAccessible(method);
        try {
            if (KotlinDetector.isSuspendingFunction(method)) {
                return CoroutinesUtils.invokeSuspendingFunction(method, getBean(), args);
            }
            // 反射调用方法
            return method.invoke(getBean(), args);
        }
        catch (IllegalArgumentException ex) {
            // 先忽略异常处理等
        }
    }
}

```

最后看下上面resolvers(HandlerMethodArgumentResolverComposite)中的处理，在GET方法中我们写的自定义参数解析器也是在这里进行处理的
```Java
public class HandlerMethodArgumentResolverComposite implements HandlerMethodArgumentResolver {
    // 之前注册的参数解析器集合
    private final List<HandlerMethodArgumentResolver> argumentResolvers = new ArrayList<>();

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return getArgumentResolver(parameter) != null;
    }

    public Object resolveArgument(MethodParameter parameter, @Nullable ModelAndViewContainer mavContainer,
            NativeWebRequest webRequest, @Nullable WebDataBinderFactory binderFactory) throws Exception {
        HandlerMethodArgumentResolver resolver = getArgumentResolver(parameter);
        if (resolver == null) {
            throw new IllegalArgumentException("Unsupported parameter type [" +
                    parameter.getParameterType().getName() + "]. supportsParameter should be called first.");
        }
        return resolver.resolveArgument(parameter, mavContainer, webRequest, binderFactory);
    }

    // 遍历解析器集合，查询匹配的进行返回处理
    private HandlerMethodArgumentResolver getArgumentResolver(MethodParameter parameter) {
        HandlerMethodArgumentResolver result = this.argumentResolverCache.get(parameter);
        if (result == null) {
            for (HandlerMethodArgumentResolver resolver : this.argumentResolvers) {
                // 如果支持对此参数类型进行解析，则返回这个解析器
                if (resolver.supportsParameter(parameter)) {
                    result = resolver;
                    this.argumentResolverCache.put(parameter, result);
                    break;
                }
            }
        }
        return result;
    }
}
```



关于SpringMVC中自定义参数的转换内容基本就是这些，如有错误欢迎指正
