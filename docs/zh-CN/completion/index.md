---
title: 关于补全的 json 文件结构
next:
    text: 关于贡献
    link: '../contribute/index.md'
---

# 关于补全的 json 文件结构

```json
{
	"root": [],
	"options": [],
	"common_options": [],
	"info": {},
	"config": []
}
```

-   以上是 json 文件的总体结构
-   json 文件使用了 schema 架构来保证 json 内容的正确和完整
    -   你可以通过悬浮提示了解属性
-   其实很简单，多看几个已有的 json 文件，就能看懂了

## 属性详解

### 1. `root`

-   值类型: 数组
-   最核心的一个属性(通常情况下)

    -   数组中的每一项是一个对象
    -   对象可用属性: `name`(必需)、`alias`、`symbol`、`next`、`options`、`tip`
    -   不多解释，在 vscode 中，配合 schema，很容易理解
    -   其中，`next` 和 `options` 的值也是一个数组，几乎和 `root` 相同
        -   不同点: `options` 中不允许添加 `options` 属性(就是不能在选项中嵌套选项)
    -   在大多数情况，你不需要考虑定义 `symbol`，因为 `symbol` 会根据上下文，自动添加一些值，用于显示符号
        -   当补全项有 `next` 时，会自动添加 `SpaceTab`
        -   在 `options`中的 `symbol` 属性会自动添加 `OptionTab`
    -   需要手动添加 `Symbol` 的情况

        -   当 `options` 中的选项类补全需要有几个预设值时

            -   ```json
                {
                	"name": "reset",
                	"options": [
                		{
                			"name": "--soft",
                			"symbol": ["WriteSpaceTab", "SpaceTab"]
                		}
                	]
                }
                ```

        -   当补全使用到了 `hooks` 添加了动态补全项时
            -   ```json
                {
                	"name": "rm",
                	"symbol": "SpaceTab"
                }
                ```

### 2. `options`

-   值类型: 数组
-   和 `root` 中的每一项的 `options` 相同
-   ```json
    {
    	"options": [
    		{
    			"name": "--version",
    			"alias": ["-v"],
    			"tip": "显示当前版本"
    		}
    	]
    }
    ```

### 3. `common_options`

-   值类型: 数组
-   这里面的所有选项在任何时候都会显示
-   ```json
    {
    	"options": [
    		{
    			"name": "--help",
    			"alias": ["-h"],
    			"tip": "显示帮助信息"
    		}
    	]
    }
    ```

### 4. `info`

-   值类型: 对象
-   定义的所有值，可以在其他地方通过以下语法获取
-   ```json
    // {{ $info.xxx }}
    // {{ $json.xxx }} $json 是整个json文件形成的对象
    {
    	"root": [
    		{
    			"name": "test",
    			"tip": "{{ $info.test_tip }}"
    		},
    		{
    			"name": "abc",
    			"tip": "{{ $json.info.abc_tip }}"
    		}
    	],
    	"info": {
    		"test_tip": "这是一个测试内容",
    		"abc_tip": "abcdefg"
    	}
    }
    ```

### 5. `config`

-   值类型: 数组
-   定义补全的特殊配置(以 `git` 的特殊配置为例)
-   ```json
    "config": [
        {
        "name": "disable_hooks",
        "value": 0,
        "values": [
            1,
            0
        ],
        "tip": [
            "设置是否禁用 hooks，默认为 0 表示不禁用\n",
            "git 中的 hooks 主要用于解析 commit 信息、分支信息等, 然后动态添加到一些补全中(如 reset,checkout,branch 等)\n",
            "如: git reset 后可以获取到解析出来的 commit，快速补全\n",
            "如果你不需要它，你可以禁用它，这样可以提高补全的加载速度\n",
            "如果禁用它，那么 <@Magenta>max_commit<@Blue> 配置也将无效"
        ]
        },
        {
        "name": "max_commit",
        "value": 20,
        "values": [
            -1,
            20
        ],
        "tip": [
            "可以为当前项目解析的 commit 的最大数量\n",
            "如果设置为 <@Magenta>-1<@Blue>, 会解析所有的 commit\n",
            "如果项目 commit 数量较多，设置为 <@Magenta>-1<@Blue> 对补全加载的速度会有不小的影响"
        ]
        }
    ]
    ```
