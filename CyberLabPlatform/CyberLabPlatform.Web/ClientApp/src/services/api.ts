import axios from "axios";
import type {
  LabTemplate,
  LabSession,
  LabDeployRequest,
  VMConsoleResponse,
  LeaderboardEntry,
  StudentLabAssignment,
  StudentProgressSummary,
  ActivityLog,
  ResourceUsageSummary,
  ResourceQuota,
  SystemConfig,
  SystemHealth,
  LabSessionSummary,
  ReportFormat,
} from "@/types/models";

const api = axios.create({
  baseURL: "/api",
});

api.interceptors.request.use((config) => {
  const token = sessionStorage.getItem("auth_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      sessionStorage.removeItem("auth_token");
      window.location.href = "/";
    }
    return Promise.reject(error);
  }
);

// Templates
export const getTemplates = () =>
  api.get<LabTemplate[]>("/templates").then((r) => r.data);

export const getTemplate = (id: string) =>
  api.get<LabTemplate>(`/templates/${id}`).then((r) => r.data);

// Lab Sessions
export const deployLab = (request: LabDeployRequest) =>
  api.post<LabSession>("/sessions/deploy", request).then((r) => r.data);

export const terminateLab = (sessionId: string) =>
  api.post(`/sessions/${sessionId}/terminate`).then((r) => r.data);

export const getActiveSessions = () =>
  api.get<LabSessionSummary[]>("/sessions/active").then((r) => r.data);

export const getSession = (id: string) =>
  api.get<LabSession>(`/sessions/${id}`).then((r) => r.data);

// VM Operations
export const pauseVM = (id: string) =>
  api.post(`/vms/${id}/pause`).then((r) => r.data);

export const resumeVM = (id: string) =>
  api.post(`/vms/${id}/resume`).then((r) => r.data);

export const resetVM = (id: string) =>
  api.post(`/vms/${id}/reset`).then((r) => r.data);

export const getVMConsole = (id: string) =>
  api.get<VMConsoleResponse>(`/vms/${id}/console`).then((r) => r.data);

export const createSnapshot = (vmId: string) =>
  api.post(`/vms/${vmId}/snapshot`).then((r) => r.data);

// Objectives
export const submitFlag = (objectiveId: string, flag: string) =>
  api
    .post<{ correct: boolean; pointsEarned: number }>(
      `/objectives/${objectiveId}/submit`,
      { flag }
    )
    .then((r) => r.data);

// Leaderboard & Progress
export const getLeaderboard = (sessionId: string) =>
  api
    .get<LeaderboardEntry[]>(`/sessions/${sessionId}/leaderboard`)
    .then((r) => r.data);

export const getSessionProgress = (sessionId: string) =>
  api
    .get<StudentLabAssignment[]>(`/sessions/${sessionId}/progress`)
    .then((r) => r.data);

// Student endpoints
export const getStudentSessions = () =>
  api.get<LabSessionSummary[]>("/student/sessions").then((r) => r.data);

export const getStudentSession = (sessionId: string) =>
  api
    .get<StudentLabAssignment>(`/student/sessions/${sessionId}`)
    .then((r) => r.data);

export const getStudentProgress = (_sessionId: string) =>
  api.get<StudentProgressSummary>("/student/progress").then((r) => r.data);

// Reports
export const getReport = (sessionId: string, format: ReportFormat) =>
  api
    .get(`/sessions/${sessionId}/report`, {
      params: { format },
      responseType: "blob",
    })
    .then((r) => r.data);

export const getActivityLog = (sessionId: string) =>
  api
    .get<ActivityLog[]>(`/sessions/${sessionId}/activity`)
    .then((r) => r.data);

// Resources
export const getResourceUsage = () =>
  api.get<ResourceUsageSummary>("/resources/usage").then((r) => r.data);

export const getQuotas = () =>
  api.get<ResourceQuota[]>("/resources/quotas").then((r) => r.data);

// System Config
export const getSystemConfig = () =>
  api.get<SystemConfig[]>("/config").then((r) => r.data);

export const updateConfig = (key: string, value: string) =>
  api.put(`/config/${key}`, { value }).then((r) => r.data);

// Health
export const getSystemHealth = () =>
  api.get<SystemHealth>("/health").then((r) => r.data);

// Users
export const getUsers = () =>
  api
    .get<{ id: string; name: string; email: string; role: string }[]>("/users")
    .then((r) => r.data);

export const updateUserRole = (userId: string, role: string) =>
  api.put(`/users/${userId}/role`, { role }).then((r) => r.data);

export default api;
