import { Link } from "react-router-dom";
import { useLabSessions, useTerminateLab } from "@/hooks/useLabSession";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { CountdownTimer } from "@/components/CountdownTimer";
import { toast } from "@/components/ui/toast";
import { MonitorPlay, Eye, XCircle, Users, Rocket } from "lucide-react";
import { LabStatus } from "@/types/models";

export default function ActiveLabs() {
  const { data: sessions, isLoading } = useLabSessions();
  const terminateMutation = useTerminateLab();

  const handleTerminate = async (sessionId: string) => {
    if (!confirm("Are you sure you want to terminate this session?")) return;
    try {
      await terminateMutation.mutateAsync(sessionId);
      toast({ title: "Session Terminated", variant: "success" });
    } catch {
      toast({ title: "Failed to terminate", variant: "destructive" });
    }
  };

  const statusVariant = (status: string) => {
    if (status === LabStatus.Running) return "success" as const;
    if (status === LabStatus.Provisioning) return "warning" as const;
    if (status === LabStatus.Failed) return "destructive" as const;
    return "secondary" as const;
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <MonitorPlay className="h-6 w-6 text-primary" /> Active Labs
        </h1>
        <Link to="/instructor/deploy">
          <Button><Rocket className="h-4 w-4 mr-2" /> Deploy New</Button>
        </Link>
      </div>

      {isLoading && <p className="text-muted-foreground">Loading sessions...</p>}

      {sessions?.length === 0 && (
        <Card><CardContent className="p-8 text-center text-muted-foreground">No active lab sessions.</CardContent></Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {sessions?.map((s) => (
          <Card key={s.id}>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle className="text-base">{s.templateName}</CardTitle>
                <Badge variant={statusVariant(s.status)}>{s.status}</Badge>
              </div>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="flex items-center gap-1 text-muted-foreground"><Users className="h-3 w-3" />{s.studentCount} students</span>
                  <CountdownTimer endTime={s.endsAt} />
                </div>
                <div className="w-full bg-secondary rounded-full h-2">
                  <div className="bg-primary rounded-full h-2 transition-all" style={{ width: `${s.averageProgress}%` }} />
                </div>
                <p className="text-xs text-muted-foreground">{Math.round(s.averageProgress)}% avg progress</p>
                <div className="flex gap-2">
                  <Link to={`/instructor/sessions/${s.id}`} className="flex-1">
                    <Button variant="outline" size="sm" className="w-full"><Eye className="h-3 w-3 mr-1" /> View</Button>
                  </Link>
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={() => handleTerminate(s.id)}
                    disabled={terminateMutation.isPending}
                  >
                    <XCircle className="h-3 w-3" />
                  </Button>
                </div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
