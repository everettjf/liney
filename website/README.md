# Liney Website

The `website/` directory is a Docusaurus site for the public Liney website and product documentation.

## Local development

```bash
npm install
npm start
```

## Build

```bash
npm run build
```

## Structure

- `docs/`: Markdown documentation rendered by Docusaurus
- `src/pages/`: custom landing pages and route pages
- `src/css/`: global Docusaurus theme overrides
- `static/`: images and other public assets copied into the final site

## Documentation authoring

Add product docs as Markdown files under `docs/` and register their navigation in `sidebars.ts`.
```
