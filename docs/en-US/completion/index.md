---
title: About the structure of json file
next:
  text: About PR (Pull Request)
  link: "../contribute/index.md"
---

# About the structure of json file

```json
{
  "root": [],
  "options": [],
  "common_options": [],
  "info": {},
  "config": []
}
```

- The json file uses a schema structure to ensure that the json content is correct and complete.
  - You can learn about these properties by hovering over the prompts
- In fact, it is very simple, you can refer to the existing json file.

## Properties

### 1. `root`

- The type of value: array
- The most core attribute (usually)

  - Each item in the array is an object
  - Object available attribute: `name`(required)、`alias`、`symbol`、`next`、`options`、`tip`
  - In vscode, with schema, it's easy to understand.
  - The values of `next` and `options` are also arrays, almost identical to `root`.
    - Difference: The `options` attribute is not allowed in `options`.
  - In most cases, you don't need to think about defining `symbol` because `symbol` will automatically add some value to the symbols depending on context
    - When the completion item has `next`, `SpaceTab` is automatically added.
    - The `symbol` attribute in `options` automatically adds the `OptionTab`.
  - Some Cases where `Symbol` needs to be added manually.

    - When several preset values are needed in `options`

      - ```json
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

    - When completion uses `hooks` to add some dynamic completion items.
      - ```json
        {
          "name": "rm",
          "symbol": "SpaceTab"
        }
        ```

### 2. `options`

- The type of value: array
- Same as the `options` for each item in `root`.
- ```json
  {
    "options": [
      {
        "name": "--version",
        "alias": ["-v"],
        "tip": "Show current version"
      }
    ]
  }
  ```

### 3. `common_options`

- The type of value: array
- Same structure as `options`
- All options are displayed at all times.
- ```json
  {
    "common_options": [
      {
        "name": "--help",
        "alias": ["-h"],
        "tip": "Show help."
      }
    ]
  }
  ```

### 4. `info`

- The type of value: object
- All values defined can be obtained elsewhere with the following syntax.
- ```json
  // {{ $info.xxx }}
  // {{ $json.xxx }} $json is the object of the entire json file.
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
      "test_tip": "this is test content.",
      "abc_tip": "abcdefg"
    }
  }
  ```

### 5. `config`

- The type of value: array
- Define some special configurations for completion.(e.g. `git`)
- ```json
  "config": [
      {
      "name": "disable_hooks",
      "value": 0,
      "values": [
          1,
          0
      ],
      "tip": [
          "Set whether to disable hooks. Default to 0.\n",
          "Hooks in git are mainly used to parse commit information, branch information, etc., and then dynamically add them to some completions (such as reset,checkout,branch, etc.)\n",
          "For example, enter <@Magenta>git reset<@Blue>, press <@Magenta>Space<@Blue> and <@Magenta>Tab<@Blue>, and you can get the resolved commit completions.\n",
          "If you don't need it, you can disable it, which will improve the loading speed of the completion.\n",
          "If you disable it, the <@Magenta>max_commit<@Blue> configuration will also be invalid."
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
          "The maximum number that can be parsed for a project commit.\n",
          "If it is <@Magenta>-1<@Blue>, all commits will be parsed.\n",
          "If there are a large number of project commits, setting <@Magenta>-1<@Blue> will affect the loading speed of the completion."
      ]
      }
  ]
  ```
