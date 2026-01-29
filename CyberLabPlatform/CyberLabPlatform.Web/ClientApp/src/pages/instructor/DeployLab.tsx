import { useNavigate } from "react-router-dom";
import { LabDeploymentWizard } from "@/components/LabDeploymentWizard";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Rocket } from "lucide-react";

export default function DeployLab() {
  const navigate = useNavigate();

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold flex items-center gap-2">
        <Rocket className="h-6 w-6 text-primary" /> Deploy Lab
      </h1>
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Lab Deployment Wizard</CardTitle>
        </CardHeader>
        <CardContent>
          <LabDeploymentWizard onComplete={() => navigate("/instructor/labs")} />
        </CardContent>
      </Card>
    </div>
  );
}
