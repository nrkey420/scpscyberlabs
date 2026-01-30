import { useState, useEffect } from "react";
import { differenceInSeconds } from "date-fns";
import { Clock } from "lucide-react";
import { cn } from "@/lib/utils";

interface CountdownTimerProps {
  endTime: string | Date;
}

export function CountdownTimer({ endTime }: CountdownTimerProps) {
  const [remaining, setRemaining] = useState(() => {
    const end = typeof endTime === "string" ? new Date(endTime) : endTime;
    return Math.max(0, differenceInSeconds(end, new Date()));
  });

  useEffect(() => {
    const interval = setInterval(() => {
      const end = typeof endTime === "string" ? new Date(endTime) : endTime;
      const secs = Math.max(0, differenceInSeconds(end, new Date()));
      setRemaining(secs);
      if (secs <= 0) clearInterval(interval);
    }, 1000);
    return () => clearInterval(interval);
  }, [endTime]);

  const hours = Math.floor(remaining / 3600);
  const minutes = Math.floor((remaining % 3600) / 60);
  const seconds = remaining % 60;
  const isLow = remaining < 600; // less than 10 minutes

  const pad = (n: number) => n.toString().padStart(2, "0");

  return (
    <div className={cn("flex items-center gap-1.5 font-mono text-sm font-bold", isLow ? "text-red-500" : "text-foreground")}>
      <Clock className={cn("h-4 w-4", isLow && "animate-pulse")} />
      <span>{pad(hours)}:{pad(minutes)}:{pad(seconds)}</span>
    </div>
  );
}
