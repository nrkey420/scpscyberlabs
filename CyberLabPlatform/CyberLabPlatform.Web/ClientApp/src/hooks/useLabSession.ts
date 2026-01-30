import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  getActiveSessions,
  getSession,
  deployLab,
  terminateLab,
} from "@/services/api";
import type { LabDeployRequest } from "@/types/models";

export function useLabSessions() {
  return useQuery({
    queryKey: ["sessions", "active"],
    queryFn: getActiveSessions,
    refetchInterval: 30000,
  });
}

export function useLabSession(id: string | undefined) {
  return useQuery({
    queryKey: ["sessions", id],
    queryFn: () => getSession(id!),
    enabled: !!id,
    refetchInterval: 15000,
  });
}

export function useDeployLab() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (request: LabDeployRequest) => deployLab(request),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["sessions"] });
    },
  });
}

export function useTerminateLab() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (sessionId: string) => terminateLab(sessionId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["sessions"] });
    },
  });
}
