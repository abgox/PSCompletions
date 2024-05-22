---
title: About PR (Pull Request)
prev:
    text: About the structure of json file
    link: '../completion/index.md'
---

# About PR (Pull Request)

1. Prerequisite: You should read [About the structure of completion json file](../completion/index.md) first.
2. You should fork [PSCompletions](https://github.com/abgox/PSCompletions), and clone to your machine.
3. After Changing, you should commit and create the `PR`.

## 1. Update the content of completion json file

-   Patch some tips of the completion.(`tip` attributes)
-   Add some missing commands for the completion.

## 2. Add language

1. In the `completions` directory, select the language you want to add.
2. Add the language identifier to the language in the `config.json` file.
3. Add a json file with the same name as the language identifier in the `language` directory.
    - You can copy the original json file and rename it.
4. Translate the contents of the `tip` attribute.

## 3. Add a new completion

1. Run it in the project root directory. `.\script\create.ps1`
2. Follow the prompts.
3. Modify the new completion.
4. Add this completion to the value of the `list` property in `completions.json` in the project root directory.
