import { useEffect, useRef, useCallback } from "react";
import type { ActivityEvent } from "@/types/models";
import {
  startConnection,
  stopConnection,
  joinSession,
  leaveSession,
  onActivityEvent,
  offActivityEvent,
  onSessionUpdated,
  onVMStatusChanged,
  onProgressUpdated,
  getConnection,
} from "@/services/signalr";

interface UseSignalROptions {
  sessionId?: string;
  onActivity?: (event: ActivityEvent) => void;
  onSessionUpdate?: (sessionId: string) => void;
  onVMStatus?: (vmId: string, status: string) => void;
  onProgress?: (studentId: string, objectiveId: string, points: number) => void;
}

export function useSignalR(options: UseSignalROptions) {
  const {
    sessionId,
    onActivity,
    onSessionUpdate,
    onVMStatus,
    onProgress,
  } = options;

  const activityRef = useRef(onActivity);
  activityRef.current = onActivity;

  const activityHandler = useCallback((event: ActivityEvent) => {
    activityRef.current?.(event);
  }, []);

  useEffect(() => {
    let mounted = true;

    async function setup() {
      try {
        await startConnection();
        if (!mounted) return;

        if (sessionId) {
          await joinSession(sessionId);
        }

        onActivityEvent(activityHandler);

        if (onSessionUpdate) {
          onSessionUpdated(onSessionUpdate);
        }
        if (onVMStatus) {
          onVMStatusChanged(onVMStatus);
        }
        if (onProgress) {
          onProgressUpdated(onProgress);
        }
      } catch (err) {
        console.error("SignalR connection failed:", err);
      }
    }

    setup();

    return () => {
      mounted = false;
      offActivityEvent(activityHandler);
      if (sessionId) {
        leaveSession(sessionId).catch(() => {});
      }

      const conn = getConnection();
      conn.off("SessionUpdated");
      conn.off("VMStatusChanged");
      conn.off("ProgressUpdated");

      stopConnection().catch(() => {});
    };
  }, [sessionId, activityHandler, onSessionUpdate, onVMStatus, onProgress]);
}
