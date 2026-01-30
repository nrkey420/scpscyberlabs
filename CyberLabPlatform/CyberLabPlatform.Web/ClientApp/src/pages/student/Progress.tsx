import { useQuery } from "@tanstack/react-query";
import { getStudentProgress } from "@/services/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Trophy, Target, BookOpen, Activity } from "lucide-react";
import { format } from "date-fns";

export default function Progress() {
  const { data: progress, isLoading } = useQuery({
    queryKey: ["student", "progress"],
    queryFn: () => getStudentProgress("me"),
  });

  if (isLoading) return <div className="text-muted-foreground p-6">Loading progress...</div>;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <Trophy className="h-6 w-6 text-yellow-400" /> My Progress
      </h1>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="p-6 flex items-center gap-4">
            <BookOpen className="h-10 w-10 text-primary" />
            <div>
              <p className="text-3xl font-bold">{progress?.completedSessions ?? 0}/{progress?.totalSessions ?? 0}</p>
              <p className="text-sm text-muted-foreground">Sessions Completed</p>
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
            <Target className="h-10 w-10 text-green-400" />
            <div>
              <p className="text-3xl font-bold">{progress?.totalObjectivesCompleted ?? 0}</p>
              <p className="text-sm text-muted-foreground">Objectives Completed</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {progress?.badges && progress.badges.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-lg">Badges Earned</CardTitle></CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              {progress.badges.map((b) => (
                <div key={b.id} className="flex flex-col items-center p-4 rounded-lg bg-secondary/30 text-center">
                  <div className="w-12 h-12 rounded-full bg-primary/20 flex items-center justify-center mb-2">
                    <Trophy className="h-6 w-6 text-yellow-400" />
                  </div>
                  <p className="text-sm font-medium">{b.name}</p>
                  <p className="text-xs text-muted-foreground">{b.description}</p>
                  <p className="text-xs text-muted-foreground mt-1">{format(new Date(b.earnedAt), "MMM d, yyyy")}</p>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {progress?.recentActivity && progress.recentActivity.length > 0 && (
        <Card>
          <CardHeader><CardTitle className="text-lg flex items-center gap-2"><Activity className="h-5 w-5" /> Recent Activity</CardTitle></CardHeader>
          <CardContent>
            <div className="space-y-2">
              {progress.recentActivity.map((a) => (
                <div key={a.id} className="flex items-center justify-between text-sm p-2 rounded bg-secondary/30">
                  <div>
                    <Badge variant="outline" className="mr-2 text-xs">{a.eventType}</Badge>
                    <span className="text-muted-foreground">{a.details}</span>
                  </div>
                  <span className="text-xs text-muted-foreground">{format(new Date(a.timestamp), "MMM d, HH:mm")}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
