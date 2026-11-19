import { useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'

export type ProfileUpdate = {
  name: string
  email: string
  currentPassword?: string
  password?: string
  passwordConfirmation?: string
}

export function useUpdateProfile() {
  const setUser = useAuthStore((state) => state.setUser)
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: ProfileUpdate) => api.auth.updateProfile(data),
    onSuccess: (user) => {
      setUser(user)
      queryClient.invalidateQueries({ queryKey: ['organizations'] })
      toast.success('Profile updated')
    },
    // Validation and password errors are rendered inline in the profile form so
    // the user can correct the exact field instead of chasing a toast.
  })
}
