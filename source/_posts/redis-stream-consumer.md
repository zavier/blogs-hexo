---
title: Redis Stream 消费组
date: 2019-06-23 16:49:06
tags: redis
---

Stream是Redis5.0中新引入的一种数据类型，它是一个支持多播的可持久化的消息队列，解决了用`list`做消息队列时只能单个消费者接受和用`pub/sub`时，消费者重启会丢失消息的问题。它和`kafka`比较相似，同时也支持消费组，如果大家对kafka有所了解的话，学习stream会更容易一些

首先，它是一个消息队列，但是这个队列中的消息是持久化的，我们可以直接读取这个队列中的消息进行独立消费，也可以加入消费组，以组的形式消费其中的消息

<!-- more -->

## 消费组消费



```go
package main

import (
	"flag"
	"fmt"
	"github.com/go-redis/redis"
	"time"
)

// 启动时先从头开始检查读取，当前消费者之前读取但未消费确认的消息
// 处理完成后，则每次读取最新的数据
var lastid = "0-0"

func main() {

	streamName := *flag.String("stream", "mystream", "stream name")
	groupName := *flag.String("group", "mygroup", "group name")
	consumerName := *flag.String("consumer", "Bob", "consumer name")
	flag.Parse()

	fmt.Printf("Group: %s, Consumer: %s starting \n", groupName, consumerName)
	check_backlog := true

	client := redis.NewClient(&redis.Options{
		Addr: "47.93.214.100:6379",
	})

	for {
		var myid string
		if check_backlog {
			myid = lastid
		} else {
			myid = ">"
		}
		args := redis.XReadGroupArgs{
			Group: groupName,
			Consumer: consumerName,
			Streams: []string{streamName, myid},
			Block: time.Duration(2) * time.Second,
			Count: 10,
		}
		// 先将 lastId置为0-0，从头开始读取 当前消费者之前已读取，但是未消费确认的消息
		streamsRes := client.XReadGroup(&args)
		fmt.Printf("streams: %v \n", streamsRes)

		streams := streamsRes.Val()
		if streams == nil {
			fmt.Println("Timeout!")
			continue
		}

		// 说明已经处理完了之前 未确认 的消息，开始处理新消息，lastId改为 >
		if len(streams[0].Messages) == 0 {
			fmt.Println("read end")
			check_backlog = false
		}

		for _, item := range streams {
			messages := item.Messages
			for _, msg := range messages {
				id := msg.ID
				values := msg.Values

				process_message(id, values)

				// 消息消费确认
				client.XAck(streamName, groupName, id)
				lastid = id
			}
		}
	}
}

func process_message(id string, msg map[string]interface{}) {
	fmt.Printf("[id=%s] msg=%v \n", id, msg)
}
```

