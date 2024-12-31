---
title: 使用Cursor开发聚会分账小程序
date: 2024-12-31 21:57:02
tags: [cursor, 聚会分账小程序]
---

平时跟朋友一起聚会或者出游的时候，大家一般都会选择AA分摊费用，这样更公平也不伤感情。不过，问题也随之而来：支出总是乱七八糟的，比如谁打了车，谁买了菜，谁带了零食……光是汇总这些就够头疼了。如果再碰上有些开销不是所有人都参与，那结算起来简直就是灾难

之前我写过一个简单的[Web小工具](https://zhengw-tech.com/expense/index-cdn.html#/project/list)，本想着能解决问题，结果朋友们吐槽太麻烦，建议我做个小程序。不过，说实话，我对小程序开发完全是个小白。正好最近大模型特别火，我就想着用 [Cursor](https://www.cursor.com/) 来试试，顺便满足一下好奇心。如果你也有类似的需求，可以来看看，说不定能帮上忙！

<!-- more -->

**登录页面**

目前登录可以随意注册账号，或者也可以通过微信登录（不需要任何其他权限，只使用了openId）

<img src="/images/expense/share_expense_login.png" style="zoom:60%" />



**账本列表**

每个账本可以理解为一次聚合，一次旅行等等

<img src="/images/expense/share_expense_list_project.png" style="zoom:60%" />



**创建账本**

<img src="/images/expense/share_expense_add_project.png" style="zoom:60%" />



**账本费用明细**

其中展示账本的费用明细，包含全部明细以及每个人的分摊明细以及应付、应收等

<img src="/images/expense/share_expense_project_detail.png" style="zoom:60%" />



**费用录入**

<img src="/images/expense/share_expense_add_fee.png" style="zoom:60%" />



**费用分享**

可以将费用明细分享给其他人

<img src="/images/expense/share_expense_share.png" style="zoom:60%" />



目前小程序还没有上线，有兴趣的话可以扫码申请体验版

<img src="/images/expense/share_expense_qrcode.jpg" style="zoom:60%" />



全部代码已上传Github:  [后端代码](https://github.com/zavier/share-expense)、[小程序代码](https://github.com/zavier/expense-miniprogram)

大家如果有其他建议之类的也欢迎交流～～
