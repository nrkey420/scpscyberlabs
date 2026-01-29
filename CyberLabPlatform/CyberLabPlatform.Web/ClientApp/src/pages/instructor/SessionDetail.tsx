import { useParams } from "react-router-dom";
import { useState, useCallback } from "react";
import { useLabSession, useTerminateLab } from "@/hooks/useLabSession";
import { useSignalR } from "@/hooks/useSignalR";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { CountdownTimer } from "@/components/CountdownTimer";
import { ActivityFeed } from "@/components/ActivityFeed";
import { toast } from "@/components/ui/toast";
import type { ActivityEvent } from "@/types/models";
import { VMStatus } from "@/types/models";
import { Users, Monitor, Activity, XCircle, Clock, CheckCircle2, AlertCircle, Pause } from "lucide-react";
import api from "@/services/api";

const vmStatusIcon: Record<string, React.ElementType> = {
  [VMStatus.Running]: CheckCircle2,
  [VMStatus.Paused]: Pause,
  [VMStatus.Failed]: AlertCircle,
  [VMStatus.Creating]: Clock,
};

const vmStatusColor: Record<string, string> = {
  [VMStatus.Running]: "text-green-500",
  [VMStatus.Paused]: "text-yellow-500",
  [VMStatus.Failed]: "text-red-500",
  [VMStatus.Creating]: "text-blue-400",
  [VMStatus.Stopped]: "text-muted-foreground",
};

export default function SessionDetail() {
  const { sessionId } = useParams<{ sessionId: string }>();
  const { data: session, refetch } = useLabSession(sessionId);
  const terminateMutation = useTerminateLab();
  const [events, setEvents] = useState<ActivityEvent[]>([]);

  const handleActivity = useCallback((event: ActivityEvent) => {
    setEvents((prev) => [...prev.slice(-200), event]);
  }, []);

  const handleSessionUpdate = useCallback(() => {
    refetch();
  }, [refetch]);

  useSignalR({
    sessionId,
    onActivity: handleActivity,
    onSessionUpdate: handleSessionUpdate,
  });

  const handleTerminate = async () => {
    if (!sessionId || !confirm("Terminate this session?")) return;
    try {
      await terminateMutation.mutateAsync(sessionId);
      toast({ title: "Session Terminated", variant: "success" });
    } catch {
      toast({ title: "Failed", variant: "destructive" });
    }
  };

  const handleExtend = async () => {
    if (!sessionId) return;
    try {
      await api.post(`/sessions/${sessionId}/extend`, { minutes: 30 });
      refetch();
      toast({ title: "Extended by 30 minutes", variant: "success" });
    } catch {
      toast({ title: "Failed to extend", variant: "destructive" });
    }
  };

  if (!session) {
    return <div className="text-center py-12 text-muted-foreground">Loading session...</div>;
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h1 className="text-2xl font-bold">{session.templateName}</h1>
          <p className="text-sm text-muted-foreground">Instructor: {session.instructorName}</p>
        </div>
        <div className="flex items-center gap-3">
          <CountdownTimer endTime={session.endsAt} />
          <Badge>{session.status}</Badge>
          <Button variant="outline" size="sm" onClick={handleExtend}>
            <Clock className="h-3 w-3 mr-1" /> +30min
          </Button>
          <Button variant="destructive" size="sm" onClick={handleTerminate}>
            <XCircle className="h-3 w-3 mr-1" /> Terminate
          </Button>
        </div>
      </div>

      {/* 3-column layout */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Student Progress */}
        <Card className="lg:col-span-1">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <Users className="h-4 w-4" /> Student Progress ({session.assignments.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-3 max-h-[500px] overflow-y-auto">
              {session.assignments.map((a) => {
                const pct = a.totalObjectives > 0 ? Math.round((a.completedObjectives / a.totalObjectives) * 100) : 0;
                return (
                  <div key={a.id} className="p-2 rounded-md bg-secondary/30">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-sm font-medium">{a.studentName}</span>
                      <span className="text-xs text-primary font-mono">{a.totalPoints} pts</span>
                    </div>
                    <div className="w-full bg-secondary rounded-full h-1.5">
                      <div className="bg-primary rounded-full h-1.5" style={{ width: `${pct}%` }} />
                    </div>
                    <p className="text-xs text-muted-foreground mt-1">{a.completedObjectives}/{a.totalObjectives} objectives</p>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* VMs */}
        <Card className="lg:col-span-1">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <Monitor className="h-4 w-4" /> Virtual Machines ({session.vmInstances.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2 max-h-[500px] overflow-y-auto">
              {session.vmInstances.map((vm) => {
                const Icon = vmStatusIcon[vm.status] || AlertCircle;
                const color = vmStatusColor[vm.status] || "text-muted-foreground";
                return (
                  <div key={vm.id} className="flex items-center gap-3 p-2 rounded-md bg-secondary/30">
                    <Icon className={`h-4 w-4 ${color}`} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{vm.name}</p>
                      <p className="text-xs text-muted-foreground">{vm.hostname} - {vm.os}</p>
                      {vm.assignedStudentName && (
                        <p className="text-xs text-primary">{vm.assignedStudentName}</p>
                      )}
                    </div>
                    <Badge variant="outline" className="text-xs">{vm.status}</Badge>
                  </div>
                );
              })}
            </div>
          </CardContent>
        </Card>

        {/* Activity Feed */}
        <Card className="lg:col-span-1">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <Activity className="h-4 w-4" /> Live Activity
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ActivityFeed events={events} />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
