---
title: 基于SpringAI实现Agent
date: 2025-08-02 21:51:39
tags: [spring-ai, agents]
---

本文主要介绍一下通过Spring AI 来实现一个类似[OpenAI Agents SDK](https://openai.github.io/openai-agents-python/)的功能

具体效果为在application.yml 中配置对应的agent 信息，如

```yml
spring:
  ai:
    agents:
      # 定义一个Agent
      - name: historyTutor
        # 与大模型交互时的Agent的系统提示词
        instructions: You provide assistance with historical queries. Explain important events and context clearly.
        # 其他Agent可以获取到的关于当前agent的描述信息
        handoffDescription: Specialist agent for historical questions

      # 定义另一个Agent
      - name: mathTutor
        instructions: You provide help with math problems. Explain your reasoning at each step and include examples
        handoffDescription: Specialist agent for math questions

      # 定义入口agent
      - name: triageAgent
        instructions: You determine which agent/tools to use based on the user's homework question
        # 这里定义可以分派的其他agent有哪些
        handoffs:
          - historyTutor
          - mathTutor
```

使用时，按需注入即可：

```java
@Slf4j
@RestController
public class AgentController {

    // 通过名称注入
    @Resource
    private Agent triageAgent;

    @GetMapping("/triage")
    public Flux<String> triage(String input) {
        return triageAgent.asyncExecute(input);
    }
}
```

<!-- more -->

下面看一下具体的实现

1. 首先需要定义一个Agent类，其中包含与大模型交互等需要用到的信息

```java
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.SimpleLoggerAdvisor;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.tool.ToolCallback;
import org.springframework.ai.tool.definition.ToolDefinition;
import org.springframework.ai.util.json.schema.JsonSchemaGenerator;
import org.springframework.util.Assert;
import reactor.core.publisher.Flux;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

@Slf4j
public class Agent {
    @Setter
    private String name;
    @Setter
    private String instructions;
    @Setter
    private String handoffDescription;
    @Setter
    private ChatModel chatModel;
    @Setter
    private List<Object> tools = new ArrayList<>();
    @Setter
    private List<Agent> handoffs = new ArrayList<>();

    private ChatClient chatClient;

    public void init() {
        Assert.notNull(chatModel, "ChatModel must not be null");
        log.info("Initializing agent: {}", name);

        // 初始化时，需要将handoffs 转换为 ToolCallback
        final List<ToolCallback> list = handoffs.stream()
                .map(Agent::getToolCallback)
                .toList();

        // 创建ChatClient,绑定相关信息
        final ChatClient.Builder builder = ChatClient.builder(chatModel);
        chatClient = builder.defaultSystem(instructions)
                .defaultTools(tools.toArray())
                .defaultAdvisors(new SimpleLoggerAdvisor())
                .defaultToolCallbacks(list)
                .build();
    }


    public String execute(String input) {
        log.info("Executing agent: {}", name);
        return chatClient.prompt()
                .user( input)
                .call()
                .content();
    }

    public Flux<String> asyncExecute(String input) {
        log.info("async Executing agent: {}", name);
        return chatClient.prompt()
                .user(input)
                .stream()
                .content();
    }


    // 提供一个方法，用于将Agent 转换为 ToolCallback实现类
    public ToolCallback getToolCallback() {
        return new AgentToolCallback(this);
    }

    public static class AgentToolCallback implements ToolCallback {

        private final Agent agent;

        public AgentToolCallback(Agent agent) {
            this.agent = agent;
        }

        @Override
        public ToolDefinition getToolDefinition() {
            final Method callMethod;
            try {
                callMethod = AgentToolCallback.class.getMethod("call", String.class);
            } catch (NoSuchMethodException e) {
                log.error("Error generating JSON schema for method: {}", e.getMessage(), e);
                throw new RuntimeException(e);
            }
            final String methodInput = JsonSchemaGenerator.generateForMethodInput(callMethod);
            return ToolDefinition.builder()
                    .name(agent.name)
                    .description(agent.handoffDescription)
                    .inputSchema(methodInput)
                    .build();
        }

        @Override
        public String call(String toolInput) {
            return agent.execute(toolInput);
        }
    }
}
```





2. 之后需要定义一个配置类，用于和application.yml 中配置信息进行一一映射

```java
import lombok.Data;

import java.util.ArrayList;
import java.util.List;

@Data
public class AgentConfig {

    private String name;
    private String instructions;
    private String handoffDescription;
    private String chatModel;

    /**
     * 工具bean名称集合
     */
    private List<String> tools = new ArrayList<>();

    /**
     * 待转接的模型bean名称集合（agents）
     */
    private List<String> handoffs = new ArrayList<>();
}
```





3. 需要实现`ImportBeanDefinitionRegistrar`来完成根据配置信息动态创建Agent bean 的过程

```java
import com.github.zavier.spring.agents.agent.Agent;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.BeanFactory;
import org.springframework.beans.factory.BeanFactoryAware;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.beans.factory.config.RuntimeBeanReference;
import org.springframework.beans.factory.support.BeanDefinitionBuilder;
import org.springframework.beans.factory.support.BeanDefinitionRegistry;
import org.springframework.beans.factory.support.ManagedList;
import org.springframework.boot.context.properties.bind.Bindable;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.context.EnvironmentAware;
import org.springframework.context.ResourceLoaderAware;
import org.springframework.context.annotation.ImportBeanDefinitionRegistrar;
import org.springframework.core.Ordered;
import org.springframework.core.PriorityOrdered;
import org.springframework.core.env.Environment;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.core.type.AnnotationMetadata;
import org.springframework.util.StreamUtils;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;

public class AgentBeanDefinitionRegistrar implements ImportBeanDefinitionRegistrar,
        EnvironmentAware, BeanFactoryAware, PriorityOrdered, ResourceLoaderAware {
    private BeanFactory beanFactory;
    private Environment environment;
    private ResourceLoader resourceLoader;

    @Override
    public void setBeanFactory(BeanFactory beanFactory) throws BeansException {
        this.beanFactory = beanFactory;
    }

    @Override
    public void setEnvironment(Environment environment) {
        this.environment = environment;
    }

    @Override
    public void setResourceLoader(ResourceLoader resourceLoader) {
        this.resourceLoader = resourceLoader;
    }

    @Override
    public void registerBeanDefinitions(AnnotationMetadata importingClassMetadata, BeanDefinitionRegistry registry) {
        // 使用Binder绑定配置到List，注意这里的配置前缀是 spring.ai.agents
        List<AgentConfig> agents = Binder.get(environment)
                .bind("spring.ai.agents", Bindable.listOf(AgentConfig.class))
                .orElse(List.of());

        for (AgentConfig agentConfig : agents) {
            String beanName = agentConfig.getName();

            // 检查是否已注册同名Bean
            if (registry.containsBeanDefinition(beanName)) {
                throw new IllegalStateException("Bean already exists: " + beanName);
            }

            BeanDefinition beanDefinition = createAgentBeanDefinition(agentConfig);
            registry.registerBeanDefinition(beanName, beanDefinition);
        }
    }

    private BeanDefinition createAgentBeanDefinition(AgentConfig agentConfig) {
        BeanDefinitionBuilder builder = BeanDefinitionBuilder
                .genericBeanDefinition(Agent.class);

        // 设置基本属性
        builder.addPropertyValue("name", agentConfig.getName());
        builder.addPropertyValue("instructions", agentConfig.getInstructions());

        // 如果配置了文件，则从文件中读取
        if (agentConfig.getInstructions() != null && agentConfig.getInstructions().startsWith("classpath:")) {
            try {
                final Resource resource = resourceLoader.getResource(agentConfig.getInstructions());
                String instructions = StreamUtils.copyToString(resource.getInputStream(), StandardCharsets.UTF_8);
                builder.addPropertyValue("instructions", instructions);
            } catch (IOException e) {
                throw new IllegalStateException("Failed to read instructions file: " + agentConfig.getInstructions(), e);
            }
        }

        // handoffs-description
        builder.addPropertyValue("handoffDescription", agentConfig.getHandoffDescription());


        // chatModel
        if (StringUtils.isNotBlank(agentConfig.getChatModel())) {
            builder.addPropertyReference("chatModel", agentConfig.getChatModel());
        } else {
            // 这里默认使用的 openAiChatModel
            builder.addPropertyReference("chatModel", "openAiChatModel");
        }

        // tools
        if (agentConfig.getTools() != null && !agentConfig.getTools().isEmpty()) {
            ManagedList<RuntimeBeanReference> toolsList = new ManagedList<>();
            for (String toolName : agentConfig.getTools()) {
                if (beanFactory.containsBean(toolName)) {
                    toolsList.add(new RuntimeBeanReference(toolName));
                } else {
                    throw new IllegalStateException("Tool bean not found: " + toolName);
                }
            }
            builder.addPropertyValue("tools", toolsList);
        }

        // handoffs
        if (agentConfig.getHandoffs() != null && !agentConfig.getHandoffs().isEmpty()) {
            ManagedList<RuntimeBeanReference> handoffsList = new ManagedList<>();
            for (String handoffName : agentConfig.getHandoffs()) {
                if (beanFactory.containsBean(handoffName)) {
                    handoffsList.add(new RuntimeBeanReference(handoffName));
                } else {
                    throw new IllegalStateException("Handoff bean not found: " + handoffName);
                }
            }
            builder.addPropertyValue("handoffs", handoffsList);
        }

        builder.setInitMethodName("init");

        return builder.getBeanDefinition();
    }

    @Override
    public int getOrder() {
        return Ordered.LOWEST_PRECEDENCE;
    }
}
```



4. 最后，我们添加一个配置类来使AgentBeanDefinitionRegistrar 生效

```java
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

@Configuration
@Import(AgentBeanDefinitionRegistrar.class)
public class AgentAutoConfiguration {
}
```



这样在项目启动的过程中，会自动读取配置文件，创建相应的Agent Bean, 在需要的地方通过名字直接注入即可使用～
