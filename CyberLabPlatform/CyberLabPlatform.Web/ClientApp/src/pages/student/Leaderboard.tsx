import { useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getLeaderboard } from "@/services/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { LeaderboardTable } from "@/components/LeaderboardTable";
import { Trophy } from "lucide-react";

export default function Leaderboard() {
  const { sessionId } = useParams<{ sessionId: string }>();

  const { data: entries, isLoading } = useQuery({
    queryKey: ["leaderboard", sessionId],
    queryFn: () => getLeaderboard(sessionId!),
    enabled: !!sessionId,
    refetchInterval: 30000,
  });

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <Trophy className="h-6 w-6 text-yellow-400" /> Leaderboard
      </h1>

      <Card>
        <CardHeader><CardTitle className="text-lg">Rankings</CardTitle></CardHeader>
        <CardContent>
          {isLoading && <p className="text-muted-foreground">Loading leaderboard...</p>}
          {entries && <LeaderboardTable entries={entries} />}
          {entries?.length === 0 && <p className="text-muted-foreground text-center py-4">No entries yet.</p>}
        </CardContent>
      </Card>
    </div>
  );
}
