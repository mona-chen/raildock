import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { expect, it, vi } from 'vitest'
import NotificationsTab from '@/features/settings/NotificationsTab'
const { save } = vi.hoisted(()=>({save:vi.fn()}))
vi.mock('@/stores/useAuthStore',()=>({useAuthStore:(selector:(s:unknown)=>unknown)=>selector({currentOrganizationId:'1'})}))
vi.mock('@/lib/api',()=>({observabilityApi:{notifications:async()=>({settings:{enabled:true,email:true,emailDestinations:[],cpu:90,memory:90,disk:90,httpErrorPercent:10,requestsPerMinute:1000,suspiciousPerMinute:0,windowMinutes:3,retentionDays:30},smtpConfigured:true,incidents:[]}),saveNotifications:save}}))
it('preserves additional destination drafts when saving fails',async()=>{
  save.mockRejectedValue(new Error('Could not save destinations'))
  const client=new QueryClient({defaultOptions:{queries:{retry:false}}})
  render(<QueryClientProvider client={client}><NotificationsTab/></QueryClientProvider>)
  const input=await screen.findByLabelText('Additional email destinations')
  fireEvent.change(input,{target:{value:'ops@example.test\noncall@example.test'}})
  fireEvent.click(screen.getByRole('button',{name:'Save changes'}))
  await waitFor(()=>expect(save).toHaveBeenCalledWith(expect.objectContaining({emailDestinations:['ops@example.test','oncall@example.test']})))
  expect(input).toHaveValue('ops@example.test\noncall@example.test')
  expect(await screen.findByRole('alert')).toHaveTextContent('Could not save destinations')
  client.clear()
})
