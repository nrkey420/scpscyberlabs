import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { getActiveSessions, getReport, getActivityLog } from "@/services/api";
import { ReportFormat } from "@/types/models";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { toast } from "@/components/ui/toast";
import { BarChart3, FileDown, FileSpreadsheet, Download } from "lucide-react";

export default function Reports() {
  const { data: sessions } = useQuery({ queryKey: ["sessions", "active"], queryFn: getActiveSessions });
  const [selectedSession, setSelectedSession] = useState("");
  const [loading, setLoading] = useState(false);

  const downloadReport = async (format: ReportFormat) => {
    if (!selectedSession) return;
    setLoading(true);
    try {
      const blob = await getReport(selectedSession, format);
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `report-${selectedSession}.${format.toLowerCase()}`;
      a.click();
      URL.revokeObjectURL(url);
      toast({ title: "Report Downloaded", variant: "success" });
    } catch {
      toast({ title: "Failed to generate report", variant: "destructive" });
    } finally {
      setLoading(false);
    }
  };

  const exportActivity = async () => {
    if (!selectedSession) return;
    setLoading(true);
    try {
      const logs = await getActivityLog(selectedSession);
      const csv = ["Timestamp,Student,Event,Details"]
        .concat(logs.map((l) => `${l.timestamp},${l.studentName ?? ""},${l.eventType},${l.details}`))
        .join("\n");
      const blob = new Blob([csv], { type: "text/csv" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `activity-${selectedSession}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      toast({ title: "Activity Log Exported", variant: "success" });
    } catch {
      toast({ title: "Failed to export", variant: "destructive" });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <BarChart3 className="h-6 w-6 text-primary" /> Reports
      </h1>

      <Card>
        <CardHeader><CardTitle className="text-lg">Select Session</CardTitle></CardHeader>
        <CardContent>
          <select
            value={selectedSession}
            onChange={(e) => setSelectedSession(e.target.value)}
            className="w-full bg-secondary border border-border rounded-md px-3 py-2 text-sm"
          >
            <option value="">Choose a session...</option>
            {sessions?.map((s) => (
              <option key={s.id} value={s.id}>{s.templateName} - {s.studentCount} students</option>
            ))}
          </select>
        </CardContent>
      </Card>

      {selectedSession && (
        <Card>
          <CardHeader><CardTitle className="text-lg">Generate Report</CardTitle></CardHeader>
          <CardContent>
            <div className="flex flex-wrap gap-3">
              <Button onClick={() => downloadReport(ReportFormat.PDF)} disabled={loading}>
                <FileDown className="h-4 w-4 mr-2" /> Download PDF
              </Button>
              <Button variant="outline" onClick={() => downloadReport(ReportFormat.CSV)} disabled={loading}>
                <FileSpreadsheet className="h-4 w-4 mr-2" /> Download CSV
              </Button>
              <Button variant="secondary" onClick={exportActivity} disabled={loading}>
                <Download className="h-4 w-4 mr-2" /> Export Activity Log
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
