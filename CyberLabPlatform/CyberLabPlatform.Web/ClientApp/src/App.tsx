import { useEffect } from "react";
import { Routes, Route } from "react-router-dom";
import { useMsal, useIsAuthenticated } from "@azure/msal-react";
import { InteractionRequiredAuthError } from "@azure/msal-browser";
import { Navbar } from "@/components/Navbar";
import { ProtectedRoute } from "@/components/ProtectedRoute";
import { Toaster } from "@/components/ui/toast";
import { UserRole } from "@/types/models";
import { useAuth, buildUserFromClaims } from "@/hooks/useAuth";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Shield } from "lucide-react";
import { loginRequest, tokenRequest } from "@/auth/msal";

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
  const { instance } = useMsal();

  return (
    <div className="min-h-screen flex items-center justify-center">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <Shield className="h-12 w-12 text-primary mx-auto mb-2" />
          <CardTitle className="text-2xl">SCPS CyberLab</CardTitle>
          <p className="text-sm text-muted-foreground">Cybersecurity Lab Orchestration Platform</p>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-sm text-muted-foreground text-center mb-4">Sign in with Microsoft Entra ID</p>
          <Button
            className="w-full"
            onClick={() => instance.loginRedirect(loginRequest)}
          >
            Sign in
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}

function decodeJwtPayload(jwt: string): Record<string, unknown> {
  try {
    const base64Url = jwt.split(".")[1];
    const base64 = base64Url.replace(/-/g, "+").replace(/_/g, "/");
    return JSON.parse(atob(base64));
  } catch {
    return {};
  }
}

export default function App() {
  const entraAuthenticated = useIsAuthenticated();
  const { instance, accounts } = useMsal();
  const { isAuthenticated, setAuthenticatedUser, logout } = useAuth();

  useEffect(() => {
    const syncAuth = async () => {
      if (!entraAuthenticated || accounts.length === 0) {
        logout();
        return;
      }

      const account = accounts[0];
      try {
        const token = await instance.acquireTokenSilent({
          ...tokenRequest,
          account,
        });

        // App roles are in the access token, not the ID token. Decode the
        // access token payload and merge its roles claim so buildUserFromClaims
        // can map the role correctly.
        const accessTokenPayload = decodeJwtPayload(token.accessToken);
        const claims = {
          ...account.idTokenClaims,
          roles: accessTokenPayload.roles ?? account.idTokenClaims?.roles,
        };
        setAuthenticatedUser(buildUserFromClaims(claims), token.accessToken);
      } catch (err) {
        if (err instanceof InteractionRequiredAuthError) {
          await instance.acquireTokenRedirect({ ...tokenRequest, account });
          return;
        }
        throw err;
      }
    };

    syncAuth();
  }, [accounts, entraAuthenticated, instance, logout, setAuthenticatedUser]);

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
