import { SiUbuntu, SiDebian, SiLinux, SiAlpinelinux, SiFedora, SiRockylinux, SiCentos, SiRedhat, SiArchlinux } from '@icons-pack/react-simple-icons'

export function operatingSystem(value?: string) {
  const name = value?.trim() || ''
  const known = name && !/^unknown$/i.test(name)
  const brands = [
    { pattern: /ubuntu/i, Icon: SiUbuntu, color: '#e97846' },
    { pattern: /debian/i, Icon: SiDebian, color: '#ef718e' },
    { pattern: /alpine/i, Icon: SiAlpinelinux, color: '#76b6d9' },
    { pattern: /fedora/i, Icon: SiFedora, color: '#84a9e9' },
    { pattern: /rocky/i, Icon: SiRockylinux, color: '#73c6a8' },
    { pattern: /centos/i, Icon: SiCentos, color: '#bc9adc' },
    { pattern: /red hat|rhel/i, Icon: SiRedhat, color: '#ee7777' },
    { pattern: /arch/i, Icon: SiArchlinux, color: '#73bada' },
  ]
  return { name: known ? name.replace(/\s*\(detected\)/i, '') : 'Operating system unknown', verifiedVersion: Boolean(known && /\b\d+(?:\.\d+)*\b/i.test(name)), ...(brands.find(brand => brand.pattern.test(name)) || { Icon: SiLinux, color: '#b7bac7' }) }
}

export default function OperatingSystem({ value }: { value?: string }) {
  const { Icon, color } = operatingSystem(value)
  return <div className="flex size-11 shrink-0 items-center justify-center rounded-xl border border-white/8 bg-white/[0.025]" aria-hidden="true"><Icon size={25} color={color} /></div>
}
