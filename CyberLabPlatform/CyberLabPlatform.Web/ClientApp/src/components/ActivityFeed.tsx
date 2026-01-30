import { useEffect, useRef } from "react";
import { format } from "date-fns";
import type { ActivityEvent } from "@/types/models";
import { Flag, Monitor, Play, Pause, AlertCircle, CheckCircle2, LogIn } from "lucide-react";

interface ActivityFeedProps {
  events: ActivityEvent[];
}

const eventIcons: Record<string, React.ElementType> = {
  FlagSubmitted: Flag,
  VMStarted: Monitor,
  VMPaused: Pause,
  VMResumed: Play,
  ObjectiveCompleted: CheckCircle2,
  SessionJoined: LogIn,
  Error: AlertCircle,
};

export function ActivityFeed({ events }: ActivityFeedProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [events]);

  return (
    <div ref={containerRef} className="space-y-2 max-h-96 overflow-y-auto pr-2">
      {events.length === 0 && (
        <p className="text-muted-foreground text-sm text-center py-4">No activity yet</p>
      )}
      {events.map((event, i) => {
        const Icon = eventIcons[event.eventType] || AlertCircle;
        return (
          <div key={i} className="flex items-start gap-3 p-2 rounded-md bg-secondary/50 text-sm">
            <Icon className="h-4 w-4 mt-0.5 shrink-0 text-primary" />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                {event.studentName && (
                  <span className="font-medium">{event.studentName}</span>
                )}
                <span className="text-muted-foreground truncate">{event.details}</span>
              </div>
            </div>
            <span className="text-xs text-muted-foreground whitespace-nowrap">
              {format(new Date(event.timestamp), "HH:mm:ss")}
            </span>
          </div>
        );
      })}
    </div>
  );
}
