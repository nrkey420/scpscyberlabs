import { Link, useLocation } from "react-router-dom";
import { useAuth } from "@/hooks/useAuth";
import { UserRole } from "@/types/models";
import { Button } from "@/components/ui/button";
import {
  Shield, LayoutDashboard, FileText, Settings, Users,
  Rocket, MonitorPlay, BarChart3, BookOpen, Trophy,
  LogOut, Menu, X,
} from "lucide-react";
import { useState } from "react";

interface NavItem {
  label: string;
  path: string;
  icon: React.ElementType;
  roles: UserRole[];
}

const navItems: NavItem[] = [
  { label: "Dashboard", path: "/", icon: LayoutDashboard, roles: [UserRole.Admin, UserRole.Instructor, UserRole.Student] },
  { label: "Templates", path: "/admin/templates", icon: FileText, roles: [UserRole.Admin] },
  { label: "System Config", path: "/admin/config", icon: Settings, roles: [UserRole.Admin] },
  { label: "Users", path: "/admin/users", icon: Users, roles: [UserRole.Admin] },
  { label: "Deploy Lab", path: "/instructor/deploy", icon: Rocket, roles: [UserRole.Instructor] },
  { label: "Active Labs", path: "/instructor/labs", icon: MonitorPlay, roles: [UserRole.Instructor] },
  { label: "Reports", path: "/instructor/reports", icon: BarChart3, roles: [UserRole.Instructor] },
  { label: "My Labs", path: "/student/labs", icon: BookOpen, roles: [UserRole.Student] },
  { label: "Progress", path: "/student/progress", icon: Trophy, roles: [UserRole.Student] },
];

export function Navbar() {
  const { user, isAuthenticated, logout } = useAuth();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  if (!isAuthenticated) return null;

  const visibleItems = navItems.filter((item) => user && item.roles.includes(user.role));

  return (
    <nav className="bg-card border-b border-border sticky top-0 z-40">
      <div className="max-w-7xl mx-auto px-4">
        <div className="flex items-center justify-between h-14">
          {/* Brand */}
          <Link to="/" className="flex items-center gap-2 text-primary font-bold text-lg">
            <Shield className="h-6 w-6" />
            <span className="hidden sm:inline">SCPS CyberLab</span>
          </Link>

          {/* Desktop nav */}
          <div className="hidden md:flex items-center gap-1">
            {visibleItems.map((item) => {
              const Icon = item.icon;
              const active = location.pathname === item.path;
              return (
                <Link key={item.path} to={item.path}>
                  <Button variant={active ? "secondary" : "ghost"} size="sm" className="gap-1.5">
                    <Icon className="h-4 w-4" />
                    {item.label}
                  </Button>
                </Link>
              );
            })}
          </div>

          {/* User menu */}
          <div className="flex items-center gap-3">
            <div className="hidden sm:block text-right">
              <p className="text-sm font-medium">{user?.name}</p>
              <p className="text-xs text-muted-foreground">{user?.role}</p>
            </div>
            <Button variant="ghost" size="icon" onClick={logout}>
              <LogOut className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="icon" className="md:hidden" onClick={() => setMobileOpen(!mobileOpen)}>
              {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </Button>
          </div>
        </div>
      </div>

      {/* Mobile nav */}
      {mobileOpen && (
        <div className="md:hidden border-t border-border p-2 space-y-1">
          {visibleItems.map((item) => {
            const Icon = item.icon;
            const active = location.pathname === item.path;
            return (
              <Link key={item.path} to={item.path} onClick={() => setMobileOpen(false)}>
                <Button variant={active ? "secondary" : "ghost"} className="w-full justify-start gap-2">
                  <Icon className="h-4 w-4" />
                  {item.label}
                </Button>
              </Link>
            );
          })}
        </div>
      )}
    </nav>
  );
}
