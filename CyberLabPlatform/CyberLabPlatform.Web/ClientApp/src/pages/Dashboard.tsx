import { useAuth } from "@/hooks/useAuth";
import { useQuery } from "@tanstack/react-query";
import { getResourceUsage, getActiveSessions, getSystemHealth, getStudentSessions, getStudentProgress } from "@/services/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ResourceGauge } from "@/components/ResourceGauge";
import { Link } from "react-router-dom";
import { Rocket, MonitorPlay, BarChart3, BookOpen, Trophy, Activity, Server, Shield } from "lucide-react";

function AdminDashboard() {
  const { data: resources } = useQuery({ queryKey: ["resources"], queryFn: getResourceUsage });
  const { data: sessions } = useQuery({ queryKey: ["sessions", "active"], queryFn: getActiveSessions });
  const { data: health } = useQuery({ queryKey: ["health"], queryFn: getSystemHealth });

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Admin Dashboard</h1>

      {/* Resource Gauges */}
      <Card>
        <CardHeader><CardTitle className="text-lg">Resource Usage</CardTitle></CardHeader>
        <CardContent>
          <div className="flex justify-around flex-wrap gap-6">
            <ResourceGauge label="VMs" used={resources?.runningVMs ?? 0} total={resources?.totalVMs ?? 0} unit="VMs" />
            <ResourceGauge label="CPU" used={resources?.usedCPUCores ?? 0} total={resources?.totalCPUCores ?? 0} unit="cores" />
            <ResourceGauge label="Memory" used={resources?.usedMemoryGB ?? 0} total={resources?.totalMemoryGB ?? 0} unit="GB" />
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <MonitorPlay className="h-10 w-10 text-primary" />
            <div>
              <p className="text-3xl font-bold">{sessions?.length ?? 0}</p>
              <p className="text-sm text-muted-foreground">Active Sessions</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <Server className="h-10 w-10 text-primary" />
            <div>
              <p className="text-3xl font-bold">{resources?.runningVMs ?? 0}</p>
              <p className="text-sm text-muted-foreground">Running VMs</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <Activity className="h-10 w-10 text-primary" />
            <div>
              <Badge variant={health?.status === "Healthy" ? "success" : "destructive"}>
                {health?.status ?? "Unknown"}
              </Badge>
              <p className="text-sm text-muted-foreground mt-1">System Health</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {health?.services && (
        <Card>
          <CardHeader><CardTitle className="text-lg">Services</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-2">
              {health.services.map((svc) => (
                <div key={svc.name} className="flex items-center justify-between text-sm">
                  <span>{svc.name}</span>
                  <div className="flex items-center gap-3">
                    <span className="text-muted-foreground">{svc.latencyMs}ms</span>
                    <Badge variant={svc.status === "Healthy" ? "success" : "destructive"}>{svc.status}</Badge>
                  </div>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function InstructorDashboard() {
  const { data: sessions } = useQuery({ queryKey: ["sessions", "active"], queryFn: getActiveSessions });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Instructor Dashboard</h1>
        <Link to="/instructor/deploy">
          <Button><Rocket className="h-4 w-4 mr-2" /> Deploy Lab</Button>
        </Link>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <MonitorPlay className="h-10 w-10 text-primary" />
            <div>
              <p className="text-3xl font-bold">{sessions?.length ?? 0}</p>
              <p className="text-sm text-muted-foreground">Active Labs</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-2 mb-3">
              <BarChart3 className="h-5 w-5 text-primary" />
              <span className="font-medium">Quick Actions</span>
            </div>
            <div className="flex gap-2">
              <Link to="/instructor/labs"><Button variant="outline" size="sm">View Labs</Button></Link>
              <Link to="/instructor/reports"><Button variant="outline" size="sm">Reports</Button></Link>
            </div>
          </CardContent>
        </Card>
      </div>

      {sessions && sessions.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-lg">Active Sessions</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-2">
              {sessions.slice(0, 5).map((s) => (
                <Link key={s.id} to={`/instructor/sessions/${s.id}`} className="flex items-center justify-between p-3 rounded-md hover:bg-secondary/50">
                  <div>
                    <p className="font-medium text-sm">{s.templateName}</p>
                    <p className="text-xs text-muted-foreground">{s.studentCount} students</p>
                  </div>
                  <Badge>{s.status}</Badge>
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function StudentDashboard() {
  const { data: sessions } = useQuery({ queryKey: ["student", "sessions"], queryFn: getStudentSessions });
  const { data: progress } = useQuery({ queryKey: ["student", "progress"], queryFn: () => getStudentProgress("me") });

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2"><Shield className="h-6 w-6 text-primary" /> My Dashboard</h1>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <BookOpen className="h-10 w-10 text-primary" />
            <div>
              <p className="text-3xl font-bold">{sessions?.length ?? 0}</p>
              <p className="text-sm text-muted-foreground">Active Labs</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <Trophy className="h-10 w-10 text-yellow-400" />
            <div>
              <p className="text-3xl font-bold">{progress?.totalPointsEarned ?? 0}</p>
              <p className="text-sm text-muted-foreground">Total Points</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <Activity className="h-10 w-10 text-green-400" />
            <div>
              <p className="text-3xl font-bold">{progress?.badges?.length ?? 0}</p>
              <p className="text-sm text-muted-foreground">Badges Earned</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {progress?.badges && progress.badges.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-lg">Recent Badges</CardTitle></CardHeader>
          <CardContent>
            <div className="flex gap-2 flex-wrap">
              {progress.badges.map((b) => (
                <Badge key={b.id} variant="secondary">{b.name}</Badge>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {sessions && sessions.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-lg">Assigned Labs</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-2">
              {sessions.map((s) => (
                <Link key={s.id} to={`/student/sessions/${s.id}`} className="flex items-center justify-between p-3 rounded-md hover:bg-secondary/50">
                  <div>
                    <p className="font-medium text-sm">{s.templateName}</p>
                    <p className="text-xs text-muted-foreground">{Math.round(s.averageProgress)}% progress</p>
                  </div>
                  <Badge variant={s.status === "Running" ? "success" : "secondary"}>{s.status}</Badge>
                </Link>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

export default function Dashboard() {
  const { isAdmin, isInstructor } = useAuth();

  if (isAdmin) return <AdminDashboard />;
  if (isInstructor) return <InstructorDashboard />;
  return <StudentDashboard />;
}
