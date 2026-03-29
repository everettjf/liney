import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docs: [
    'intro',
    {
      type: 'category',
      label: 'Guides',
      collapsed: false,
      items: [
        'guides/getting-started',
        'guides/command-palette-and-quick-commands',
        'guides/overview-and-canvas',
        'guides/diff-and-review',
        'guides/hidden-features',
      ],
    },
    {
      type: 'category',
      label: 'Workflows',
      collapsed: false,
      items: [
        'workflows/worktrees-and-sessions',
        'workflows/remote-sessions-and-ssh',
        'workflows/agents-and-hapi',
        'workflows/workspace-workflows',
      ],
    },
  ],
};

export default sidebars;
