import { create } from "zustand";
import { UserRole, type User } from "@/types/models";

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  setAuthenticatedUser: (user: User, token: string) => void;
  logout: () => void;
}

function mapRole(input?: string): UserRole {
  switch (input) {
    case "SystemAdministrator":
    case "Admin":
      return UserRole.Admin;
    case "Instructor":
      return UserRole.Instructor;
    default:
      return UserRole.Student;
  }
}

export function buildUserFromClaims(claims: Record<string, unknown>): User {
  const roleClaim = (claims.roles as string[] | undefined)?.[0]
    ?? (claims.role as string | undefined)
    ?? "Student";

  return {
    id: (claims.oid as string | undefined)
      ?? (claims.sub as string | undefined)
      ?? "unknown",
    name: (claims.name as string | undefined) ?? "Unknown User",
    email: (claims.preferred_username as string | undefined)
      ?? (claims.email as string | undefined)
      ?? "",
    role: mapRole(roleClaim),
  };
}

export const useAuthStore = create<AuthState>((set) => ({
  user: (() => {
    const stored = sessionStorage.getItem("auth_user");
    return stored ? JSON.parse(stored) : null;
  })(),
  isAuthenticated: !!sessionStorage.getItem("auth_token"),
  setAuthenticatedUser: (user, token) => {
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
  const { user, isAuthenticated, setAuthenticatedUser, logout } = useAuthStore();

  const isAdmin = user?.role === UserRole.Admin;
  const isInstructor = user?.role === UserRole.Instructor;
  const isStudent = user?.role === UserRole.Student;

  const hasRole = (role: UserRole) => user?.role === role;

  return { user, isAuthenticated, setAuthenticatedUser, logout, isAdmin, isInstructor, isStudent, hasRole };
}
