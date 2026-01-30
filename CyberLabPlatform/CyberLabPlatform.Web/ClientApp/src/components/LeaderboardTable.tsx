import type { LeaderboardEntry } from "@/types/models";
import { Badge } from "@/components/ui/badge";
import { Trophy, Medal, Award } from "lucide-react";
import { useAuth } from "@/hooks/useAuth";

interface LeaderboardTableProps {
  entries: LeaderboardEntry[];
}

export function LeaderboardTable({ entries }: LeaderboardTableProps) {
  const { user } = useAuth();

  const rankIcon = (rank: number) => {
    if (rank === 1) return <Trophy className="h-5 w-5 text-yellow-400" />;
    if (rank === 2) return <Medal className="h-5 w-5 text-gray-300" />;
    if (rank === 3) return <Award className="h-5 w-5 text-amber-600" />;
    return <span className="text-sm font-mono w-5 text-center">{rank}</span>;
  };

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border text-left">
            <th className="pb-3 pr-4 w-12">Rank</th>
            <th className="pb-3 pr-4">Student</th>
            <th className="pb-3 pr-4 text-right">Points</th>
            <th className="pb-3 pr-4 text-right">Objectives</th>
            <th className="pb-3">Badges</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => {
            const isCurrentUser = entry.studentId === user?.id;
            return (
              <tr
                key={entry.studentId}
                className={`border-b border-border/50 ${
                  isCurrentUser ? "bg-primary/10" : "hover:bg-secondary/30"
                }`}
              >
                <td className="py-3 pr-4">{rankIcon(entry.rank)}</td>
                <td className="py-3 pr-4 font-medium">
                  {entry.studentName}
                  {isCurrentUser && (
                    <Badge variant="outline" className="ml-2 text-xs">You</Badge>
                  )}
                </td>
                <td className="py-3 pr-4 text-right font-mono font-bold text-primary">
                  {entry.totalPoints}
                </td>
                <td className="py-3 pr-4 text-right text-muted-foreground">
                  {entry.completedObjectives}/{entry.totalObjectives}
                </td>
                <td className="py-3">
                  <div className="flex gap-1 flex-wrap">
                    {entry.badges.map((badge) => (
                      <Badge key={badge.id} variant="secondary" className="text-xs">
                        {badge.name}
                      </Badge>
                    ))}
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
