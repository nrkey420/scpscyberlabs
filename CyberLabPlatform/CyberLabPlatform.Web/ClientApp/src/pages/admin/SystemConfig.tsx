import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { getSystemConfig, updateConfig } from "@/services/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "@/components/ui/toast";
import { Settings, Save } from "lucide-react";
import { useState } from "react";

export default function SystemConfig() {
  const { data: configs, isLoading } = useQuery({ queryKey: ["config"], queryFn: getSystemConfig });
  const queryClient = useQueryClient();
  const [editedValues, setEditedValues] = useState<Record<string, string>>({});

  const mutation = useMutation({
    mutationFn: ({ key, value }: { key: string; value: string }) => updateConfig(key, value),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["config"] });
      toast({ title: "Configuration Saved", variant: "success" });
    },
    onError: () => {
      toast({ title: "Failed to save", variant: "destructive" });
    },
  });

  const handleSave = (key: string) => {
    const value = editedValues[key];
    if (value !== undefined) {
      mutation.mutate({ key, value });
      setEditedValues((prev) => {
        const next = { ...prev };
        delete next[key];
        return next;
      });
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <Settings className="h-6 w-6 text-primary" /> System Configuration
      </h1>

      {isLoading && <p className="text-muted-foreground">Loading configuration...</p>}

      <Card>
        <CardHeader><CardTitle className="text-lg">Settings</CardTitle></CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left">
                  <th className="pb-3 pr-4">Key</th>
                  <th className="pb-3 pr-4">Value</th>
                  <th className="pb-3 pr-4">Description</th>
                  <th className="pb-3 w-20"></th>
                </tr>
              </thead>
              <tbody>
                {configs?.map((cfg) => {
                  const hasEdit = editedValues[cfg.key] !== undefined;
                  return (
                    <tr key={cfg.key} className="border-b border-border/50">
                      <td className="py-3 pr-4 font-mono text-xs text-primary">{cfg.key}</td>
                      <td className="py-3 pr-4">
                        <Input
                          value={editedValues[cfg.key] ?? cfg.value}
                          onChange={(e) => setEditedValues({ ...editedValues, [cfg.key]: e.target.value })}
                          className="h-8 text-xs"
                        />
                      </td>
                      <td className="py-3 pr-4 text-muted-foreground text-xs">{cfg.description}</td>
                      <td className="py-3">
                        <Button
                          size="sm"
                          variant={hasEdit ? "default" : "ghost"}
                          disabled={!hasEdit || mutation.isPending}
                          onClick={() => handleSave(cfg.key)}
                        >
                          <Save className="h-3 w-3" />
                        </Button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
