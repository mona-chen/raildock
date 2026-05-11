import { useEffect, useRef } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight, Github, BarChart3, ScrollText, Layers, GitBranch, Database, Shield, Sparkles } from 'lucide-react'
import gsap from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'

gsap.registerPlugin(ScrollTrigger)

const features = [
  { icon: GitBranch, title: 'Git Push to Deploy', desc: 'Connect your repo and deploy on every push. Supports 20+ languages via Dokku buildpacks.' },
  { icon: Database, title: 'One-Click Datastores', desc: 'PostgreSQL, Redis, MySQL, MongoDB. Provisioned instantly with automatic env variable injection.' },
  { icon: Layers, title: 'Visual Architecture', desc: 'See your entire infrastructure on a canvas. Services, connections, and health at a glance.' },
  { icon: BarChart3, title: 'Real-time Metrics', desc: 'CPU, memory, disk, and network monitoring with beautiful charts and configurable alerts.' },
  { icon: ScrollText, title: 'Structured Logs', desc: 'Filter, search, and stream logs in real-time. JSON structured logging with 90-day retention.' },
  { icon: Shield, title: 'Self-Hosted & Open Source', desc: 'Run on your own servers. Zero vendor lock-in. Full SSH and CLI access via Dokku.' },
]

const steps = [
  { num: '01', title: 'Connect', desc: 'Link your Git repository or push directly. RailDock auto-detects your framework and language.' },
  { num: '02', title: 'Configure', desc: 'Set environment variables, add datastores, and define domains through the visual canvas.' },
  { num: '03', title: 'Deploy', desc: 'Every push triggers a deployment. Zero-downtime deploys with automatic rollback on failure.' },
]

const testimonials = [
  { name: 'Sarah Chen', role: 'Platform Engineer, TechCorp', quote: 'RailDock cut our deployment time from hours to minutes. The visual canvas makes managing microservices actually enjoyable.', color: 'from-rail-purple to-rail-blue' },
  { name: 'Marcus Johnson', role: 'CTO, StartupXYZ', quote: 'We migrated from Heroku and never looked back. Self-hosted means we control our infrastructure and our costs.', color: 'from-rail-orange to-rail-yellow' },
  { name: 'Priya Sharma', role: 'DevOps Lead, ScaleUp', quote: 'The Dokku integration is seamless. I get the simplicity of a PaaS with the flexibility of running on my own servers.', color: 'from-rail-blue to-rail-teal' },
]

export default function HomePage() {
  const heroRef = useRef<HTMLDivElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)

  // Particle animation
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    let w = window.innerWidth
    let h = window.innerHeight
    canvas.width = w * dpr
    canvas.height = h * dpr
    ctx.scale(dpr, dpr)

    const particles = Array.from({ length: 200 }, () => ({
      x: Math.random() * w, y: Math.random() * h,
      vx: (Math.random() - 0.5) * 0.3, vy: (Math.random() - 0.5) * 0.3,
      r: Math.random() * 1.2 + 0.3, alpha: Math.random() * 0.4 + 0.1,
      color: ['139,92,246', '59,130,246', '34,197,94', '20,184,166', '249,115,22'][Math.floor(Math.random() * 5)],
    }))

    let mouseX = -1000, mouseY = -1000
    const onMove = (e: MouseEvent) => { mouseX = e.clientX; mouseY = e.clientY }
    window.addEventListener('mousemove', onMove, { passive: true })

    let animId: number
    const animate = () => {
      ctx.clearRect(0, 0, w, h)
      for (const p of particles) {
        p.vx += (Math.random() - 0.5) * 0.015
        p.vy += (Math.random() - 0.5) * 0.015
        p.vx *= 0.995; p.vy *= 0.995
        const dx = p.x - mouseX, dy = p.y - mouseY, dist = Math.sqrt(dx * dx + dy * dy)
        if (dist < 200 && dist > 0) { const f = (200 - dist) / 200 * 0.4; p.vx += (dx / dist) * f; p.vy += (dy / dist) * f }
        p.x += p.vx; p.y += p.vy
        if (p.x < -50) p.x = w + 50; if (p.x > w + 50) p.x = -50
        if (p.y < -50) p.y = h + 50; if (p.y > h + 50) p.y = -50
        ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2)
        ctx.fillStyle = `rgba(${p.color}, ${p.alpha})`; ctx.fill()
        const grad = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, p.r * 5)
        grad.addColorStop(0, `rgba(${p.color}, ${p.alpha * 0.1})`); grad.addColorStop(1, `rgba(${p.color}, 0)`)
        ctx.fillStyle = grad; ctx.fill()
      }
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x, dy = particles[i].y - particles[j].y
          const dist = Math.sqrt(dx * dx + dy * dy)
          if (dist < 150) {
            ctx.beginPath(); ctx.moveTo(particles[i].x, particles[i].y); ctx.lineTo(particles[j].x, particles[j].y)
            ctx.strokeStyle = `rgba(139,92,246, ${0.03 * (1 - dist / 150)})`; ctx.lineWidth = 0.5; ctx.stroke()
          }
        }
      }
      animId = requestAnimationFrame(animate)
    }
    animate()
    const onResize = () => { w = window.innerWidth; h = window.innerHeight; canvas.width = w * dpr; canvas.height = h * dpr; ctx.setTransform(dpr, 0, 0, dpr, 0, 0) }
    window.addEventListener('resize', onResize, { passive: true })
    return () => { cancelAnimationFrame(animId); window.removeEventListener('mousemove', onMove); window.removeEventListener('resize', onResize) }
  }, [])

  // Scroll animations
  useEffect(() => {
    const ctx = gsap.context(() => {
      gsap.utils.toArray<HTMLElement>('.reveal').forEach(el => {
        gsap.fromTo(el, { opacity: 0, y: 30 }, {
          opacity: 1, y: 0, duration: 0.7, ease: 'power2.out',
          scrollTrigger: { trigger: el, start: 'top 85%' }
        })
      })
    })
    return () => ctx.revert()
  }, [])

  return (
    <div className="min-h-screen bg-[#0D0D0F]">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 h-14 flex items-center bg-[#0D0D0F]/80 backdrop-blur-xl border-b border-[rgba(255,255,255,0.06)]">
        <div className="max-w-7xl mx-auto w-full px-6 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-[rgba(139,92,246,0.2)] flex items-center justify-center border border-[rgba(139,92,246,0.3)]">
              <span className="text-rail-purple text-xs font-bold">RD</span>
            </div>
            <span className="text-sm font-bold text-white">RailDock</span>
          </Link>
          <div className="hidden md:flex items-center gap-6">
            {[
              { label: 'Features', href: '#features' },
              { label: 'Docs', href: '#' },
              { label: 'Pricing', href: '/pricing' },
              { label: 'Enterprise', href: '#' },
            ].map(item => (
              <a key={item.label} href={item.href} className="text-sm text-[#6B6B7B] hover:text-white transition-colors">{item.label}</a>
            ))}
          </div>
          <div className="flex items-center gap-3">
            <Link to="/dashboard" className="px-3 py-1.5 text-xs font-medium text-[#A0A0B0] border border-[rgba(255,255,255,0.1)] rounded-lg hover:bg-[rgba(255,255,255,0.06)] hover:text-white transition-all">
              Dashboard
            </Link>
            <Link to="/dashboard" className="px-3 py-1.5 text-xs font-medium text-white bg-rail-purple rounded-lg hover:bg-rail-purple-dark transition-all">
              Deploy
            </Link>
          </div>
        </div>
      </nav>

      {/* Hero */}
      <section ref={heroRef} className="relative min-h-screen flex items-center pt-14 overflow-hidden">
        <canvas ref={canvasRef} className="absolute inset-0 w-full h-full" />
        {/* Glow orbs */}
        <div className="absolute top-20 right-20 w-[600px] h-[600px] rounded-full opacity-20 blur-[120px]" style={{ background: 'radial-gradient(circle, rgba(139,92,246,0.4) 0%, transparent 70%)' }} />
        <div className="absolute bottom-0 left-0 w-[500px] h-[500px] rounded-full opacity-15 blur-[100px]" style={{ background: 'radial-gradient(circle, rgba(59,130,246,0.3) 0%, transparent 70%)' }} />

        {/* Floating Dashboard Preview */}
        <div className="absolute right-8 top-1/2 -translate-y-1/2 w-[55%] max-w-[680px] hidden lg:block pointer-events-none z-[2]">
          <div className="relative animate-[float_6s_ease-in-out_infinite]">
            <div className="bg-[#151518]/90 backdrop-blur-sm rounded-xl border border-[rgba(255,255,255,0.08)] shadow-2xl overflow-hidden">
              <div className="h-8 bg-[#0D0D0F] border-b border-[rgba(255,255,255,0.06)] flex items-center px-3 gap-2">
                <div className="flex gap-1.5"><div className="w-2.5 h-2.5 rounded-full bg-rail-red/60" /><div className="w-2.5 h-2.5 rounded-full bg-rail-yellow/60" /><div className="w-2.5 h-2.5 rounded-full bg-rail-green/60" /></div>
                <div className="ml-3 flex-1 h-5 bg-[#1A1A1F] rounded-md border border-[rgba(255,255,255,0.06)] flex items-center px-2">
                  <span className="text-[10px] text-[#4A4A55]">raildock.app/dashboard</span>
                </div>
              </div>
              <div className="p-4 bg-[#0D0D0F]">
                <div className="flex items-center justify-between mb-4">
                  <div className="flex items-center gap-2">
                    <div className="w-5 h-5 rounded bg-[rgba(139,92,246,0.2)] flex items-center justify-center"><span className="text-[8px] text-rail-purple font-bold">RD</span></div>
                    <span className="text-xs text-[#A0A0B0]">api-platform</span>
                    <span className="text-[10px] text-[#4A4A55]">/ production</span>
                  </div>
                  <div className="flex gap-1">
                    {['Architecture', 'Logs', 'Settings'].map(t => (
                      <span key={t} className={`text-[10px] px-2 py-0.5 rounded ${t === 'Architecture' ? 'bg-rail-purple text-white' : 'text-[#4A4A55]'}`}>{t}</span>
                    ))}
                  </div>
                </div>
                <div className="relative h-44 bg-[#151518] rounded-lg border border-[rgba(255,255,255,0.06)] dot-grid-dark">
                  {[{ x: 20, y: 16, name: 'backend-api', color: '#8B5CF6', icon: 'BA' }, { x: 220, y: 16, name: 'web-frontend', color: '#3B82F6', icon: 'WF' }, { x: 20, y: 100, name: 'postgres', color: '#3B82F6', icon: 'PG' }, { x: 220, y: 100, name: 'redis', color: '#EF4444', icon: 'RD' }].map((s, i) => (
                    <div key={i} className="absolute bg-[#1A1A1F] rounded-lg p-2.5 border border-[rgba(255,255,255,0.08)] shadow-lg" style={{ left: s.x, top: s.y, width: '120px' }}>
                      <div className="flex items-center gap-1.5 mb-1">
                        <div className="w-5 h-5 rounded flex items-center justify-center text-white text-[7px] font-bold" style={{ backgroundColor: s.color }}>{s.icon}</div>
                        <span className="text-[10px] font-medium text-white truncate">{s.name}</span>
                      </div>
                      <div className="flex items-center gap-1"><div className="w-1 h-1 rounded-full bg-rail-green" /><span className="text-[8px] text-[#4A4A55]">Running</span></div>
                    </div>
                  ))}
                  <svg className="absolute inset-0 w-full h-full pointer-events-none">
                    <line x1="80" y1="35" x2="220" y2="35" stroke="#8B5CF6" strokeWidth="1" strokeDasharray="3 3" opacity="0.3" />
                    <line x1="80" y1="35" x2="80" y2="120" stroke="#8B5CF6" strokeWidth="1" strokeDasharray="3 3" opacity="0.3" />
                  </svg>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Content */}
        <div className="relative z-10 max-w-7xl mx-auto px-6 w-full">
          <div className="max-w-lg">
            <span className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[rgba(139,92,246,0.1)] border border-[rgba(139,92,246,0.2)] text-rail-purple text-xs font-medium mb-6">
              <Sparkles size={12} /> Open-source deployment platform
            </span>
            <h1 className="text-5xl lg:text-6xl font-bold text-white tracking-tight leading-[1.1] mb-5">
              Ship software<br /><span className="text-transparent bg-clip-text bg-gradient-to-r from-rail-purple to-rail-blue">peacefully</span>
            </h1>
            <p className="text-base text-[#A0A0B0] mb-8 max-w-md leading-relaxed">
              The all-in-one platform powered by Dokku. Deploy anything without the complexity. Visual canvas, real-time logs, and zero-downtime deploys.
            </p>
            <div className="flex flex-wrap items-center gap-3">
              <Link to="/dashboard" className="inline-flex items-center gap-2 px-5 py-2.5 bg-rail-purple text-white text-sm font-medium rounded-lg hover:bg-rail-purple-dark transition-all">
                Deploy Now <ArrowRight size={14} />
              </Link>
              <Link to="/dashboard" className="inline-flex items-center gap-2 px-5 py-2.5 border border-[rgba(255,255,255,0.1)] text-[#A0A0B0] text-sm font-medium rounded-lg hover:bg-[rgba(255,255,255,0.06)] hover:text-white transition-all">
                View Demo
              </Link>
            </div>
            <p className="text-xs text-[#4A4A55] mt-4">Free forever. No credit card required. MIT Licensed.</p>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="py-24 bg-[#0D0D0F]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="text-center mb-16 reveal">
            <h2 className="text-3xl lg:text-4xl font-bold text-white mb-4">Built on Dokku, designed for humans</h2>
            <p className="text-[#6B6B7B] max-w-lg mx-auto">RailDock wraps the power of Dokku in an intuitive visual interface. Manage apps, databases, and services from a single canvas.</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {features.map((f, i) => (
              <div key={i} className="reveal group bg-[#151518] border border-[rgba(255,255,255,0.06)] rounded-xl p-6 hover:border-[rgba(255,255,255,0.12)] hover:bg-[#1A1A1F] transition-all">
                <div className="w-10 h-10 rounded-lg bg-[rgba(139,92,246,0.1)] flex items-center justify-center mb-4 group-hover:bg-[rgba(139,92,246,0.2)] transition-all">
                  <f.icon size={18} className="text-rail-purple" />
                </div>
                <h3 className="text-sm font-semibold text-white mb-2">{f.title}</h3>
                <p className="text-xs text-[#6B6B7B] leading-relaxed">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How It Works */}
      <section className="py-24 bg-[#151518]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="mb-12 reveal">
            <span className="text-xs font-semibold text-rail-orange uppercase tracking-wider">How it works</span>
            <h2 className="text-3xl lg:text-4xl font-bold text-white mt-3 max-w-md">From repository to production in three steps</h2>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 relative">
            <div className="hidden md:block absolute top-8 left-[16%] right-[16%] h-px border-t border-dashed border-[rgba(255,255,255,0.1)]" />
            {steps.map((s, i) => (
              <div key={i} className="reveal bg-[#1A1A1F] border border-[rgba(255,255,255,0.06)] rounded-xl p-8 relative" style={{ borderTop: '3px solid #8B5CF6' }}>
                <span className="font-mono text-5xl text-rail-purple/20 font-bold">{s.num}</span>
                <h3 className="text-lg font-semibold text-white mt-4 mb-2">{s.title}</h3>
                <p className="text-sm text-[#6B6B7B] leading-relaxed">{s.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Testimonials */}
      <section className="py-24 bg-[#0D0D0F]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="text-center mb-12 reveal">
            <h2 className="text-3xl lg:text-4xl font-bold text-white">Loved by developers</h2>
          </div>
          <div className="flex gap-5 overflow-x-auto pb-4 snap-x snap-mandatory scrollbar-hide">
            {testimonials.map((t, i) => (
              <div key={i} className="reveal flex-shrink-0 w-[360px] max-w-[90vw] snap-start bg-[#151518] border border-[rgba(255,255,255,0.06)] rounded-xl p-7">
                <div className="flex items-center gap-3 mb-5">
                  <div className={`w-11 h-11 rounded-full bg-gradient-to-br ${t.color}`} />
                  <div>
                    <h4 className="text-sm font-semibold text-white">{t.name}</h4>
                    <p className="text-xs text-[#4A4A55]">{t.role}</p>
                  </div>
                </div>
                <p className="text-sm text-[#A0A0B0] leading-relaxed italic">&ldquo;{t.quote}&rdquo;</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20 bg-[#151518]">
        <div className="max-w-7xl mx-auto px-6 text-center reveal">
          <h2 className="text-3xl lg:text-4xl font-bold text-white mb-4">Ready to deploy peacefully?</h2>
          <p className="text-[#6B6B7B] max-w-md mx-auto mb-8">Join thousands of developers shipping with RailDock. Free and open source forever.</p>
          <Link to="/dashboard" className="inline-flex items-center gap-2 px-6 py-3 bg-rail-purple text-white text-sm font-medium rounded-lg hover:bg-rail-purple-dark transition-all">
            Get Started <ArrowRight size={14} />
          </Link>
          <p className="text-[10px] text-[#4A4A55] mt-5 uppercase tracking-wider font-medium">MIT Licensed \u2022 Self-hosted \u2022 Community-driven</p>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-[#0D0D0F] border-t border-[rgba(255,255,255,0.06)] pt-14 pb-8">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-10">
            <div>
              <div className="flex items-center gap-2 mb-3">
                <div className="w-6 h-6 rounded bg-[rgba(139,92,246,0.2)] flex items-center justify-center"><span className="text-rail-purple text-[9px] font-bold">RD</span></div>
                <span className="text-sm font-bold text-white">RailDock</span>
              </div>
              <p className="text-xs text-[#4A4A55] max-w-[200px]">Open-source deployment platform powered by Dokku.</p>
            </div>
            {['Product', 'Developers', 'Company'].map(col => (
              <div key={col}>
                <h4 className="text-[10px] font-semibold text-white uppercase tracking-wider mb-3">{col}</h4>
                <div className="flex flex-col gap-2">
                  {col === 'Product' && ['Features', 'Pricing', 'Changelog', 'Roadmap'].map(i => (
                    <span key={i} className="text-xs text-[#4A4A55] hover:text-[#A0A0B0] transition-colors cursor-pointer">{i}</span>
                  ))}
                  {col === 'Developers' && ['Documentation', 'API Reference', 'GitHub', 'Community'].map(i => (
                    <span key={i} className="text-xs text-[#4A4A55] hover:text-[#A0A0B0] transition-colors cursor-pointer">{i}</span>
                  ))}
                  {col === 'Company' && ['Blog', 'About', 'Contact', 'Enterprise'].map(i => (
                    <span key={i} className="text-xs text-[#4A4A55] hover:text-[#A0A0B0] transition-colors cursor-pointer">{i}</span>
                  ))}
                </div>
              </div>
            ))}
          </div>
          <div className="mt-10 pt-5 border-t border-[rgba(255,255,255,0.06)] flex items-center justify-between">
            <p className="text-xs text-[#4A4A55]">2025 RailDock. All rights reserved.</p>
            <div className="flex items-center gap-4 text-[#4A4A55]">
              <Github size={16} className="hover:text-white transition-colors cursor-pointer" />
            </div>
          </div>
        </div>
      </footer>
    </div>
  )
}
