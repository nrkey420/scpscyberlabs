namespace CyberLabPlatform.Core.Models;

public class LabObjective
{
    public Guid Id { get; set; }
    public Guid TemplateId { get; set; }
    public LabTemplate Template { get; set; } = null!;
    public int ObjectiveOrder { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string FlagValue { get; set; } = string.Empty;
    public int Points { get; set; } = 10;
    public string Hint { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
