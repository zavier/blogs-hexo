---
title: Git Worktree：更优雅的多分支开发方式
date: 2025-10-08 10:08:26
tags: [git]
---

> 注：AI 生成，略有调整

在日常开发中，我们经常需要同时处理多个分支：

- 一个主分支（`main` 或 `develop`）
- 若干个功能开发分支（`feature/*`）
- 偶尔的紧急修复分支（`hotfix/*`）

大多数人为了同时开发或调试多个分支，会这样做： **再 clone 一份仓库，然后在另一个目录里切换到不同分支**。

但这样带来很多问题：

- 占用磁盘空间（一个项目可能几百 MB，clone 多份会爆仓）
- 管理混乱（分支、依赖、配置容易搞混）
- Git 操作分散（每个仓库要分别 fetch/pull）

其实，Git 内置了一个优雅的解决方案 —— **`git worktree`**。

<!-- more -->

## 一、什么是 Git Worktree？

简单来说：

> **Git worktree 允许你在同一个 Git 仓库中，同时签出（checkout）多个分支到不同的工作目录。**

换句话说，你只需要一个 `.git` 仓库，就可以拥有多个独立的工作区，每个工作区可以是不同分支的代码。

```
project/
├── .git/               # 唯一的 Git 仓库
├── main/               # 主分支工作区
│   └── ...
../feature-login/      # 功能分支工作区
../hotfix              # 修复分支工作区
```

这样既避免了重复 clone，又能同时在多个分支上工作。

## 二、常用命令速览

| 命令                               | 说明                                       |
| ---------------------------------- | ------------------------------------------ |
| `git worktree list`                | 查看当前仓库下的所有工作区                 |
| `git worktree add <path> <branch>` | 创建新的工作区并检出指定分支               |
| `git worktree remove <path>`       | 删除一个工作区（Git 2.35+ 会自动删除目录） |
| `git worktree prune`               | 清理无效或孤立的 worktree 记录             |

### 创建新的 worktree

```
git worktree add ../feature-login feature/login
```

**解释：**

- `../feature-login` 是新工作区目录（注意不要在主工作区创建目录）
- `feature/login` 是要签出的分支名（不存在会自动创建）

效果：在上级目录创建一个名为 `feature-login` 的文件夹，并签出 `feature/login` 分支。

---

### 查看当前所有 worktree

```
git worktree list
```

输出示例：

```
/Users/wei/project              e1d2b3c [main]
/Users/wei/project/feature-login 9a3c4d2 [feature/login]
```

可以看到当前仓库下的所有工作区及对应分支。

---

### 删除 worktree

```
git worktree remove ../feature-login
```



## 三、实际使用场景详解

### 多分支并行开发

假设你在 `develop` 分支上开发新版本，但此时有另一个功能 `feature/login` 需要同时开发。

#### 传统做法（麻烦版）

1. 复制项目目录一份
2. 在新目录中切换分支
3. 分别开发两个分支

> 缺点：代码重复、浪费磁盘、容易混淆

#### 使用 Worktree（优雅版）

1.在项目根目录执行：

```
cd ~/project
git worktree add ../feature-login feature/login
```

这会在上级目录创建一个新目录 `feature-login`，并签出 `feature/login` 分支。

目录结构如下：

```
project/                # 当前是 develop 分支
../feature-login/       # 新建的 feature/login 分支
```

2.开发流程：

在 `feature-login` 目录下正常开发、提交代码：

```
cd ../feature-login
# 编辑代码
git add .
git commit -m "Add login feature"
```

与此同时，你仍可以在原 `project` 目录中继续开发 `develop` 分支。



## 四、更多技巧与注意事项

### 同时管理多个分支的优势

- 每个分支都是独立的目录，不会互相污染
- 构建缓存可复用（例如使用 `node_modules` 或 `venv`）
- 提高上下文切换效率（无需反复 stash / checkout）
- 结合 IDE（VSCode、IntelliJ）时，可分别打开不同分支目录并调试

------

### 注意事项

1. **不要在同一分支上创建多个 worktree**（Git 会拒绝）

    > 一个分支同一时间只能被一个 worktree 签出。

2. **删除 worktree 时，务必先确保没有未提交修改**
     否则可能丢失工作成果。

3. **worktree 的元信息保存在 `.git/worktrees/` 中**
     不要随意手动修改或删除此目录。



## 五、完整示例流程回顾

以下是一个真实开发场景的完整命令流程：

```
# 1. 当前在 develop 分支上
git status
# On branch develop

# 2. 新建功能分支的独立工作区
git worktree add ../feature-login feature/login

# 3. 进入并开发新功能
cd ../feature-login
# ...edit code...
git add .
git commit -m "Add login module"
git push origin feature/login

# 4. 线上紧急 bug，创建 hotfix 工作区
cd ~/project
git worktree add ../hotfix-urgent main

# 5. 修复并推送
cd ../hotfix-urgent
# ...fix bug...
git commit -am "Hotfix: patch production issue"
git push origin main

# 6. 删除修复分支工作区
git worktree remove ../hotfix-urgent
```



## 六、总结

| 对比项     | 多仓库开发    | Git Worktree     |
| ---------- | ------------- | ---------------- |
| 磁盘空间   | 多份重复代码  | 共享 `.git` 仓库 |
| 分支切换   | 手动 checkout | 独立目录并行     |
| 上下文切换 | 需要 stash    | 无需 stash       |
| 易用性     | 一般          | 高效简洁         |



## 参考资料

- [Git 官方文档：git-worktree](https://git-scm.com/docs/git-worktree)
- [Pro Git（中文版）](https://git-scm.com/book/zh/v2)
