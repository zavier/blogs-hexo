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

关于SpringMVC中自定义参数的转换使用基本就是这些，如有错误欢迎指正