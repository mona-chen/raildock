# RailDock - Technical Specification

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| react | ^19.2.0 | UI framework |
| react-dom | ^19.2.0 | DOM rendering |
| react-router-dom | ^7.14.1 | Multi-page routing |
| three | ^0.184.0 | 3D spline tunnel hero effect |
| meshline | ^3.3.1 | MeshLine for 3D tube trail |
| gsap | ^3.15.0 | Scroll animations, hero sequence, transitions |
| @gsap/react | ^2.1.2 | GSAP React integration (useGSAP) |
| lucide-react | ^0.562.0 | Icons throughout |
| framer-motion | ^12.38.0 | Page transitions, UI micro-interactions |
| class-variance-authority | ^0.7.1 | Component variant styling |
| clsx | ^2.1.1 | Conditional classnames |
| tailwind-merge | ^3.4.0 | Tailwind class deduplication |
| typescript | ~5.9.3 | Type checking |
| vite | ^7.2.4 | Build tool |
| @vitejs/plugin-react | ^5.1.1 | Vite React plugin |
| tailwindcss | ^3.4.19 | Utility CSS |
| postcss | ^8.5.6 | CSS processing |
| autoprefixer | ^10.4.23 | CSS vendor prefixes |

### Backend (Ruby)

| Gem | Version | Purpose |
|-----|---------|---------|
| rails | ~> 8.1.1 | Web framework |
| pg | ~> 1.1 | PostgreSQL adapter |
| puma | >= 5.0 | Web server |
| jwt | ~> 2.8 | JSON Web Tokens |
| lockbox | ~> 2.0 | Encryption at rest |
| net-ssh | ~> 7.2 | SSH for Dokku |
| net-scp | ~> 4.0 | SCP for file transfer |
| rack-attack | latest | Rate limiting |
| concurrent-ruby | latest | Thread-safe collections |
| solid_cache | latest | Cache backend |
| solid_queue | latest | Job queue |
| solid_cable | latest | ActionCable backend |

## Component Inventory

### Layout

| Component | Source | Notes |
|-----------|--------|-------|
| Navigation | Custom | Fixed glassmorphism nav, changes on scroll past hero. Contains scroll-aware transparency state. |
| Footer | Custom | 4-column grid, reused across all pages. |

### Sections (Home Page)

| Component | Source | Notes |
|-----------|--------|-------|
| HeroSection | Custom | Contains HybridRenderer (3D + 2D canvas), content overlay, CTA buttons. Most complex section. |
| LogoMarquee | Custom | CSS animation infinite scroll, 12 logos in flex row. |
| PlatformOverview | Custom | 3-column feature card grid. |
| HowItWorks | Custom | 3-step layout with dashed connector lines. |
| FeatureShowcase | Custom | 3x2 image grid with scroll-triggered center reveal (simplified from full 3D to CSS/GL fade). |
| DeploymentSources | Custom | Two-column with accordion left, interactive terminal right. |
| MetricsPreview | Custom | Browser-frame mockup with animated bar chart. |
| Testimonials | Custom | Horizontal scroll snap row of testimonial cards. |
| CTABanner | Custom | Simple centered CTA section. |

### Pages

| Component | Source | Notes |
|-----------|--------|-------|
| HomePage | Custom | Composes all home sections. |
| DashboardPage | Custom | Full demo dashboard - the star feature. Local state only, no backend. |
| PricingPage | Custom | Pricing tiers + FAQ accordion. |

### Dashboard Components (Demo Mode)

| Component | Source | Notes |
|-----------|--------|-------|
| DashboardLayout | Custom | Flex row: sidebar + canvas + right panel. |
| Sidebar | Custom | Project list, system nav, user avatar. |
| Canvas | Custom | Dark dot-grid background, draggable service cards, SVG connection lines. |
| ServiceCard | Custom | Draggable node, 200px wide, shows icon, name, status. |
| TopBar | Custom | Breadcrumb, env tabs, deploy/add buttons. |
| RightPanel | Custom | Collapsible 320px panel with Settings/Variables/Logs/Metrics tabs. |
| LogViewer | Custom | Color-coded streaming logs, auto-scroll. |
| MetricsChart | Custom | CPU/memory bar charts with random data updates. |
| AddServiceModal | Custom | Modal to add new service types. |
| Toast | Custom | Deployment notification toasts. |

### Reusable Components

| Component | Source | Notes |
|-----------|--------|-------|
| PillButton | Custom | Variant: primary (teal), secondary (outline), ghost. Used everywhere. |
| SectionHeader | Custom | Eyebrow + headline + subline pattern repeated in multiple sections. |
| FeatureCard | Custom | Icon circle + title + description. Used in PlatformOverview. |
| TestimonialCard | Custom | Avatar + name + role + quote + stars. |
| PricingCard | Custom | Name + price + features + CTA. 3 variants (Free/Pro/Enterprise). |
| BrowserFrame | Custom | Mock browser chrome for MetricsPreview. |
| Accordion | Custom | Expandable items for FAQ and DeploymentSources. |

### 3D/Canvas Components

| Component | Source | Notes |
|-----------|--------|-------|
| SplineScene | Custom | Three.js CatmullRomCurve3 tube with MeshLine, grid floor, animated shader. Renders to its own canvas. |
| ParticleCanvas | Custom | HTML5 Canvas 2D, 500 particles, Brownian motion, mouse repulsion. Clip-path portal reveals SplineScene beneath. |
| HybridRenderer | Custom | Manages both SplineScene and ParticleCanvas, handles resize, coordinates portal position. |

## Animation Implementation

| Animation | Library | Implementation Approach | Complexity |
|-----------|---------|------------------------|------------|
| 3D Spline Fly-Through | Three.js + meshline | CatmullRomCurve3 path, camera follows path at 0.00045/frame. MeshLine with rainbow dash texture. Animated vertex shader with simplex noise displacement. Grid floor with reflection. | **High** 🔒 |
| 2D Particle Field | Canvas 2D API | 500 particles with Brownian motion, radial gradient auras, mouse repulsion, wraparound. Custom Particle class with update/render cycle. | **High** 🔒 |
| Clip Portal with Liquid Border | CSS clip-path + SVG filter | clip-path:inset() on particle canvas reveals 3D scene. SVG feMorphology+feTurbulence+feDisplacementMap creates liquid border. Animated feTurbulence seed. | **High** 🔒 |
| Portal Drag Interaction | GSAP Draggable + quickTo | GSAP Draggable on portal element. quickTo for smooth position updates. Velocity maps to 3D camera FOV (50-90). Spring return on release. | **High** 🔒 |
| Hero Load Sequence | GSAP timeline | 5-step timeline: 3D scene starts, particles fade in, portal border animates, headline words stagger, CTAs slide up. | **Medium** |
| Scroll-Triggered Reveals | GSAP ScrollTrigger | Generic fade-up pattern for all sections. IntersectionObserver-like triggering at 'top 80%'. | **Low** |
| Feature Grid Center Reveal | GSAP ScrollTrigger | Center cell scales up while surrounding cells fade out. Simplified from full 3D FLIP to CSS transforms + opacity. | **Medium** |
| Logo Marquee | CSS @keyframes | translateX(0) to translateX(-50%), 60s linear infinite. Duplicate logo set for seamless loop. | **Low** |
| Terminal Typing | GSAP | Character-by-character reveal of terminal content on tab switch. | **Medium** |
| Bar Chart Stagger | GSAP ScrollTrigger | Bars animate from height:0 with 0.1s stagger when scrolled into view. | **Low** |
| Service Card Drag | Pointer Events | Custom drag handler updates x/y state. SVG bezier connections redraw on position change. | **Medium** |
| Connection Pulse | CSS animation | stroke-dashoffset animation on SVG path for flowing data effect. | **Low** |
| Metrics Live Update | setInterval | Random data every 2s, CSS transition on bar height. | **Low** |
| Log Stream | setInterval | New lines every 500ms during deployment, auto-scroll to bottom. | **Low** |
| Page Transitions | Framer Motion | AnimatePresence with fade/slide on route change. | **Low** |
| Nav Scroll Effect | Scroll event listener | Toggle glassmorphism class based on scroll position past hero height. | **Low** |
| Card Hover Effects | CSS transitions | translateY(-4px) + shadow on hover. 0.3s ease. | **Low** |
| Button Hover Effects | CSS transitions | Background darken, scale(1.02). 0.2s ease. | **Low** |
| Testimonial Scroll Snap | CSS scroll-snap | scroll-snap-type: x mandatory on container. | **Low** |
| Deploy Toast | Framer Motion | Animate in from top, auto-dismiss after 3s. | **Low** |

## State & Logic

### Dashboard State (React Context)

The dashboard demo uses a single `DashboardContext` with `useReducer` to manage all state:

- **projects**: Array of project objects (id, name, services[])
- **activeProject**: Currently selected project ID
- **activeService**: Currently selected service ID (for right panel)
- **services**: Map of service objects (id, name, type, status, position{x,y}, variables[], logs[], metrics{cpu,memory})
- **connections**: Array of {from, to} pairs for SVG lines
- **rightPanelTab**: Active tab in right panel (settings/variables/logs/metrics)
- **deploymentState**: 'idle' | 'deploying' | 'success' | 'failed'
- **toasts**: Array of toast notifications

### Key Interactions

**Drag System**: Custom pointer-event hook (`useDraggable`) that captures mousedown/mousemove/mouseup, computes delta from initial position, updates service position in state. Connection SVG paths recalculate from card edge points on each position change.

**Log Streaming**: During deployment, a `setInterval` generates realistic Dokku-style log lines ("-----> Building app...", "-----> Node.js detected", etc.) and appends to the active service's log array. Log viewer uses `useRef` to auto-scroll to bottom.

**Metrics Simulation**: `setInterval` every 2s randomizes CPU (10-80%) and memory (20-90%) values for running services. Bar charts use CSS `transition: height 0.5s ease` for smooth changes.

**Portal Position (Hero)**: Managed by HybridRenderer class. Lissajous pattern when idle, GSAP Draggable when interacting. Position state updates clip-path inset values on the particle canvas.

## Other Key Decisions

### Routing
React Router v6 with BrowserRouter. Three routes: `/` (Home), `/dashboard` (Demo), `/pricing` (Pricing). Dashboard route is the key destination - the "View Demo" CTA links here.

### No Backend
The entire application is frontend-only. The dashboard demo simulates all Dokku operations with mock data and timers. In production, a real backend would proxy SSH commands to a Dokku host.

### Canvas Architecture
The hero uses two separate `<canvas>` elements stacked with z-index. The 3D canvas (Three.js) is at z-index 0, the 2D particle canvas at z-index 1. The particle canvas has `clip-path: inset()` that creates the portal hole revealing the 3D scene. A separate div with SVG filter creates the liquid border effect around the portal edge.

### Responsive Strategy
Desktop-first design. Breakpoint at 768px:
- Hero portal shrinks to 80vw
- Particle count drops to 200
- Feature grid becomes single column
- Dashboard sidebar collapses to icon-only or hamburger
- How It Works steps stack vertically

### Performance
- Cap DPR at 2 for both canvases
- Use `requestAnimationFrame` for all animation loops
- Pause 3D and particle animations when hero is not visible (IntersectionObserver)
- Lazy load dashboard page with React.lazy + Suspense

### Accessibility
- `prefers-reduced-motion`: Disable Lissajous, reduce particle speed to 10%
- All canvas elements have `role="img"` and `aria-label`
- Keyboard navigation for portal (arrow keys)
- Focus visible states on all interactive elements
