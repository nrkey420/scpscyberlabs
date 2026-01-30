import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { getTemplates } from "@/services/api";
import api from "@/services/api";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DifficultyLevel, type LabTemplate } from "@/types/models";
import { toast } from "@/components/ui/toast";
import { FileText, Monitor, Clock, Target, ToggleLeft, ToggleRight } from "lucide-react";
import { useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";

const diffVariant: Record<string, "success" | "default" | "warning" | "destructive"> = {
  [DifficultyLevel.Beginner]: "success",
  [DifficultyLevel.Intermediate]: "default",
  [DifficultyLevel.Advanced]: "warning",
  [DifficultyLevel.Expert]: "destructive",
};

export default function Templates() {
  const { data: templates, isLoading } = useQuery({ queryKey: ["templates"], queryFn: getTemplates });
  const queryClient = useQueryClient();
  const [selected, setSelected] = useState<LabTemplate | null>(null);

  const toggleMutation = useMutation({
    mutationFn: (t: LabTemplate) => api.put(`/templates/${t.id}/toggle`, { isActive: !t.isActive }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["templates"] });
      toast({ title: "Template Updated", variant: "success" });
    },
  });

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold flex items-center gap-2"><FileText className="h-6 w-6 text-primary" /> Lab Templates</h1>
      </div>

      {isLoading && <p className="text-muted-foreground">Loading templates...</p>}

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {templates?.map((t) => (
          <Card key={t.id} className={`cursor-pointer hover:border-primary/50 transition ${!t.isActive ? "opacity-60" : ""}`}>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <CardTitle className="text-base" onClick={() => setSelected(t)}>{t.name}</CardTitle>
                <Badge variant={diffVariant[t.difficulty]}>{t.difficulty}</Badge>
              </div>
              <CardDescription className="line-clamp-2">{t.description}</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex gap-4 text-xs text-muted-foreground mb-3">
                <span className="flex items-center gap-1"><Monitor className="h-3 w-3" />{t.vmCount} VMs</span>
                <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{t.durationMinutes}m</span>
                <span className="flex items-center gap-1"><Target className="h-3 w-3" />{t.objectives.length} obj</span>
              </div>
              <div className="flex items-center justify-between">
                <div className="flex gap-1 flex-wrap">
                  {t.tags.slice(0, 3).map((tag) => (
                    <Badge key={tag} variant="outline" className="text-xs">{tag}</Badge>
                  ))}
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => toggleMutation.mutate(t)}
                  title={t.isActive ? "Deactivate" : "Activate"}
                >
                  {t.isActive ? <ToggleRight className="h-5 w-5 text-green-500" /> : <ToggleLeft className="h-5 w-5 text-muted-foreground" />}
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      {/* Detail Modal */}
      <Dialog.Root open={!!selected} onOpenChange={() => setSelected(null)}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 bg-black/60 z-50" />
          <Dialog.Content className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-card border border-border rounded-lg p-6 max-w-lg w-full z-50 max-h-[80vh] overflow-y-auto">
            {selected && (
              <>
                <Dialog.Title className="text-xl font-bold mb-1">{selected.name}</Dialog.Title>
                <Badge variant={diffVariant[selected.difficulty]} className="mb-3">{selected.difficulty}</Badge>
                <p className="text-sm text-muted-foreground mb-4">{selected.description}</p>
                <div className="space-y-3">
                  <div className="flex gap-4 text-sm">
                    <span>{selected.vmCount} VMs</span>
                    <span>{selected.durationMinutes} min</span>
                    <span>{selected.objectives.length} objectives</span>
                  </div>
                  <h3 className="font-semibold text-sm mt-4">Objectives</h3>
                  {selected.objectives.sort((a, b) => a.orderIndex - b.orderIndex).map((o) => (
                    <div key={o.id} className="text-sm border-l-2 border-primary pl-3">
                      <p className="font-medium">{o.title} <span className="text-primary">({o.points} pts)</span></p>
                      <p className="text-muted-foreground text-xs">{o.description}</p>
                    </div>
                  ))}
                </div>
                <div className="flex justify-end mt-6">
                  <Dialog.Close asChild>
                    <Button variant="outline">Close</Button>
                  </Dialog.Close>
                </div>
              </>
            )}
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>
    </div>
  );
}
