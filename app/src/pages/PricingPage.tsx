import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Check, ChevronDown, Github } from 'lucide-react'

const plans = [
  {
    name: 'Free',
    price: '$0',
    period: '/month',
    desc: 'Perfect for getting started and deploying small apps',
    features: ['3 projects', '5 services per project', 'Community support', 'Basic metrics', 'Git push deploy', 'Environment variables'],
    cta: 'Start Free',
    popular: false,
  },
  {
    name: 'Pro',
    price: '$29',
    period: '/month',
    desc: 'For professional developers and teams shipping production apps',
    features: ['Unlimited projects', '20 services per project', 'Priority support', 'Advanced metrics & alerts', 'Custom domains & SSL', 'Team collaboration', 'Database backups', 'Rollback history'],
    cta: 'Upgrade to Pro',
    popular: true,
  },
  {
    name: 'Enterprise',
    price: 'Custom',
    period: '',
    desc: 'For teams shipping at scale with compliance and support needs',
    features: ['Everything in Pro', 'Unlimited services', 'SSO & SAML', 'Audit logs', 'SLA guarantee', 'Dedicated support', 'Custom integrations', 'On-premise option'],
    cta: 'Contact Sales',
    popular: false,
  },
]

const faqs = [
  { q: 'Is RailDock really free?', a: 'Yes! RailDock is open source and free to self-host. The Free tier on our managed offering is also free forever. You only pay if you choose to upgrade for additional features.' },
  { q: 'Do I need my own servers?', a: 'For self-hosting, yes — you need a Linux server (VM, VPS, or bare metal) with Docker installed. RailDock sits on top of Dokku, which manages all the container orchestration for you.' },
  { q: 'How does Dokku integration work?', a: "RailDock communicates with your Dokku instance via SSH commands. It provides a visual layer on top of Dokku's CLI, translating your canvas actions into Dokku commands automatically." },
  { q: 'Can I migrate from Heroku?', a: "Absolutely. RailDock uses the same buildpack-based deployment model as Heroku. Most apps can be migrated by simply changing your Git remote from Heroku to your RailDock instance." },
  { q: 'What languages are supported?', a: 'RailDock supports all languages that Dokku buildpacks support: Node.js, Python, Ruby, Go, PHP, Java, Scala, Rust, and more. You can also use custom Dockerfiles for any language.' },
]

export default function PricingPage() {
  const [openFaq, setOpenFaq] = useState(0)

  return (
    <div className="min-h-screen bg-[#0D0D0F]">
      {/* Nav */}
      <nav className="h-14 flex items-center bg-[#0D0D0F]/80 backdrop-blur-xl border-b border-[rgba(255,255,255,0.06)]">
        <div className="max-w-7xl mx-auto w-full px-6 flex items-center justify-between">
          <Link to="/" className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-[rgba(139,92,246,0.2)] flex items-center justify-center border border-[rgba(139,92,246,0.3)]">
              <span className="text-rail-purple text-xs font-bold">RD</span>
            </div>
            <span className="text-sm font-bold text-white">RailDock</span>
          </Link>
          <div className="flex items-center gap-3">
            <Link to="/dashboard" className="px-3 py-1.5 text-xs font-medium text-[#A0A0B0] border border-[rgba(255,255,255,0.1)] rounded-lg hover:bg-[rgba(255,255,255,0.06)] hover:text-white transition-all">Dashboard</Link>
            <Link to="/dashboard" className="px-3 py-1.5 text-xs font-medium text-white bg-rail-purple rounded-lg hover:bg-rail-purple-dark transition-all">Deploy</Link>
          </div>
        </div>
      </nav>

      <main className="pt-16 pb-20">
        {/* Hero */}
        <div className="max-w-3xl mx-auto px-6 text-center mb-14">
          <h1 className="text-4xl lg:text-5xl font-bold text-white mb-4">Simple, transparent pricing</h1>
          <p className="text-[#6B6B7B] text-lg">Start free. Scale as you grow. No surprises.</p>
        </div>

        {/* Plans */}
        <div className="max-w-6xl mx-auto px-6 grid grid-cols-1 md:grid-cols-3 gap-5 mb-20">
          {plans.map((p, i) => (
            <div key={i} className={`relative bg-[#151518] rounded-xl p-8 border ${p.popular ? 'border-rail-purple/40 shadow-lg shadow-rail-purple/5' : 'border-[rgba(255,255,255,0.06)]'}`}>
              {p.popular && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1 bg-[rgba(139,92,246,0.15)] text-rail-purple text-[11px] font-semibold rounded-full border border-[rgba(139,92,246,0.3)]">
                  Most Popular
                </span>
              )}
              <h3 className="text-base font-semibold text-white mb-2">{p.name}</h3>
              <div className="flex items-baseline gap-1 mb-2">
                <span className="text-4xl font-bold text-white">{p.price}</span>
                <span className="text-sm text-[#4A4A55]">{p.period}</span>
              </div>
              <p className="text-xs text-[#6B6B7B] mb-6">{p.desc}</p>
              <ul className="space-y-2.5 mb-8">
                {p.features.map((f, j) => (
                  <li key={j} className="flex items-start gap-2.5 text-sm">
                    <Check size={14} className="text-rail-green flex-shrink-0 mt-0.5" />
                    <span className="text-[#A0A0B0]">{f}</span>
                  </li>
                ))}
              </ul>
              <Link
                to="/dashboard"
                className={`block w-full text-center py-2.5 rounded-lg font-medium text-sm transition-all ${
                  p.popular ? 'bg-rail-purple text-white hover:bg-rail-purple-dark' : 'border border-[rgba(255,255,255,0.1)] text-[#A0A0B0] hover:bg-[rgba(255,255,255,0.06)] hover:text-white'
                }`}
              >
                {p.cta}
              </Link>
            </div>
          ))}
        </div>

        {/* FAQ */}
        <div className="max-w-2xl mx-auto px-6">
          <h2 className="text-2xl lg:text-3xl font-bold text-white text-center mb-10">Frequently asked questions</h2>
          <div className="space-y-2">
            {faqs.map((f, i) => (
              <div key={i} className="bg-[#151518] rounded-xl border border-[rgba(255,255,255,0.06)] overflow-hidden">
                <button onClick={() => setOpenFaq(openFaq === i ? -1 : i)} className="w-full flex items-center justify-between px-5 py-4 text-left">
                  <span className="text-sm font-semibold text-white">{f.q}</span>
                  <ChevronDown size={14} className={`text-[#4A4A55] transition-transform ${openFaq === i ? 'rotate-180' : ''}`} />
                </button>
                {openFaq === i && (
                  <div className="px-5 pb-4">
                    <p className="text-sm text-[#6B6B7B] leading-relaxed">{f.a}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-[#0D0D0F] border-t border-[rgba(255,255,255,0.06)] pt-10 pb-6">
        <div className="max-w-7xl mx-auto px-6 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="w-5 h-5 rounded bg-[rgba(139,92,246,0.2)] flex items-center justify-center"><span className="text-rail-purple text-[7px] font-bold">RD</span></div>
            <span className="text-xs text-[#4A4A55]">2025 RailDock. All rights reserved.</span>
          </div>
          <Github size={14} className="text-[#4A4A55] hover:text-white transition-colors cursor-pointer" />
        </div>
      </footer>
    </div>
  )
}
