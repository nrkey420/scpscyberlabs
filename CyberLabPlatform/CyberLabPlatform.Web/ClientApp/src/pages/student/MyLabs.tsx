import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getStudentSessions } from "@/services/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { CountdownTimer } from "@/components/CountdownTimer";
import { LabStatus } from "@/types/models";
import { BookOpen, Play } from "lucide-react";

export default function MyLabs() {
  const { data: sessions, isLoading } = useQuery({
    queryKey: ["student", "sessions"],
    queryFn: getStudentSessions,
  });

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <BookOpen className="h-6 w-6 text-primary" /> My Labs
      </h1>

      {isLoading && <p className="text-muted-foreground">Loading labs...</p>}

      {sessions?.length === 0 && (
        <Card><CardContent className="p-8 text-center text-muted-foreground">No labs assigned to you yet.</CardContent></Card>
      )}

      <div className="space-y-4">
        {sessions?.map((s) => (
          <Card key={s.id}>
            <CardContent className="p-4 flex items-center justify-between flex-wrap gap-4">
              <div>
                <h3 className="font-semibold">{s.templateName}</h3>
                <div className="flex items-center gap-3 mt-1">
                  <Badge variant={s.status === LabStatus.Running ? "success" : "secondary"}>{s.status}</Badge>
                  {s.status === LabStatus.Running && <CountdownTimer endTime={s.endsAt} />}
                </div>
                <div className="mt-2">
                  <div className="w-48 bg-secondary rounded-full h-1.5">
                    <div className="bg-primary rounded-full h-1.5" style={{ width: `${s.averageProgress}%` }} />
                  </div>
                  <p className="text-xs text-muted-foreground mt-1">{Math.round(s.averageProgress)}% complete</p>
                </div>
              </div>
              {s.status === LabStatus.Running && (
                <Link to={`/student/sessions/${s.id}`}>
                  <Button>
                    <Play className="h-4 w-4 mr-2" /> Enter Lab
                  </Button>
                </Link>
              )}
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
