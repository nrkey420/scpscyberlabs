import { useState } from "react";
import type { LabObjective, StudentProgress } from "@/types/models";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { CheckCircle2, Circle, ChevronDown, ChevronRight, Flag } from "lucide-react";

interface ObjectiveChecklistProps {
  objectives: LabObjective[];
  progress: StudentProgress[];
  onFlagSubmit: (objectiveId: string, flag: string) => void;
}

export function ObjectiveChecklist({
  objectives,
  progress,
  onFlagSubmit,
}: ObjectiveChecklistProps) {
  const [expandedHint, setExpandedHint] = useState<string | null>(null);
  const [flagInputs, setFlagInputs] = useState<Record<string, string>>({});

  const sorted = [...objectives].sort((a, b) => a.orderIndex - b.orderIndex);

  return (
    <div className="space-y-2">
      {sorted.map((obj) => {
        const prog = progress.find((p) => p.objectiveId === obj.id);
        const isCompleted = prog?.isCompleted ?? false;
        const flagValue = flagInputs[obj.id] ?? "";

        return (
          <div
            key={obj.id}
            className={`border rounded-lg p-3 ${
              isCompleted ? "border-green-600/40 bg-green-600/5" : "border-border"
            }`}
          >
            <div className="flex items-start gap-3">
              {isCompleted ? (
                <CheckCircle2 className="h-5 w-5 text-green-500 mt-0.5 shrink-0" />
              ) : (
                <Circle className="h-5 w-5 text-muted-foreground mt-0.5 shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <span className={`font-medium text-sm ${isCompleted ? "line-through opacity-60" : ""}`}>
                    {obj.title}
                  </span>
                  <Badge variant={obj.isBonusObjective ? "warning" : "secondary"} className="text-xs">
                    {obj.points} pts
                  </Badge>
                </div>
                <p className="text-xs text-muted-foreground">{obj.description}</p>

                {obj.hint && (
                  <button
                    className="text-xs text-primary mt-1 flex items-center gap-1 hover:underline"
                    onClick={() => setExpandedHint(expandedHint === obj.id ? null : obj.id)}
                  >
                    {expandedHint === obj.id ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
                    Hint
                  </button>
                )}
                {expandedHint === obj.id && obj.hint && (
                  <p className="text-xs text-yellow-400 mt-1 pl-4 italic">{obj.hint}</p>
                )}

                {!isCompleted && obj.flagValue && (
                  <div className="flex items-center gap-2 mt-2">
                    <Input
                      placeholder="Enter flag..."
                      value={flagValue}
                      onChange={(e) => setFlagInputs({ ...flagInputs, [obj.id]: e.target.value })}
                      className="h-8 text-xs"
                    />
                    <Button
                      size="sm"
                      className="h-8"
                      onClick={() => {
                        if (flagValue.trim()) {
                          onFlagSubmit(obj.id, flagValue.trim());
                          setFlagInputs({ ...flagInputs, [obj.id]: "" });
                        }
                      }}
                    >
                      <Flag className="h-3 w-3 mr-1" /> Submit
                    </Button>
                  </div>
                )}

                {isCompleted && prog?.pointsEarned !== undefined && (
                  <p className="text-xs text-green-400 mt-1">
                    +{prog.pointsEarned} points earned
                  </p>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
