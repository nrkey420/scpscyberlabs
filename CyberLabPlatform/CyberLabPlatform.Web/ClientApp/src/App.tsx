import { Routes, Route } from "react-router-dom";
import { Navbar } from "@/components/Navbar";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import { Toaster } from "@/components/ui/toast";
import { UserRole } from "@/types/models";
import { useAuth } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Shield } from "lucide-react";

import Dashboard from "@/pages/Dashboard";
import Templates from "@/pages/admin/Templates";
import SystemConfig from "@/pages/admin/SystemConfig";
import Users from "@/pages/admin/Users";
import DeployLab from "@/pages/instructor/DeployLab";
import ActiveLabs from "@/pages/instructor/ActiveLabs";
import SessionDetail from "@/pages/instructor/SessionDetail";
import Reports from "@/pages/instructor/Reports";
import MyLabs from "@/pages/student/MyLabs";
import LabSession from "@/pages/student/LabSession";
import Progress from "@/pages/student/Progress";
import Leaderboard from "@/pages/student/Leaderboard";

function LoginPage() {
  const { login } = useAuth();

  const demoLogin = (role: UserRole) => {
    const users = {
      [UserRole.Admin]: { id: "admin-1", name: "Admin User", email: "admin@scps.edu", role: UserRole.Admin },
      [UserRole.Instructor]: { id: "inst-1", name: "Dr. Smith", email: "smith@scps.edu", role: UserRole.Instructor },
      [UserRole.Student]: { id: "stud-1", name: "Jane Doe", email: "jane@scps.edu", role: UserRole.Student },
    };
    login(users[role], "demo-token-" + role);
  };

  return (
    <div className="min-h-screen flex items-center justify-center">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <Shield className="h-12 w-12 text-primary mx-auto mb-2" />
          <CardTitle className="text-2xl">SCPS CyberLab</CardTitle>
          <p className="text-sm text-muted-foreground">Cybersecurity Lab Orchestration Platform</p>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground text-center mb-4">Select a demo role to continue</p>
          <Button className="w-full" onClick={() => demoLogin(UserRole.Admin)}>Login as Admin</Button>
          <Button className="w-full" variant="secondary" onClick={() => demoLogin(UserRole.Instructor)}>Login as Instructor</Button>
          <Button className="w-full" variant="outline" onClick={() => demoLogin(UserRole.Student)}>Login as Student</Button>
        </CardContent>
      </Card>
    </div>
  );
}

export default function App() {
  const { isAuthenticated } = useAuth();

  if (!isAuthenticated) {
    return (
      <>
        <LoginPage />
        <Toaster />
      </>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <main className="max-w-7xl mx-auto px-4 py-6">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/admin/templates" element={<ProtectedRoute requiredRole={UserRole.Admin}><Templates /></ProtectedRoute>} />
          <Route path="/admin/config" element={<ProtectedRoute requiredRole={UserRole.Admin}><SystemConfig /></ProtectedRoute>} />
          <Route path="/admin/users" element={<ProtectedRoute requiredRole={UserRole.Admin}><Users /></ProtectedRoute>} />
          <Route path="/instructor/deploy" element={<ProtectedRoute requiredRole={UserRole.Instructor}><DeployLab /></ProtectedRoute>} />
          <Route path="/instructor/labs" element={<ProtectedRoute requiredRole={UserRole.Instructor}><ActiveLabs /></ProtectedRoute>} />
          <Route path="/instructor/sessions/:sessionId" element={<ProtectedRoute requiredRole={UserRole.Instructor}><SessionDetail /></ProtectedRoute>} />
          <Route path="/instructor/reports" element={<ProtectedRoute requiredRole={UserRole.Instructor}><Reports /></ProtectedRoute>} />
          <Route path="/student/labs" element={<ProtectedRoute requiredRole={UserRole.Student}><MyLabs /></ProtectedRoute>} />
          <Route path="/student/sessions/:sessionId" element={<ProtectedRoute requiredRole={UserRole.Student}><LabSession /></ProtectedRoute>} />
          <Route path="/student/progress" element={<ProtectedRoute requiredRole={UserRole.Student}><Progress /></ProtectedRoute>} />
          <Route path="/student/leaderboard/:sessionId" element={<ProtectedRoute requiredRole={UserRole.Student}><Leaderboard /></ProtectedRoute>} />
        </Routes>
      </main>
      <Toaster />
    </div>
  );
}
