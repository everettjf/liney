import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docs: [
    'intro',
    {
      type: 'category',
      label: 'Guides',
      items: ['guides/getting-started', 'guides/hidden-features'],
    },
    {
      type: 'category',
      label: 'Workflows',
      items: ['workflows/worktrees-and-sessions'],
    },
  ],
};

export default sidebars;
