import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: "/PSCompletions/",
  title: "PSCompletions(psc)",
  locales: {
    "en-US": {
      label: "en-US (English)",
      description: "The document of PSCompletions module.",
      link: "/en-US"
    },
    "zh-CN": {
      label: "zh-CN (简体中文)",
      description: "PSCompletions 模块的文档说明",
      link: "/zh-CN"
    }
  },
  themeConfig: {
    socialLinks: [
      { icon: 'github', link: 'https://github.com/abgox/PSCompletions' },
      {
        icon: {
          svg: '<svg t="1718697878187" class="icon" viewBox="0 0 1024 1024" version="1.1" xmlns="http://www.w3.org/2000/svg" p-id="935" width="200" height="200"><path d="M512 1024C229.234 1024 0 794.766 0 512S229.234 0 512 0s512 229.234 512 512-229.234 512-512 512z m259.157-568.889l-290.759 0.014c-13.966 0-25.287 11.321-25.287 25.273l-0.028 63.218c0 13.966 11.306 25.287 25.273 25.287H657.38c13.966 0 25.287 11.307 25.287 25.273v12.644a75.847 75.847 0 0 1-75.847 75.847H366.606a25.287 25.287 0 0 1-25.287-25.273v-240.2a75.847 75.847 0 0 1 75.847-75.846l353.92-0.015c13.966 0 25.273-11.306 25.287-25.273l0.071-63.189c0-13.966-11.306-25.287-25.272-25.301l-353.992 0.014c-104.718-0.014-189.624 84.892-189.624 189.61v353.963c0 13.967 11.32 25.287 25.287 25.287h372.935c94.265 0 170.666-76.401 170.666-170.666v-145.38c0-13.952-11.32-25.273-25.287-25.273z" p-id="936"></path></svg>'
        },
        link: "https://gitee.com/abgox/PSCompletions"
      }
    ],
    search: {
      provider: 'local',
      options: {
        locales: {
          "zh-CN": {
            translations: {
              button: {
                buttonText: '搜索文档',
                buttonAriaLabel: '搜索文档'
              },
              modal: {
                displayDetails: "显示详细列表",
                noResultsText: '无法找到相关结果',
                resetButtonTitle: '清除查询条件',
                footer: {
                  selectText: '选择',
                  navigateText: '切换',
                  closeText: "关闭"
                }
              }
            }
          }
        }
      }
    },
    outline: "deep",
    footer: {
      message: 'Released under the <a href="https://github.com/abgox/PSCompletions/blob/main/LICENSE">MIT License</a>.',
      copyright: 'Copyright © 2023-present <a href="https://github.com/abgox">abgox</a>'
    }
  },
})
