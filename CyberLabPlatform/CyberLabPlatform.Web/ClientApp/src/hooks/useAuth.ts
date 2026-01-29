import { create } from "zustand";
import { UserRole, type User } from "@/types/models";

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  setUser: (user: User | null) => void;
  login: (user: User, token: string) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: (() => {
    const stored = sessionStorage.getItem("auth_user");
    return stored ? JSON.parse(stored) : null;
  })(),
  isAuthenticated: !!sessionStorage.getItem("auth_token"),
  setUser: (user) => set({ user, isAuthenticated: !!user }),
  login: (user, token) => {
    sessionStorage.setItem("auth_token", token);
    sessionStorage.setItem("auth_user", JSON.stringify(user));
    set({ user, isAuthenticated: true });
  },
  logout: () => {
    sessionStorage.removeItem("auth_token");
    sessionStorage.removeItem("auth_user");
    set({ user: null, isAuthenticated: false });
  },
}));

export function useAuth() {
  const { user, isAuthenticated, login, logout } = useAuthStore();

  const isAdmin = user?.role === UserRole.Admin;
  const isInstructor = user?.role === UserRole.Instructor;
  const isStudent = user?.role === UserRole.Student;

  const hasRole = (role: UserRole) => user?.role === role;

  return { user, isAuthenticated, login, logout, isAdmin, isInstructor, isStudent, hasRole };
}
