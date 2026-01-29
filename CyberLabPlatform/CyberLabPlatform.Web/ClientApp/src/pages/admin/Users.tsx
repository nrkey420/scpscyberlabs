import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { getUsers, updateUserRole } from "@/services/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/components/ui/toast";
import { UserRole } from "@/types/models";
import { Users as UsersIcon } from "lucide-react";

export default function Users() {
  const { data: users, isLoading } = useQuery({ queryKey: ["users"], queryFn: getUsers });
  const queryClient = useQueryClient();

  const roleMutation = useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: string }) => updateUserRole(userId, role),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] });
      toast({ title: "Role Updated", variant: "success" });
    },
    onError: () => {
      toast({ title: "Failed to update role", variant: "destructive" });
    },
  });

  const roleBadge = (role: string) => {
    if (role === UserRole.Admin) return "destructive" as const;
    if (role === UserRole.Instructor) return "default" as const;
    return "secondary" as const;
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <UsersIcon className="h-6 w-6 text-primary" /> User Management
      </h1>

      {isLoading && <p className="text-muted-foreground">Loading users...</p>}

      <Card>
        <CardHeader><CardTitle className="text-lg">All Users</CardTitle></CardHeader>
        <CardContent>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left">
                  <th className="pb-3 pr-4">Name</th>
                  <th className="pb-3 pr-4">Email</th>
                  <th className="pb-3 pr-4">Role</th>
                </tr>
              </thead>
              <tbody>
                {users?.map((u) => (
                  <tr key={u.id} className="border-b border-border/50">
                    <td className="py-3 pr-4 font-medium">{u.name}</td>
                    <td className="py-3 pr-4 text-muted-foreground">{u.email}</td>
                    <td className="py-3 pr-4">
                      <div className="flex items-center gap-2">
                        <Badge variant={roleBadge(u.role)}>{u.role}</Badge>
                        <select
                          value={u.role}
                          onChange={(e) => roleMutation.mutate({ userId: u.id, role: e.target.value })}
                          className="bg-secondary border border-border rounded px-2 py-1 text-xs"
                        >
                          {Object.values(UserRole).map((r) => (
                            <option key={r} value={r}>{r}</option>
                          ))}
                        </select>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
