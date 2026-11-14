import { Routes, Route, Navigate, useNavigate } from 'react-router-dom'
import { lazy, Suspense, useEffect, useState, useRef } from 'react'
import { Toaster } from 'sonner'
import { QueryClientProvider } from '@tanstack/react-query'
import { createQueryClient } from '@/lib/queryClient'
import { useAuthStore } from '@/stores/useAuthStore'
import { disconnectCable } from '@/lib/cable'
import { Spinner } from '@/components/ui/spinner'
import DashboardLayout from '@/components/layout/DashboardLayout'
import AuthGuard from '@/components/layout/AuthGuard'
import RootRedirect from '@/components/RootRedirect'
import { ErrorBoundary } from '@/features/shared/ErrorBoundary'
import CommandPalette from '@/features/command-palette/CommandPalette'

const AuthPage = lazy(() => import('./pages/AuthPage'))
const AcceptInvitationPage = lazy(() => import('./pages/AcceptInvitationPage'))
const ProjectsPage = lazy(() => import('./pages/ProjectsPage'))
const ProjectCanvas = lazy(() => import('./pages/ProjectCanvas'))
const ServerPage = lazy(() => import('./pages/ServerPage'))
const SettingsPage = lazy(() => import('./pages/SettingsPage'))
const ActivityPage = lazy(() => import('./pages/ActivityPage'))
const NotFoundPage = lazy(() => import('./pages/NotFoundPage'))


function SessionQueries({ children }: { children: React.ReactNode }) {
  const [client] = useState(createQueryClient)
  useEffect(() => {
    const unsubscribe = useAuthStore.subscribe((next, previous) => {
      if (next.token !== previous.token || next.currentOrganizationId !== previous.currentOrganizationId) {
        void client.cancelQueries()
        client.clear()
        disconnectCable()
      }
    })
    return () => { unsubscribe(); void client.cancelQueries(); disconnectCable() }
  }, [client])
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}


function App() {
  const token = useAuthStore((state) => state.token)
  const organizationId = useAuthStore((state) => state.currentOrganizationId)
  const scope = `${token ?? ''}:${organizationId ?? ''}`
  const previousOrganization = useRef(organizationId)
  const navigate = useNavigate()
  useEffect(() => {
    if (previousOrganization.current !== organizationId && token) navigate('/dashboard/projects', { replace: true })
    previousOrganization.current = organizationId
  }, [organizationId, token, navigate])
  return (
    <SessionQueries key={scope}>
      <div className="min-h-screen bg-[#0B0B0D] text-[#F0F1F3] font-sans antialiased">
        <ErrorBoundary>
          <Suspense fallback={<div role="status" className="flex min-h-dvh items-center justify-center gap-3 bg-[#0B0B0D] text-sm text-[#a0a0b0]"><Spinner className="size-5 text-violet-300" />Loading your workspace…</div>}>
            <Routes>
              <Route path="/" element={<RootRedirect />} />
              <Route path="/login" element={<AuthPage />} />
              <Route path="/setup" element={<AuthPage />} />
              <Route path="/invitations/:token" element={<AcceptInvitationPage />} />
              <Route path="/dashboard" element={
                <AuthGuard>
                  <ErrorBoundary>
                    <DashboardLayout />
                  </ErrorBoundary>
                </AuthGuard>
              }>
                <Route index element={<Navigate to="projects" replace />} />
                <Route path="projects" element={<ProjectsPage />} />
                <Route path="project/:projectId/*" element={<ProjectCanvas />} />
                <Route path="servers" element={<ServerPage />} />
                <Route path="activity" element={<ActivityPage />} />
                <Route path="settings" element={<SettingsPage />} />
              </Route>
              <Route path="*" element={<NotFoundPage />} />
            </Routes>
          </Suspense>
        </ErrorBoundary>
        <CommandPalette />
        <Toaster
          position="top-right"
          theme="dark"
          toastOptions={{
            style: {
              background: '#161618',
              border: '1px solid rgba(255,255,255,0.06)',
              color: '#F0F1F3',
            },
          }}
        />
      </div>
    </SessionQueries>
  )
}

export default App
