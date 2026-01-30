import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { getTemplates, getUsers } from "@/services/api";
import { useDeployLab } from "@/hooks/useLabSession";
import type { LabTemplate, LabDeployRequest } from "@/types/models";
import { DifficultyLevel } from "@/types/models";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/components/ui/toast";
import { ChevronLeft, ChevronRight, Rocket, CheckCircle2, Search } from "lucide-react";

const difficultyColor: Record<DifficultyLevel, string> = {
  [DifficultyLevel.Beginner]: "success",
  [DifficultyLevel.Intermediate]: "default",
  [DifficultyLevel.Advanced]: "warning",
  [DifficultyLevel.Expert]: "destructive",
};

const steps = ["Select Template", "Select Students", "Configuration", "Review & Deploy"];

export function LabDeploymentWizard({ onComplete }: { onComplete?: () => void }) {
  const [step, setStep] = useState(0);
  const [selectedTemplate, setSelectedTemplate] = useState<LabTemplate | null>(null);
  const [selectedStudentIds, setSelectedStudentIds] = useState<string[]>([]);
  const [timeout, setTimeout] = useState(60);
  const [notes, setNotes] = useState("");
  const [studentSearch, setStudentSearch] = useState("");

  const { data: templates } = useQuery({ queryKey: ["templates"], queryFn: getTemplates });
  const { data: users } = useQuery({ queryKey: ["users"], queryFn: getUsers });
  const deployMutation = useDeployLab();

  const students = users?.filter((u) => u.role === "Student") ?? [];
  const filteredStudents = students.filter(
    (s) => s.name.toLowerCase().includes(studentSearch.toLowerCase()) ||
           s.email.toLowerCase().includes(studentSearch.toLowerCase())
  );

  const canNext = () => {
    if (step === 0) return !!selectedTemplate;
    if (step === 1) return selectedStudentIds.length > 0;
    if (step === 2) return timeout > 0;
    return true;
  };

  const handleDeploy = async () => {
    if (!selectedTemplate) return;
    const request: LabDeployRequest = {
      templateId: selectedTemplate.id,
      studentIds: selectedStudentIds,
      timeoutMinutes: timeout,
      notes: notes || undefined,
    };
    try {
      await deployMutation.mutateAsync(request);
      toast({ title: "Lab Deployed", description: "Lab session is being provisioned.", variant: "success" });
      onComplete?.();
    } catch {
      toast({ title: "Deployment Failed", description: "Could not deploy the lab.", variant: "destructive" });
    }
  };

  return (
    <div className="space-y-6">
      {/* Step indicator */}
      <div className="flex items-center gap-2">
        {steps.map((s, i) => (
          <div key={s} className="flex items-center gap-2">
            <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold ${
              i < step ? "bg-green-600 text-white" : i === step ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground"
            }`}>
              {i < step ? <CheckCircle2 className="h-4 w-4" /> : i + 1}
            </div>
            <span className={`text-sm hidden sm:inline ${i === step ? "text-foreground font-medium" : "text-muted-foreground"}`}>{s}</span>
            {i < steps.length - 1 && <div className="w-8 h-px bg-border" />}
          </div>
        ))}
      </div>

      {/* Step 0: Template */}
      {step === 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {templates?.filter((t) => t.isActive).map((t) => (
            <Card
              key={t.id}
              className={`cursor-pointer transition-all hover:border-primary ${
                selectedTemplate?.id === t.id ? "border-primary ring-2 ring-primary/30" : ""
              }`}
              onClick={() => setSelectedTemplate(t)}
            >
              <CardHeader className="pb-2">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">{t.name}</CardTitle>
                  <Badge variant={difficultyColor[t.difficulty] as "default"}>{t.difficulty}</Badge>
                </div>
              </CardHeader>
              <CardContent>
                <p className="text-sm text-muted-foreground mb-3">{t.description}</p>
                <div className="flex gap-4 text-xs text-muted-foreground">
                  <span>{t.vmCount} VMs</span>
                  <span>{t.durationMinutes} min</span>
                  <span>{t.objectives.length} objectives</span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Step 1: Students */}
      {step === 1 && (
        <div className="space-y-4">
          <div className="relative">
            <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search students..."
              value={studentSearch}
              onChange={(e) => setStudentSearch(e.target.value)}
              className="pl-10"
            />
          </div>
          <div className="flex items-center justify-between text-sm text-muted-foreground">
            <span>{selectedStudentIds.length} selected</span>
            <Button variant="ghost" size="sm" onClick={() => setSelectedStudentIds(
              selectedStudentIds.length === students.length ? [] : students.map((s) => s.id)
            )}>
              {selectedStudentIds.length === students.length ? "Deselect All" : "Select All"}
            </Button>
          </div>
          <div className="space-y-1 max-h-64 overflow-y-auto">
            {filteredStudents.map((s) => (
              <label
                key={s.id}
                className="flex items-center gap-3 p-2 rounded-md hover:bg-secondary/50 cursor-pointer"
              >
                <input
                  type="checkbox"
                  checked={selectedStudentIds.includes(s.id)}
                  onChange={(e) => {
                    if (e.target.checked) {
                      setSelectedStudentIds([...selectedStudentIds, s.id]);
                    } else {
                      setSelectedStudentIds(selectedStudentIds.filter((id) => id !== s.id));
                    }
                  }}
                  className="rounded border-border"
                />
                <div>
                  <p className="text-sm font-medium">{s.name}</p>
                  <p className="text-xs text-muted-foreground">{s.email}</p>
                </div>
              </label>
            ))}
          </div>
        </div>
      )}

      {/* Step 2: Configuration */}
      {step === 2 && (
        <div className="space-y-6 max-w-md">
          <div>
            <label className="text-sm font-medium mb-2 block">Session Timeout (minutes)</label>
            <input
              type="range"
              min={15}
              max={240}
              step={15}
              value={timeout}
              onChange={(e) => setTimeout(Number(e.target.value))}
              className="w-full"
            />
            <p className="text-sm text-muted-foreground mt-1">{timeout} minutes</p>
          </div>
          <div>
            <label className="text-sm font-medium mb-2 block">Notes (optional)</label>
            <Input
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Any additional notes..."
            />
          </div>
        </div>
      )}

      {/* Step 3: Review */}
      {step === 3 && (
        <div className="space-y-4">
          <Card>
            <CardContent className="p-4 space-y-3">
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Template</span>
                <span className="text-sm font-medium">{selectedTemplate?.name}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Students</span>
                <span className="text-sm font-medium">{selectedStudentIds.length} selected</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Timeout</span>
                <span className="text-sm font-medium">{timeout} minutes</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">VMs per student</span>
                <span className="text-sm font-medium">{selectedTemplate?.vmCount}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-muted-foreground">Total VMs</span>
                <span className="text-sm font-bold text-primary">
                  {(selectedTemplate?.vmCount ?? 0) * selectedStudentIds.length}
                </span>
              </div>
              {notes && (
                <div className="flex justify-between">
                  <span className="text-sm text-muted-foreground">Notes</span>
                  <span className="text-sm">{notes}</span>
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      )}

      {/* Navigation */}
      <div className="flex justify-between pt-4 border-t border-border">
        <Button variant="outline" onClick={() => setStep(step - 1)} disabled={step === 0}>
          <ChevronLeft className="h-4 w-4 mr-1" /> Back
        </Button>
        {step < 3 ? (
          <Button onClick={() => setStep(step + 1)} disabled={!canNext()}>
            Next <ChevronRight className="h-4 w-4 ml-1" />
          </Button>
        ) : (
          <Button onClick={handleDeploy} disabled={deployMutation.isPending}>
            <Rocket className="h-4 w-4 mr-1" />
            {deployMutation.isPending ? "Deploying..." : "Deploy Lab"}
          </Button>
        )}
      </div>
    </div>
  );
}
