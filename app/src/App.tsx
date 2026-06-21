import { Routes, Route, Navigate } from 'react-router-dom'
import { lazy, Suspense } from 'react'
import { Toaster } from 'sonner'
import { QueryClientProvider } from '@tanstack/react-query'
import { queryClient } from '@/lib/queryClient'
import DashboardLayout from '@/components/layout/DashboardLayout'
import AuthGuard from '@/components/layout/AuthGuard'
import RootRedirect from '@/components/RootRedirect'
import { ErrorBoundary } from '@/features/shared/ErrorBoundary'

const AuthPage = lazy(() => import('./pages/AuthPage'))
const AcceptInvitationPage = lazy(() => import('./pages/AcceptInvitationPage'))
const ProjectsPage = lazy(() => import('./pages/ProjectsPage'))
const ProjectCanvas = lazy(() => import('./pages/ProjectCanvas'))
const ServerPage = lazy(() => import('./pages/ServerPage'))
const SettingsPage = lazy(() => import('./pages/SettingsPage'))
const ActivityPage = lazy(() => import('./pages/ActivityPage'))


function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <div className="min-h-screen bg-[#0B0B0D] text-[#F0F1F3] font-sans antialiased">
        <ErrorBoundary>
          <Suspense fallback={<div className="min-h-screen bg-[#0B0B0D]" />}>
            <Routes>
              <Route path="/" element={<RootRedirect />} />
              <Route path="/login" element={<AuthPage />} />
              <Route path="/setup" element={<AuthPage />} />
              <Route path="/invitations/:token" element={<AcceptInvitationPage />} />
              <Route path="/dashboard" element={
                <AuthGuard>
                  <DashboardLayout />
                </AuthGuard>
              }>
                <Route index element={<Navigate to="projects" replace />} />
                <Route path="projects" element={<ProjectsPage />} />
                <Route path="project/:projectId/*" element={<ProjectCanvas />} />
                <Route path="servers" element={<ServerPage />} />
                <Route path="activity" element={<ActivityPage />} />
                <Route path="settings" element={<SettingsPage />} />
              </Route>
            </Routes>
          </Suspense>
        </ErrorBoundary>
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
    </QueryClientProvider>
  )
}

export default App
