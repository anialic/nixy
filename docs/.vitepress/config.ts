import { defineConfig } from "vitepress";

export default defineConfig({
  title: "nixy",
  description: "Structured configuration for Nix fleets",
  base: "/nixy/",
  themeConfig: {
    nav: [
      { text: "Guide", link: "/guide" },
      { text: "API", link: "/api" },
      {
        text: "GitHub",
        link: "https://github.com/cuskiy/nixy",
      },
    ],
    sidebar: [
      {
        text: "Introduction",
        items: [
          { text: "Getting Started", link: "/getting-started" },
          { text: "Guide", link: "/guide" },
        ],
      },
      {
        text: "Reference",
        items: [
          { text: "Advanced", link: "/advanced" },
          { text: "API", link: "/api" },
        ],
      },
    ],
  },
});
