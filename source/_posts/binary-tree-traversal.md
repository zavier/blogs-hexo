---
title: 二叉树遍历笔记
date: 2020-05-03 13:51:30
tags: [二叉树]
---

树的遍历分为深度优先和广度优先，对于二叉树来说，深度优先有前序遍历（根->左->右), 中序遍历（左->根->右）和后序遍历（根->左->右），广度优先为层次遍历。这里主要对这几种遍历方式的实现进行一下记录

先定义一下树结构

```java
public class TreeNode {
    int val;
    TreeNode left;
    TreeNode right;
    TreeNode(int x) { val = x; }
}
```

<!-- more -->

## 深度优先遍历

### 前序遍历

**递归实现**

```java
public List<Integer> preorderTraversal(TreeNode root) {
    List<Integer> result = new ArrayList<>();
    preorder(root, result);
    return result;
}

private void preorder(TreeNode node, List<Integer> result) {
    if (node == null) {
        return;
    }
    result.add(node.val);
    preorder(node.left, result);
    preorder(node.right, result);
}
```

**迭代实现**

```java
public List<Integer> preorderTraversal(TreeNode root) {
    if (root == null) {
        return new ArrayList<>();
    }
    Stack<TreeNode> stack = new Stack<>();
    stack.push(root);

    List<Integer> result = new ArrayList<>();
    while (!stack.isEmpty()) {
        TreeNode treeNode = stack.pop();
        result.add(treeNode.val);
        // 先入栈右节点，是为了让左节点先出栈
        if (treeNode.right != null) {
            stack.push(treeNode.right);
        }
        if (treeNode.left != null) {
            stack.push(treeNode.left);
        }
    }
    return result;
}
```



### 中序遍历

**递归实现**

```java
public List<Integer> inorderTraversal(TreeNode root) {
    List<Integer> result = new ArrayList<>();
    inorder(root, result);
    return result;
}

private void inorder(TreeNode node, List<Integer> result) {
    if (node == null) {
        return;
    }
    inorder(node.left, result);
    result.add(node.val);
    inorder(node.right, result);
}
```

**迭代实现**

```java
public List<Integer> inorderTraversal(TreeNode root) {
    if (root == null) {
        return new ArrayList<>();
    }
    Stack<TreeNode> stack = new Stack<>();

    List<Integer> result = new ArrayList<>();
    TreeNode treeNode = root;
    while (!stack.isEmpty() || treeNode != null) {
        if (treeNode != null) {
            // 添加所有的左子节点
            stack.push(treeNode);
            treeNode = treeNode.left;
        } else {
            // 开始访问
            treeNode = stack.pop();
            result.add(treeNode.val);
            treeNode = treeNode.right;
        }
    }
    return result;
}
```



### 后序遍历

**递归实现**

```java
public List<Integer> postorderTraversal(TreeNode root) {
    List<Integer> result = new ArrayList<>();
    postorder(root, result);
    return result;
}

private void postorder(TreeNode treeNode, List<Integer> result) {
    if (treeNode == null) {
        return;
    }
    postorder(treeNode.left, result);
    postorder(treeNode.right, result);
    result.add(treeNode.val);
}
```

**迭代实现**

```java
public List<Integer> postorderTraversal(TreeNode root) {
    if (root == null) {
        return new ArrayList<>();
    }

    Stack<TreeNode> stack = new Stack<>();
    stack.push(root);
    // 当栈使用
    LinkedList<Integer> result = new LinkedList<>();
    while (!stack.isEmpty()) {
        // 根节点入最终结果容器栈(最后出栈)
        TreeNode treeNode = stack.pop();
        result.addFirst(treeNode.val);

        // 入栈左节点后再入栈右节点(调用后让右节点先弹出如结果栈，这样就是 左->右->根顺序)
        if (treeNode.left != null) {
            stack.push(treeNode.left);
        }
        if (treeNode.right != null) {
            stack.push(treeNode.right);
        }
    }
    return result;
}
```



## 广度优先遍历

### 层次遍历

```java
public List<Integer> levelOrder(TreeNode root) {
    if (root == null) {
        return new int[0];
    }
    Queue<TreeNode> queue = new LinkedList<>();
    queue.offer(root);

    List<Integer> list = new ArrayList<>();
    while (!queue.isEmpty()) {
        TreeNode treeNode = queue.poll();
        list.add(treeNode.val);
        if (treeNode.left != null) {
            queue.offer(treeNode.left);
        }
        if (treeNode.right != null) {
            queue.offer(treeNode.right);
        }
    }
    return list;
}
```

