import { useParams } from "react-router-dom";
import { useState, useCallback } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { getStudentSession, getSession, submitFlag } from "@/services/api";
import { useSignalR } from "@/hooks/useSignalR";
import { VMConsole } from "@/components/VMConsole";
import { ObjectiveChecklist } from "@/components/ObjectiveChecklist";
import { CountdownTimer } from "@/components/CountdownTimer";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/components/ui/toast";
import { VMStatus } from "@/types/models";
import { Monitor, Target, ChevronLeft, ChevronRight } from "lucide-react";

export default function LabSession() {
  const { sessionId } = useParams<{ sessionId: string }>();
  const queryClient = useQueryClient();
  const [selectedVM, setSelectedVM] = useState<string | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);

  const { data: assignment } = useQuery({
    queryKey: ["student", "session", sessionId],
    queryFn: () => getStudentSession(sessionId!),
    enabled: !!sessionId,
    refetchInterval: 30000,
  });

  const { data: session } = useQuery({
    queryKey: ["sessions", sessionId],
    queryFn: () => getSession(sessionId!),
    enabled: !!sessionId,
  });

  const handleProgressUpdate = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ["student", "session", sessionId] });
  }, [queryClient, sessionId]);

  useSignalR({
    sessionId,
    onProgress: handleProgressUpdate,
  });

  const myVMs = session?.vmInstances.filter((vm) => vm.status === VMStatus.Running) ?? [];
  const activeVM = selectedVM ?? myVMs[0]?.id ?? null;

  const objectives = assignment?.progress.map((item, index) => ({
    id: item.objectiveId,
    templateId: session?.templateId ?? "",
    title: item.objectiveTitle,
    description: "",
    points: item.pointsEarned ?? 0,
    orderIndex: index + 1,
    isBonusObjective: false,
  })) ?? [];

  const handleFlagSubmit = async (objectiveId: string, flag: string) => {
    try {
      const result = await submitFlag(objectiveId, flag);
      if (result.correct) {
        toast({ title: "Correct!", description: `+${result.pointsEarned} points`, variant: "success" });
        queryClient.invalidateQueries({ queryKey: ["student", "session", sessionId] });
      } else {
        toast({ title: "Incorrect Flag", description: "Try again.", variant: "destructive" });
      }
    } catch {
      toast({ title: "Submission Failed", variant: "destructive" });
    }
  };

  return (
    <div className="flex h-[calc(100vh-3.5rem)]">
      {/* Sidebar */}
      {sidebarOpen && (
        <div className="w-80 border-r border-border flex flex-col overflow-y-auto bg-card shrink-0">
          {/* Timer */}
          {session && (
            <div className="p-4 border-b border-border">
              <CountdownTimer endTime={session.endsAt} />
              <p className="text-xs text-muted-foreground mt-1">{session.templateName}</p>
            </div>
          )}

          {/* VMs */}
          <div className="p-4 border-b border-border">
            <h3 className="text-sm font-semibold flex items-center gap-1 mb-2">
              <Monitor className="h-4 w-4" /> Virtual Machines
            </h3>
            <div className="space-y-1">
              {myVMs.map((vm) => (
                <button
                  key={vm.id}
                  onClick={() => setSelectedVM(vm.id)}
                  className={`w-full text-left p-2 rounded-md text-sm transition ${
                    activeVM === vm.id ? "bg-primary/20 text-primary" : "hover:bg-secondary/50"
                  }`}
                >
                  <p className="font-medium">{vm.name}</p>
                  <p className="text-xs text-muted-foreground">{vm.hostname} - {vm.os}</p>
                </button>
              ))}
              {myVMs.length === 0 && (
                <p className="text-xs text-muted-foreground">No running VMs</p>
              )}
            </div>
          </div>

          {/* Objectives */}
          <div className="p-4 flex-1">
            <h3 className="text-sm font-semibold flex items-center gap-1 mb-2">
              <Target className="h-4 w-4" /> Objectives
            </h3>
            {assignment && session && (
              <>
                <div className="mb-3 flex items-center gap-2">
                  <Badge variant="secondary">{assignment.completedObjectives}/{assignment.totalObjectives}</Badge>
                  <span className="text-sm font-mono text-primary">{assignment.totalPoints} pts</span>
                </div>
                <ObjectiveChecklist
                  objectives={objectives}
                  progress={assignment.progress}
                  onFlagSubmit={handleFlagSubmit}
                />
              </>
            )}
          </div>
        </div>
      )}

      {/* Toggle sidebar */}
      <button
        onClick={() => setSidebarOpen(!sidebarOpen)}
        className="w-6 flex items-center justify-center border-r border-border hover:bg-secondary/50 shrink-0"
      >
        {sidebarOpen ? <ChevronLeft className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
      </button>

      {/* Main console area */}
      <div className="flex-1 bg-black">
        {activeVM ? (
          <VMConsole vmInstanceId={activeVM} />
        ) : (
          <div className="flex items-center justify-center h-full text-muted-foreground">
            <div className="text-center">
              <Monitor className="h-12 w-12 mx-auto mb-3 opacity-30" />
              <p>Select a VM to connect</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
