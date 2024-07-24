---
title: About PR (Pull Request)
prev:
  text: About the structure of json file
  link: "../completion/index.md"
---

# About PR (Pull Request)

1. Prerequisite: You should read [About the structure of completion json file](../completion/index.md) first.
2. You should fork [PSCompletions](https://github.com/abgox/PSCompletions), and clone to your machine.
3. After Changing, you should commit and create the `PR`.

## 1. Update the content of completion json file

- Patch some tips of the completion.(`tip` attributes)
- Add some missing parts for the completion.
  - The missing parts can be viewed by using the `compareJson.ps1` script.
    - Take `git` for example.
    - You can view the missing parts of the `zh-CN.json` file (Compared to the `en-US.json` file) by using the following command.
      - `.\script\compareJson.ps1 .\completions\git\language\zh-CN.json .\completions\git\language\en-US.json`
    - If it's compared to the first language configured in `config.json`, the second parameter can also be omitted.
      - It's usually compared to the first language, so the following commands are the most common usage.
      - `.\script\compareJson.ps1 .\completions\git\language\zh-CN.json`

## 2. Add language

1. In the `completions` directory, select the language you want to add.
2. Add the language identifier to the language in the `config.json` file.
3. Add a json file with the same name as the language identifier in the `language` directory.
   - You can copy the original json file and rename it.
4. Translate the contents of the `tip` attribute.

## 3. Add a new completion

1. Run it in the project root directory. `.\script\create.ps1`
   - For the convenience of debugging, `create.ps1` will link the created completion directory to the `completions` directory of the `PSCompletions` module.
     - So `PSCompletions` module must be installed and imported before running `create.ps1`.
       - `Install-Module PSCompletions -Scope CurrentUser`
       - `Import-Module PSCompletions`
   - After the `PR` is committed and merged, you should use `psc rm` to remove this completion and `psc add` to re-add it.
2. Follow the prompts.
3. Modify the new completion.
4. Modify `config.json` as required.
