import { useState, useEffect } from "react";
import { getVMConsole } from "@/services/api";
import type { VMConsoleResponse } from "@/types/models";
import { Loader2, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";

interface VMConsoleProps {
  vmInstanceId: string;
  onConnect?: () => void;
  onDisconnect?: () => void;
}

export function VMConsole({ vmInstanceId, onConnect, onDisconnect }: VMConsoleProps) {
  const [console, setConsole] = useState<VMConsoleResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchConsole() {
      setLoading(true);
      setError(null);
      try {
        const data = await getVMConsole(vmInstanceId);
        if (!cancelled) {
          setConsole(data);
          onConnect?.();
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Failed to connect to VM console");
          onDisconnect?.();
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    fetchConsole();
    return () => {
      cancelled = true;
      onDisconnect?.();
    };
  }, [vmInstanceId, onConnect, onDisconnect]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full bg-black/50 rounded-lg">
        <div className="text-center">
          <Loader2 className="h-8 w-8 animate-spin text-primary mx-auto mb-3" />
          <p className="text-muted-foreground">Connecting to VM console...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-full bg-black/50 rounded-lg">
        <div className="text-center">
          <AlertTriangle className="h-8 w-8 text-destructive mx-auto mb-3" />
          <p className="text-destructive mb-3">{error}</p>
          <Button variant="outline" onClick={() => { setLoading(true); setError(null); getVMConsole(vmInstanceId).then(setConsole).catch(() => setError("Retry failed")); }}>
            Retry Connection
          </Button>
        </div>
      </div>
    );
  }

  return (
    <iframe
      src={`${console!.consoleUrl}?token=${console!.token}`}
      className="w-full h-full border-0 rounded-lg bg-black"
      title="VM Console"
      sandbox="allow-same-origin allow-scripts allow-forms"
    />
  );
}
