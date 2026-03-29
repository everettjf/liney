import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import {useEffect, useMemo, useRef, useState, type MouseEvent} from 'react';
import styles from './index.module.css';

const githubUrl = 'https://github.com/everettjf/liney';
const releaseUrl = 'https://github.com/everettjf/liney/releases';
const brewCommand = 'brew update && brew install --cask everettjf/tap/liney';

const coreItems = [
  {
    title: 'Native orbit',
    text: 'A real macOS app with the speed, focus, and local feel you want when terminal work is the center of the workflow.',
  },
  {
    title: 'Worktree gravity',
    text: 'Repos, branches, and worktrees stay connected so parallel tasks do not drift into chaos.',
  },
  {
    title: 'Parallel flow',
    text: 'Keep coding, reviewing, debugging, and side quests alive at the same time without losing spatial context.',
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
];

const faqs = [
  {
    question: 'What is Liney?',
    answer: 'Liney is a native macOS workspace for repositories, Git worktrees, terminal sessions, and diff-heavy daily development.',
  },
  {
    question: 'Who is it for?',
    answer: 'Developers who keep multiple branches, worktrees, and shell tasks active at the same time.',
  },
  {
    question: 'Where is the documentation now?',
    answer: 'Liney now ships with a dedicated Docusaurus documentation section, with Markdown-based guides and structured navigation.',
  },
];

const orbitStats = [
  {value: 'Native', label: 'macOS workspace'},
  {value: 'Git', label: 'worktree aware'},
  {value: 'Parallel', label: 'terminal flows'},
];

function HomePage(): JSX.Element {
  const [pointer, setPointer] = useState({x: 0, y: 0});
  const [copied, setCopied] = useState(false);
  const [lightboxImage, setLightboxImage] = useState<{src: string; alt: string} | null>(null);
  const copyResetTimeoutRef = useRef<number | null>(null);

  const sparkles = useMemo(
    () =>
      Array.from({length: 12}, (_, index) => ({
        id: index,
        style: {
          left: `${8 + (index % 4) * 24 + ((index * 7) % 9)}%`,
          top: `${10 + Math.floor(index / 4) * 28 + ((index * 11) % 10)}%`,
          animationDelay: `${index * 0.45}s`,
          animationDuration: `${4.5 + (index % 5) * 0.6}s`,
        },
      })),
    [],
  );

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
    transform: `perspective(1200px) rotateX(${pointer.y * -8}deg) rotateY(${pointer.x * 10}deg) translate3d(${pointer.x * 10}px, ${pointer.y * 10}px, 0)`,
  };

  const shotStyle = {
    transform: `translate3d(${pointer.x * 10}px, ${pointer.y * 10}px, 0) scale(1.01)`,
  };

  return (
    <Layout
      title="Native macOS workspace for worktrees and terminal sessions"
      description="Liney is a native macOS workspace for repositories, worktrees, terminal sessions, and parallel coding flow.">
      <div className={styles.pageShell}>
        <div className={styles.spaceBackdrop} aria-hidden="true">
          <div className={`${styles.spaceGlow} ${styles.spaceGlow1}`} />
          <div className={`${styles.spaceGlow} ${styles.spaceGlow2}`} />
          <div className={`${styles.spaceGlow} ${styles.spaceGlow3}`} />
          <div className={`${styles.stars} ${styles.starsDense}`} />
          <div className={`${styles.stars} ${styles.starsSoft}`} />
        </div>

        <main className={styles.page}>
          <section className={styles.hero}>
            <div className={styles.heroCopyColumn}>
              <p className={styles.eyebrow}>Native macOS workspace</p>
              <h1 className={styles.heroTitle}>
                Liney
                <span className={styles.gradientText}> keeps parallel work visible.</span>
              </h1>
              <p className={styles.heroLead}>
                Liney turns repos, worktrees, and terminal sessions into one native workspace built for multi-threaded coding on macOS.
              </p>

              <div className={styles.heroActions}>
                <Link className="button button--primary button--lg" to="/docs/intro">
                  Read the docs
                </Link>
                <a className="button button--secondary button--lg" href={releaseUrl}>
                  Download latest build
                </a>
              </div>
            </div>

            <div className={styles.heroVisualWrap} onMouseMove={handlePointerMove} onMouseLeave={resetPointer}>
              <div className={styles.heroVisual} style={visualStyle}>
                <div className={styles.heroOrbitCard}>
                  {sparkles.map((sparkle) => (
                    <span key={sparkle.id} className={styles.heroSparkle} style={sparkle.style} />
                  ))}
                  <div className={`${styles.heroChip} ${styles.heroChipTop}`}>workspace map</div>
                  <div className={`${styles.heroChip} ${styles.heroChipBottom}`}>parallel sessions</div>
                  <button
                    className={styles.heroShotFrame}
                    type="button"
                    style={shotStyle}
                    onClick={() => openLightbox('/screenshot.png', 'Liney workspace showing repositories, worktrees, and terminal panes')}>
                    <img src="/screenshot.png" alt="Liney workspace showing repositories, worktrees, and terminal panes" />
                  </button>
                </div>
              </div>
            </div>
          </section>

          <section className={styles.orbitStrip} aria-label="Product highlights">
            {orbitStats.map((item) => (
              <article className={styles.orbitStat} key={item.label}>
                <p className={styles.orbitValue}>{item.value}</p>
                <p className={styles.orbitLabel}>{item.label}</p>
              </article>
            ))}
          </section>

          <section className={styles.section}>
            <div className={styles.sectionHeading}>
              <p className={styles.eyebrow}>Why it fits</p>
              <h2>Built around real repository flow.</h2>
              <p>Fast, native, and spatial. The app is designed around worktrees and active terminal context instead of flat terminal windows.</p>
            </div>

            <div className={styles.coreGrid}>
              {coreItems.map((item, index) => (
                <article className={styles.coreCard} key={item.title}>
                  <div className={styles.cardOrb}>0{index + 1}</div>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                </article>
              ))}
            </div>
          </section>

          <section className={styles.section}>
            <div className={styles.showcaseGrid}>
              <article className={`${styles.showcaseCard} ${styles.showcaseCardLarge}`}>
                <div>
                  <p className={styles.eyebrow}>Spatial clarity</p>
                  <h2>See the whole constellation of active work.</h2>
                  <p>Repos, worktrees, and terminals stay grouped so your mental model survives context switching.</p>
                </div>
                <div className={styles.showcaseShot}>
                  <button type="button" className={styles.showcaseShotButton} onClick={() => openLightbox('/screenshot1.png', 'Liney repository and workspace view')}>
                    <img src="/screenshot1.png" alt="Liney repository and workspace view" />
                  </button>
                </div>
              </article>

              <article className={styles.showcaseCard}>
                <p className={styles.eyebrow}>Terminal energy</p>
                <h3>Keep momentum alive.</h3>
                <p>Open long-running flows side by side and keep them discoverable instead of burying them in tabs.</p>
              </article>

              <article className={styles.showcaseCard}>
                <p className={styles.eyebrow}>Documentation</p>
                <h3>Now a real docs site.</h3>
                <p>The website now includes structured Markdown documentation with sidebars, stable links, and room for deeper guides.</p>
              </article>
            </div>
          </section>

          <section className={styles.section}>
            <div className={styles.sectionHeading}>
              <p className={styles.eyebrow}>Documentation</p>
              <h2>Start with a guide, not a guess.</h2>
              <p>The docs are split by actual usage: onboarding, worktree workflows, and the features people usually discover too late.</p>
            </div>

            <div className={styles.docsGrid}>
              {docsItems.map((item) => (
                <article className={styles.docsCard} key={item.title}>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                  <Link className={styles.docsLink} to={item.to}>
                    Open guide
                  </Link>
                </article>
              ))}
            </div>
          </section>

          <section className={styles.section}>
            <div className={styles.sectionHeading}>
              <p className={styles.eyebrow}>Install</p>
              <h2>Launch straight into the orbit.</h2>
            </div>

            <div className={styles.installGrid}>
              <article className={`${styles.installCard} ${styles.installCardHighlight}`}>
                <p className={styles.installTitle}>GitHub release</p>
                <p>Download the latest macOS build directly from GitHub Releases.</p>
                <a className="button button--primary" href={releaseUrl}>
                  Download latest build
                </a>
              </article>

              <article className={`${styles.installCard} ${styles.installCardCode}`}>
                <div className={styles.installCodeHead}>
                  <p className={styles.installTitle}>Homebrew</p>
                  <button className={styles.copyButton} type="button" onClick={handleCopy}>
                    {copied ? 'Copied' : 'Copy'}
                  </button>
                </div>
                <pre>{brewCommand}</pre>
              </article>
            </div>
          </section>

          <section className={styles.section}>
            <div className={styles.sectionHeading}>
              <p className={styles.eyebrow}>FAQ</p>
              <h2>Short answers for terminal people.</h2>
            </div>

            <div className={styles.faqGrid}>
              {faqs.map((faq) => (
                <article className={styles.faqCard} key={faq.question}>
                  <h3>{faq.question}</h3>
                  <p>{faq.answer}</p>
                </article>
              ))}
            </div>
          </section>

          <section className={styles.siteFooter}>
            <p>Built for native repository work on macOS.</p>
            <a href={githubUrl}>github.com/everettjf/liney</a>
          </section>
        </main>

        {lightboxImage ? (
          <div className={styles.lightbox} role="dialog" aria-modal="true" aria-label="Image preview" onClick={() => setLightboxImage(null)}>
            <button className={styles.lightboxClose} type="button" onClick={() => setLightboxImage(null)} aria-label="Close image preview">
              ×
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
