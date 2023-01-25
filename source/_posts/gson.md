---
title: Gson原理分析-JsonReader
date: 2023-01-20 11:08:24
tags: [gson, json]
---

java语言下，进行json处理的工具类jackson, fastjson, gson等，使用起来比较简单，就不介绍了，这次我们就来探索一下其中gson的具体实现，其核心处理类为JsonReader和JsonWriter进行json格式数据的读取和写入，上层TypeAdapter使用其进行json和具体数据类型的转换，而Gson调用时会根据类型获取到具体的TypeAdapter进行使用

<img src="/images/gson.jpg" style="zoom:60%" />

<!-- more -->

在将json字符串转换成Java对象时，首先需要有定义Java的类，这里我们先不定义，而是使用一种更通用的，将json字符串转换成JsonElement的方法(`com.google.gson.JsonParser#parseString`)实现 

```java
// JsonParser.java
public static JsonElement parseReader(JsonReader reader)
        throws JsonIOException, JsonSyntaxException {
    boolean lenient = reader.isLenient();
    reader.setLenient(true);
    try {
        // 1. 调用Streams的方法
        return Streams.parse(reader);
    } catch (StackOverflowError e) {
        throw new JsonParseException("Failed parsing JSON source: " + reader + " to Json", e);
    } catch (OutOfMemoryError e) {
        throw new JsonParseException("Failed parsing JSON source: " + reader + " to Json", e);
    } finally {
        reader.setLenient(lenient);
    }
}

// Streams.java
public static JsonElement parse(JsonReader reader) throws JsonParseException {
    boolean isEmpty = true;
    try {
        reader.peek();
        isEmpty = false;
        // 2. 使用 TypeAdapters.JSON_ELEMENT 进行读取
        return TypeAdapters.JSON_ELEMENT.read(reader);
    } catch (EOFException e) {
        if (isEmpty) {
            return JsonNull.INSTANCE;
        }
        // The stream ended prematurely so it is likely a syntax error.
        throw new JsonSyntaxException(e);
    } catch (MalformedJsonException e) {
        throw new JsonSyntaxException(e);
    } catch (IOException e) {
        throw new JsonIOException(e);
    } catch (NumberFormatException e) {
        throw new JsonSyntaxException(e);
    }
}
```

最终调用如下Adapter

```java
// TypeAdapters.java
public static final TypeAdapter<JsonElement> JSON_ELEMENT = new TypeAdapter<JsonElement>() {
    /**
     * 读取对象或者数组
     */
    private JsonElement tryBeginNesting(JsonReader in, JsonToken peeked) throws IOException {
        switch (peeked) {
            case BEGIN_ARRAY:
                in.beginArray();
                return new JsonArray();
            case BEGIN_OBJECT:
                in.beginObject();
                return new JsonObject();
            default:
                return null;
        }
    }

    /** 读取基础类型和null */
    private JsonElement readTerminal(JsonReader in, JsonToken peeked) throws IOException {
        switch (peeked) {
            case STRING:
                return new JsonPrimitive(in.nextString());
            case NUMBER:
                String number = in.nextString();
                return new JsonPrimitive(new LazilyParsedNumber(number));
            case BOOLEAN:
                return new JsonPrimitive(in.nextBoolean());
            case NULL:
                in.nextNull();
                return JsonNull.INSTANCE;
            default:
                throw new IllegalStateException("Unexpected token: " + peeked);
        }
    }

    // 3. 进行json数据读取
    // 总结一下就是使用peek，后根据peek的结果来调用对应的方法进行读取使用
    @Override public JsonElement read(JsonReader in) throws IOException {
        if (in instanceof JsonTreeReader) {
            return ((JsonTreeReader) in).nextJsonElement();
        }

        // JsonArray 或者 JsonObject
        JsonElement current;
        JsonToken peeked = in.peek();

        // 根据peeked结果，判断类型后创建JsonObject或者JsonArray
        current = tryBeginNesting(in, peeked);
        if (current == null) {
            // 如果是基础类型，则直接读取后返回
            return readTerminal(in, peeked);
        }

        // 这部分之前低版本是使用递归来实现的，这里是使用栈来实现
        // 之前的递归代码阅读起来比较容易，这里调整可能是为了防止堆栈溢出?
        Deque<JsonElement> stack = new ArrayDeque<>();

        while (true) {
            while (in.hasNext()) {
                String name = null;
                // 之前读取的是类型是对象时，接着获取对象的key
                if (current instanceof JsonObject) {
                    name = in.nextName();
                }

                // 查看一下key对应的value值(此时没有真正读取值)，判断一下值结构
                peeked = in.peek();
                JsonElement value = tryBeginNesting(in, peeked);
                // value是对象或者数组时，则认为是嵌套结构
                boolean isNesting = value != null;

                // key对应的value不是对象或者数组结构，则认为是基础类型进行读取
                if (value == null) {
                    value = readTerminal(in, peeked);
                }

                // 根据结构(对象或者数组)，进行数据的添加
                if (current instanceof JsonArray) {
                    ((JsonArray) current).add(value);
                } else {
                    ((JsonObject) current).add(name, value);
                }

                if (isNesting) {
                    // value是对象或者数组，则将此次结果记录到队列中，下个循环开始解析value中的信息
                    stack.addLast(current);
                    current = value;
                }
            }

            // 最后根据结构调用关闭读取方法
            if (current instanceof JsonArray) {
                in.endArray();
            } else {
                in.endObject();
            }

            if (stack.isEmpty()) {
                return current;
            } else {
                // 之前的while循环中，嵌套结构(深度优先)已经处理完成，这里依次再进行出栈后解析(广度)
                current = stack.removeLast();
            }
        }
    }

    @Override public void write(JsonWriter out, JsonElement value) throws IOException {
        // TODO write部分这次先不进行查看分析
    }
};
```











