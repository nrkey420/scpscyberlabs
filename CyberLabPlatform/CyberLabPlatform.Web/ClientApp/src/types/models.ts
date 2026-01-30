export enum UserRole {
  Admin = "Admin",
  Instructor = "Instructor",
  Student = "Student",
}

export enum LabStatus {
  Pending = "Pending",
  Provisioning = "Provisioning",
  Running = "Running",
  Paused = "Paused",
  Completed = "Completed",
  Failed = "Failed",
  Terminated = "Terminated",
}

export enum VMStatus {
  Creating = "Creating",
  Running = "Running",
  Paused = "Paused",
  Stopped = "Stopped",
  Failed = "Failed",
  Deleted = "Deleted",
}

export enum DifficultyLevel {
  Beginner = "Beginner",
  Intermediate = "Intermediate",
  Advanced = "Advanced",
  Expert = "Expert",
}

export enum ReportFormat {
  PDF = "PDF",
  CSV = "CSV",
}

export interface User {
  id: string;
  name: string;
  email: string;
  role: UserRole;
}

export interface LabTemplate {
  id: string;
  name: string;
  description: string;
  difficulty: DifficultyLevel;
  durationMinutes: number;
  vmCount: number;
  objectives: LabObjective[];
  isActive: boolean;
  tags: string[];
  createdAt: string;
}

export interface LabSession {
  id: string;
  templateId: string;
  templateName: string;
  instructorId: string;
  instructorName: string;
  status: LabStatus;
  startedAt: string;
  endsAt: string;
  terminatedAt?: string;
  vmInstances: VMInstance[];
  assignments: StudentLabAssignment[];
}

export interface VMInstance {
  id: string;
  sessionId: string;
  name: string;
  status: VMStatus;
  ipAddress?: string;
  hostname: string;
  os: string;
  cpuCores: number;
  memoryMB: number;
  assignedStudentId?: string;
  assignedStudentName?: string;
}

export interface StudentLabAssignment {
  id: string;
  sessionId: string;
  studentId: string;
  studentName: string;
  studentEmail: string;
  progress: StudentProgress[];
  totalPoints: number;
  completedObjectives: number;
  totalObjectives: number;
  startedAt: string;
  completedAt?: string;
}

export interface LabObjective {
  id: string;
  templateId: string;
  title: string;
  description: string;
  points: number;
  orderIndex: number;
  flagValue?: string;
  hint?: string;
  isBonusObjective: boolean;
}

export interface StudentProgress {
  id: string;
  assignmentId: string;
  objectiveId: string;
  objectiveTitle: string;
  isCompleted: boolean;
  completedAt?: string;
  pointsEarned: number;
  flagSubmitted?: string;
}

export interface ActivityLog {
  id: string;
  sessionId: string;
  studentId?: string;
  studentName?: string;
  eventType: string;
  details: string;
  timestamp: string;
}

export interface SystemConfig {
  key: string;
  value: string;
  description: string;
  category: string;
}

export interface ResourceQuota {
  id: string;
  name: string;
  maxVMs: number;
  maxCPUCores: number;
  maxMemoryGB: number;
  currentVMs: number;
  currentCPUCores: number;
  currentMemoryGB: number;
}

export interface ResourceUsageSummary {
  totalVMs: number;
  runningVMs: number;
  totalCPUCores: number;
  usedCPUCores: number;
  totalMemoryGB: number;
  usedMemoryGB: number;
  activeSessions: number;
}

export interface LeaderboardEntry {
  rank: number;
  studentId: string;
  studentName: string;
  totalPoints: number;
  completedObjectives: number;
  totalObjectives: number;
  badges: Badge[];
  completionTime?: string;
}

export interface LabDeployRequest {
  templateId: string;
  studentIds: string[];
  timeoutMinutes: number;
  notes?: string;
}

export interface VMConsoleResponse {
  consoleUrl: string;
  token: string;
  expiresAt: string;
}

export interface LabSessionSummary {
  id: string;
  templateName: string;
  status: LabStatus;
  studentCount: number;
  startedAt: string;
  endsAt: string;
  averageProgress: number;
}

export interface StudentProgressSummary {
  totalSessions: number;
  completedSessions: number;
  totalPointsEarned: number;
  totalObjectivesCompleted: number;
  badges: Badge[];
  recentActivity: ActivityLog[];
}

export interface Badge {
  id: string;
  name: string;
  description: string;
  iconUrl: string;
  earnedAt: string;
}

export interface ActivityEvent {
  sessionId: string;
  studentId?: string;
  studentName?: string;
  eventType: string;
  details: string;
  timestamp: string;
}

export interface SystemHealth {
  status: string;
  uptime: string;
  services: { name: string; status: string; latencyMs: number }[];
}
