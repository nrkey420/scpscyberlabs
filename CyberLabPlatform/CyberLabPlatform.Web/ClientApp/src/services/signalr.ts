import * as signalR from "@microsoft/signalr";
import type { ActivityEvent } from "@/types/models";

let connection: signalR.HubConnection | null = null;

export function getConnection(): signalR.HubConnection {
  if (!connection) {
    const token = sessionStorage.getItem("auth_token") ?? "";
    connection = new signalR.HubConnectionBuilder()
      .withUrl("/hubs/lab", {
        accessTokenFactory: () => token,
      })
      .withAutomaticReconnect([0, 2000, 5000, 10000, 30000])
      .configureLogging(signalR.LogLevel.Information)
      .build();
  }
  return connection;
}

export async function startConnection(): Promise<void> {
  const conn = getConnection();
  if (conn.state === signalR.HubConnectionState.Disconnected) {
    await conn.start();
  }
}

export async function stopConnection(): Promise<void> {
  if (connection && connection.state !== signalR.HubConnectionState.Disconnected) {
    await connection.stop();
  }
  connection = null;
}

export async function joinSession(sessionId: string): Promise<void> {
  const conn = getConnection();
  await conn.invoke("JoinSession", sessionId);
}

export async function leaveSession(sessionId: string): Promise<void> {
  const conn = getConnection();
  await conn.invoke("LeaveSession", sessionId);
}

export function onActivityEvent(
  callback: (event: ActivityEvent) => void
): void {
  const conn = getConnection();
  conn.on("ActivityEvent", callback);
}

export function offActivityEvent(
  callback: (event: ActivityEvent) => void
): void {
  const conn = getConnection();
  conn.off("ActivityEvent", callback);
}

export function onSessionUpdated(
  callback: (sessionId: string) => void
): void {
  const conn = getConnection();
  conn.on("SessionUpdated", callback);
}

export function onVMStatusChanged(
  callback: (vmId: string, status: string) => void
): void {
  const conn = getConnection();
  conn.on("VMStatusChanged", callback);
}

export function onProgressUpdated(
  callback: (studentId: string, objectiveId: string, points: number) => void
): void {
  const conn = getConnection();
  conn.on("ProgressUpdated", callback);
}
