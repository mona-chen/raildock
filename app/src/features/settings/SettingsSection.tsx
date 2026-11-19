import type { ReactNode } from 'react'
import { Switch } from '@/components/ui/switch'
import { Button } from '@/components/ui/button'

export function SettingsSection({title,description,children}:{title:string;description?:string;children:ReactNode}) {
  return <section className="overflow-hidden rounded-lg border border-white/9 bg-[#111114]"><header className="border-b border-white/[0.07] px-5 py-4"><h3 className="text-[13px] font-medium text-[#eeeeF2]">{title}</h3>{description&&<p className="mt-1 text-xs leading-5 text-[#9292a3]">{description}</p>}</header><div className="divide-y divide-white/6">{children}</div></section>
}
export function SettingsRow({id,title,description,children,inline=false}:{id?:string;title:string;description?:string;children:ReactNode;inline?:boolean}) {
  return <div className={`grid items-center gap-3 px-5 py-4 sm:gap-6 ${inline?'grid-cols-[minmax(0,1fr)_auto]':'sm:grid-cols-[minmax(0,1fr)_180px]'}`}><div>{id?<label htmlFor={id} className="text-[13px] font-medium text-[#d8d8e0]">{title}</label>:<div className="text-[13px] font-medium text-[#d8d8e0]">{title}</div>}{description&&<p id={id?`${id}-help`:undefined} className="mt-1 max-w-lg text-xs leading-5 text-[#9292a3]">{description}</p>}</div><div className="flex items-center sm:justify-end">{children}</div></div>
}
export function SettingsToggle({id,title,description,checked,onChange}:{id:string;title:string;description:string;checked:boolean;onChange:(checked:boolean)=>void}) {
  return <SettingsRow inline id={id} title={title} description={description}><Switch id={id} aria-label={title} aria-describedby={`${id}-help`} checked={checked} onCheckedChange={onChange} className="h-5 w-9 data-[state=checked]:bg-rail-purple data-[state=unchecked]:bg-[#393941] **:data-[slot=switch-thumb]:bg-white" /></SettingsRow>
}
export function SettingsSaveBar({dirty,saving,onReset}:{dirty:boolean;saving:boolean;onReset:()=>void}) {
  return <div className={`${dirty ? 'sticky bottom-0' : 'relative'} z-10 -mx-1 flex flex-wrap items-center justify-between gap-3 border-t border-white/8 bg-[#0c0c0f]/95 px-1 py-4 backdrop-blur-sm`}><p role="status" className="text-xs text-[#9292a3]">{saving?'Saving changes…':dirty?'You have unsaved changes.':'All changes saved'}</p><div className="flex items-center gap-2"><Button type="button" variant="ghost" size="sm" disabled={!dirty||saving} onClick={onReset} className="text-[#aaaab8]">Reset</Button><Button type="submit" size="sm" disabled={!dirty||saving} className="bg-rail-purple text-white hover:bg-rail-purple-dark disabled:bg-white/6 disabled:text-[#707080]">{saving?'Saving…':'Save changes'}</Button></div></div>
}
