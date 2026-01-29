import { useEffect } from "react";
import { create } from "zustand";
import { cn } from "@/lib/utils";
import { X } from "lucide-react";

interface Toast {
  id: string;
  title: string;
  description?: string;
  variant?: "default" | "destructive" | "success";
}

interface ToastState {
  toasts: Toast[];
  addToast: (toast: Omit<Toast, "id">) => void;
  removeToast: (id: string) => void;
}

export const useToastStore = create<ToastState>((set) => ({
  toasts: [],
  addToast: (toast) => {
    const id = Math.random().toString(36).slice(2);
    set((state) => ({ toasts: [...state.toasts, { ...toast, id }] }));
    setTimeout(() => {
      set((state) => ({ toasts: state.toasts.filter((t) => t.id !== id) }));
    }, 5000);
  },
  removeToast: (id) =>
    set((state) => ({ toasts: state.toasts.filter((t) => t.id !== id) })),
}));

export function toast(props: Omit<Toast, "id">) {
  useToastStore.getState().addToast(props);
}

export function Toaster() {
  const toasts = useToastStore((s) => s.toasts);
  const removeToast = useToastStore((s) => s.removeToast);

  useEffect(() => {}, [toasts]);

  if (toasts.length === 0) return null;

  return (
    <div className="fixed bottom-4 right-4 z-50 flex flex-col gap-2 max-w-sm">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={cn(
            "rounded-lg border p-4 shadow-lg flex items-start gap-3",
            t.variant === "destructive"
              ? "bg-destructive text-destructive-foreground border-destructive"
              : t.variant === "success"
                ? "bg-green-600 text-white border-green-700"
                : "bg-card text-card-foreground border-border"
          )}
        >
          <div className="flex-1">
            <p className="font-semibold text-sm">{t.title}</p>
            {t.description && (
              <p className="text-sm opacity-90 mt-1">{t.description}</p>
            )}
          </div>
          <button onClick={() => removeToast(t.id)} className="opacity-70 hover:opacity-100">
            <X className="h-4 w-4" />
          </button>
        </div>
      ))}
    </div>
  );
}
