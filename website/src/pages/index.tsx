import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import {useEffect, useMemo, useRef, useState, type MouseEvent} from 'react';
import styles from './index.module.css';

const githubUrl = 'https://github.com/everettjf/liney';
const releaseUrl = 'https://github.com/everettjf/liney/releases';
const brewCommand = 'brew install --cask everettjf/tap/liney';

const features = [
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="3" width="7" height="7" rx="1.5" />
        <rect x="14" y="3" width="7" height="7" rx="1.5" />
        <rect x="3" y="14" width="7" height="7" rx="1.5" />
        <rect x="14" y="14" width="7" height="7" rx="1.5" />
      </svg>
    ),
    title: 'Spatial workspace',
    text: 'Repos, worktrees, and terminals live in one spatial layout. Your mental model survives context switches.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 3v12" />
        <circle cx="18" cy="6" r="3" />
        <circle cx="6" cy="18" r="3" />
        <path d="M18 9a9 9 0 0 1-9 9" />
      </svg>
    ),
    title: 'Git worktree native',
    text: 'First-class worktree support. Branch, review, and build in parallel without losing track of what goes where.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="4 17 10 11 4 5" />
        <line x1="12" y1="19" x2="20" y2="19" />
      </svg>
    ),
    title: 'Parallel terminals',
    text: 'Long-running tasks, builds, and debugging sessions stay visible and discoverable instead of buried in tabs.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 20h9" />
        <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z" />
      </svg>
    ),
    title: 'Diff & review',
    text: 'Built-in diff views tied to your workspace context. Review changes without leaving your flow.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
        <line x1="8" y1="21" x2="16" y2="21" />
        <line x1="12" y1="17" x2="12" y2="21" />
      </svg>
    ),
    title: 'Native macOS',
    text: 'Not Electron. A real macOS app with the speed, responsiveness, and system integration you expect.',
  },
  {
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="12" cy="12" r="3" />
        <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
      </svg>
    ),
    title: 'Agents & HAPI',
    text: 'Launch agent sessions and connect HAPI to your active workspace for AI-assisted development.',
  },
];

const docsItems = [
  {
    title: 'Getting Started',
    text: 'Set up your first repository, open sessions, and learn the sidebar signals.',
    to: '/docs/guides/getting-started',
  },
  {
    title: 'Worktrees & Sessions',
    text: 'Use multiple checkouts and terminal panes without losing your mental model.',
    to: '/docs/workflows/worktrees-and-sessions',
  },
  {
    title: 'Hidden Features',
    text: 'Surface the parts of Liney that are easy to miss but matter in daily use.',
    to: '/docs/guides/hidden-features',
  },
  {
    title: 'Agents & HAPI',
    text: 'Launch agent sessions and understand how HAPI attaches to the active workspace.',
    to: '/docs/workflows/agents-and-hapi',
  },
  {
    title: 'Remote Sessions',
    text: 'Save SSH targets, reuse remote shells, and keep remote work attached to repository context.',
    to: '/docs/workflows/remote-sessions-and-ssh',
  },
  {
    title: 'Overview & Canvas',
    text: 'Use higher-level surfaces that summarize active work and show live terminal context.',
    to: '/docs/guides/overview-and-canvas',
  },
];

const faqs = [
  {
    question: 'What is Liney?',
    answer: 'A native macOS workspace for repositories, Git worktrees, terminal sessions, and diff-heavy daily development.',
  },
  {
    question: 'Who is it for?',
    answer: 'Developers who keep multiple branches, worktrees, and shell tasks active at the same time.',
  },
  {
    question: 'Is it free and open source?',
    answer: 'Yes! Liney is completely free and open source under the Apache 2.0 license. The source code is available on GitHub. Pull requests are welcome — we love contributions from the community.',
  },
];

function HomePage(): JSX.Element {
  const [pointer, setPointer] = useState({x: 0, y: 0});
  const [copied, setCopied] = useState(false);
  const [lightboxImage, setLightboxImage] = useState<{src: string; alt: string} | null>(null);
  const copyResetTimeoutRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (copyResetTimeoutRef.current !== null) {
        window.clearTimeout(copyResetTimeoutRef.current);
      }
    };
  }, []);

  useEffect(() => {
    if (!lightboxImage) {
      return;
    }

    const previousOverflow = document.body.style.overflow;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setLightboxImage(null);
      }
    };

    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', handleKeyDown);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [lightboxImage]);

  const handlePointerMove = (event: MouseEvent<HTMLElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    setPointer({x, y});
  };

  const resetPointer = () => setPointer({x: 0, y: 0});

  const copyText = async (value: string) => {
    if (navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(value);
        return true;
      } catch {
        // Fall back when clipboard permissions are blocked.
      }
    }

    const textArea = document.createElement('textarea');
    textArea.value = value;
    textArea.setAttribute('readonly', '');
    textArea.style.position = 'fixed';
    textArea.style.top = '0';
    textArea.style.left = '0';
    textArea.style.opacity = '0';
    document.body.append(textArea);
    textArea.focus();
    textArea.select();
    textArea.setSelectionRange(0, value.length);

    try {
      return document.execCommand('copy');
    } finally {
      textArea.remove();
    }
  };

  const handleCopy = async () => {
    const didCopy = await copyText(brewCommand);

    if (copyResetTimeoutRef.current !== null) {
      window.clearTimeout(copyResetTimeoutRef.current);
    }

    if (didCopy) {
      setCopied(true);
      copyResetTimeoutRef.current = window.setTimeout(() => setCopied(false), 1600);
    }
  };

  const openLightbox = (src: string, alt: string) => setLightboxImage({src, alt});

  const visualStyle = {
    transform: `perspective(1200px) rotateX(${pointer.y * -6}deg) rotateY(${pointer.x * 8}deg)`,
  };

  return (
    <Layout
      title="Native macOS workspace for worktrees and terminal sessions"
      description="Liney is a native macOS workspace for repositories, worktrees, terminal sessions, and parallel coding flow.">
      <div className={styles.pageShell}>
        <div className={styles.starfield} aria-hidden="true">
          <div className={styles.starsSmall} />
          <div className={styles.starsMedium} />
          <div className={styles.starsLarge} />
          <div className={styles.shootingStar1} />
          <div className={styles.shootingStar2} />
          <div className={styles.shootingStar3} />
          <div className={styles.glow1} />
          <div className={styles.glow2} />
        </div>

        <main className={styles.page}>
          {/* Hero */}
          <section className={styles.hero}>
            <div className={styles.heroCopy}>
              <div className={styles.badge}>Cosmic native workspace</div>
              <h1 className={styles.heroTitle}>
                <span className={styles.heroTitleBrand}>"Liney"</span>{' '}
                <span className={styles.heroTitleAccent}>parallel orbit.</span>
              </h1>
              <p className={styles.heroLead}>
                Liney brings repos, worktrees, and terminal sessions into one native macOS workspace.
                Keep parallel work visible. Stay in flow.
              </p>

              <div className={styles.heroActions}>
                <Link className={styles.btnPrimary} to="/docs/intro">
                  Read the docs
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M3 8h10M9 4l4 4-4 4" />
                  </svg>
                </Link>
                <Link className={styles.btnSecondary} to="/docs/guides/getting-started">
                  Download Liney
                </Link>
              </div>
            </div>

            <div
              className={styles.heroVisualWrap}
              onMouseMove={handlePointerMove}
              onMouseLeave={resetPointer}>
              <div className={styles.heroVisual} style={visualStyle}>
                <button
                  className={styles.heroScreenshot}
                  type="button"
                  onClick={() => openLightbox('/screenshot.png', 'Liney workspace showing repositories, worktrees, and terminal panes')}>
                  <img
                    src="/screenshot.png"
                    alt="Liney workspace showing repositories, worktrees, and terminal panes"
                    loading="eager"
                  />
                </button>
              </div>
            </div>
          </section>

          {/* Features */}
          <section className={styles.section}>
            <div className={styles.sectionHeader}>
              <h2 className={styles.sectionTitle}>Everything you need for parallel work</h2>
              <p className={styles.sectionSub}>
                Built from scratch for macOS. No Electron, no compromises.
              </p>
            </div>

            <div className={styles.featureGrid}>
              {features.map((item) => (
                <article className={styles.featureCard} key={item.title}>
                  <div className={styles.featureIcon}>{item.icon}</div>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                </article>
              ))}
            </div>
          </section>

          {/* Showcase */}
          <section className={styles.section}>
            <div className={styles.showcase}>
              <div className={styles.showcaseText}>
                <h2 className={styles.sectionTitle}>See everything at a glance</h2>
                <p>
                  Repos, worktrees, and terminals stay grouped so your mental model survives context switching.
                  No more hunting through tabs or losing track of that build you started.
                </p>
                <Link className={styles.showcaseLink} to="/docs/guides/getting-started">
                  Learn how it works
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M3 8h10M9 4l4 4-4 4" />
                  </svg>
                </Link>
              </div>
              <div className={styles.showcaseImage}>
                <button
                  type="button"
                  className={styles.showcaseImgBtn}
                  onClick={() => openLightbox('/screenshot1.png', 'Liney repository and workspace view')}>
                  <img src="/screenshot1.png" alt="Liney repository and workspace view" loading="lazy" />
                </button>
              </div>
            </div>
          </section>

          {/* Docs */}
          <section className={styles.section}>
            <div className={styles.sectionHeader}>
              <h2 className={styles.sectionTitle}>Documentation</h2>
              <p className={styles.sectionSub}>
                Guides, workflows, and everything you need to get the most out of Liney.
              </p>
            </div>

            <div className={styles.docsGrid}>
              {docsItems.map((item) => (
                <Link className={styles.docsCard} key={item.title} to={item.to}>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                  <span className={styles.docsArrow}>
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M3 8h10M9 4l4 4-4 4" />
                    </svg>
                  </span>
                </Link>
              ))}
            </div>
          </section>

          {/* FAQ */}
          <section className={styles.section}>
            <div className={styles.sectionHeader}>
              <h2 className={styles.sectionTitle}>FAQ</h2>
            </div>

            <div className={styles.faqList}>
              {faqs.map((faq) => (
                <details className={styles.faqItem} key={faq.question} open>
                  <summary>{faq.question}</summary>
                  <p>{faq.answer}</p>
                </details>
              ))}
            </div>
          </section>

          {/* Footer */}
          <footer className={styles.siteFooter}>
            <div className={styles.footerInner}>
              <p>Built for native repository work on macOS.</p>
              <a href={githubUrl}>GitHub</a>
            </div>
          </footer>
        </main>

        {lightboxImage ? (
          <div className={styles.lightbox} role="dialog" aria-modal="true" aria-label="Image preview" onClick={() => setLightboxImage(null)}>
            <button className={styles.lightboxClose} type="button" onClick={() => setLightboxImage(null)} aria-label="Close image preview">
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 5l10 10M15 5L5 15" />
              </svg>
            </button>
            <div className={styles.lightboxPanel} onClick={(event) => event.stopPropagation()}>
              <img className={styles.lightboxImage} src={lightboxImage.src} alt={lightboxImage.alt} />
            </div>
          </div>
        ) : null}
      </div>
    </Layout>
  );
}

export default HomePage;
