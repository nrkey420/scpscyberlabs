import { RadialBarChart, RadialBar, ResponsiveContainer } from "recharts";

interface ResourceGaugeProps {
  label: string;
  used: number;
  total: number;
  unit: string;
}

export function ResourceGauge({ label, used, total, unit }: ResourceGaugeProps) {
  const percentage = total > 0 ? Math.round((used / total) * 100) : 0;
  const color = percentage > 90 ? "#ef4444" : percentage > 70 ? "#f59e0b" : "#3b82f6";

  const data = [{ name: label, value: percentage, fill: color }];

  return (
    <div className="flex flex-col items-center">
      <div className="w-32 h-32 relative">
        <ResponsiveContainer width="100%" height="100%">
          <RadialBarChart
            cx="50%"
            cy="50%"
            innerRadius="70%"
            outerRadius="100%"
            barSize={10}
            data={data}
            startAngle={90}
            endAngle={-270}
          >
            <RadialBar
              background={{ fill: "hsl(217, 33%, 17%)" }}
              dataKey="value"
              cornerRadius={5}
            />
          </RadialBarChart>
        </ResponsiveContainer>
        <div className="absolute inset-0 flex items-center justify-center">
          <span className="text-xl font-bold">{percentage}%</span>
        </div>
      </div>
      <p className="text-sm font-medium mt-2">{label}</p>
      <p className="text-xs text-muted-foreground">
        {used} / {total} {unit}
      </p>
    </div>
  );
}
