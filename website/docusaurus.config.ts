import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Liney',
  tagline: 'Native macOS workspace for worktrees, terminal sessions, and parallel coding flow.',
  favicon: 'favicon.ico',
  future: {
    v4: true,
  },
  url: 'https://liney.app',
  baseUrl: '/',
  organizationName: 'everettjf',
  projectName: 'liney',
  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },
  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          routeBasePath: 'docs',
          editUrl: 'https://github.com/everettjf/liney/tree/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],
  themeConfig: {
    image: 'screenshot.png',
    colorMode: {
      defaultMode: 'dark',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'Liney',
      logo: {
        alt: 'Liney logo',
        src: 'appicon_32x32.png',
      },
      items: [
        {to: '/', label: 'Home', position: 'left'},
        {to: '/docs/intro', label: 'Documentation', position: 'left'},
        {href: 'https://github.com/everettjf/liney/releases', label: 'Download', position: 'right'},
        {href: 'https://github.com/everettjf/liney', label: 'GitHub', position: 'right'},
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Product',
          items: [
            {label: 'Home', to: '/'},
            {label: 'Download', href: 'https://github.com/everettjf/liney/releases'},
            {label: 'GitHub', href: 'https://github.com/everettjf/liney'},
          ],
        },
        {
          title: 'Documentation',
          items: [
            {label: 'Getting Started', to: '/docs/guides/getting-started'},
            {label: 'Worktrees & Sessions', to: '/docs/workflows/worktrees-and-sessions'},
            {label: 'Hidden Features', to: '/docs/guides/hidden-features'},
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} Liney.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
