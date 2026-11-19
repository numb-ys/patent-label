using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Text.Json;

// Read metadata only. Never load or initialize the plug-in or AutoCAD assemblies.
using var input = File.OpenRead(args[0]);
using var pe = new PEReader(input);
var metadata = pe.GetMetadataReader();
var expectedFramework = args.Length > 1 ? args[1] : ".NETFramework,Version=v4.0";
var expectedCadApi = args.Length > 2 ? args[2] : "19.0.";
var references = metadata.AssemblyReferences.Select(handle => metadata.GetAssemblyReference(handle))
    .ToDictionary(reference => metadata.GetString(reference.Name), reference => reference.Version.ToString());
string? framework = null;
foreach (var handle in metadata.GetAssemblyDefinition().GetCustomAttributes())
{
    var attribute = metadata.GetCustomAttribute(handle);
    if (attribute.Constructor.Kind != HandleKind.MemberReference) continue;
    var constructor = metadata.GetMemberReference((MemberReferenceHandle)attribute.Constructor);
    if (constructor.Parent.Kind != HandleKind.TypeReference) continue;
    var type = metadata.GetTypeReference((TypeReferenceHandle)constructor.Parent);
    if (metadata.GetString(type.Name) != "TargetFrameworkAttribute") continue;
    var value = metadata.GetBlobReader(attribute.Value);
    if (value.ReadUInt16() == 1) framework = value.ReadSerializedString();
}
var methods = metadata.MethodDefinitions.Select(handle => metadata.GetString(metadata.GetMethodDefinition(handle).Name)).ToHashSet();
var memberNames = metadata.MemberReferences.Select(handle => metadata.GetString(metadata.GetMemberReference(handle).Name)).ToHashSet();
var flags = pe.PEHeaders.CorHeader!.Flags;
var checks = new Dictionary<string, bool>
{
    ["targets-expected-net-framework"] = framework == expectedFramework,
    ["managed-anycpu"] = flags.HasFlag(CorFlags.ILOnly) && !flags.HasFlag(CorFlags.Requires32Bit) && !flags.HasFlag(CorFlags.Prefers32Bit),
    ["uses-framework-mscorlib"] = references.GetValueOrDefault("mscorlib") == "4.0.0.0",
    ["references-target-autocad-api-only"] = new[] {"AcCoreMgd", "Acdbmgd"}.All(name => references.Any(r => r.Key.Equals(name, StringComparison.OrdinalIgnoreCase) && r.Value.StartsWith(expectedCadApi))) &&
        references.Where(r => r.Key.EndsWith("mgd", StringComparison.OrdinalIgnoreCase)).All(r => r.Value.StartsWith(expectedCadApi)),
    ["has-no-net8-json-dependency"] = !references.ContainsKey("System.Text.Json") && references.Where(r => r.Key == "System.Runtime").All(r => new Version(r.Value).Major < 8),
    ["json-uses-inbox-framework-library"] = references.GetValueOrDefault("System.Web.Extensions") == "4.0.0.0",
    ["contains-preview-place-and-clear"] = methods.Contains("Place") && methods.Contains("ClearPreview") && methods.Contains("HoldForVerification"),
    ["contains-native-font-configuration"] = methods.Contains("EnsureFonts") && methods.Contains("Configure"),
    ["has-no-custom-double-click-hook"] = !memberNames.Contains("add_BeginDoubleClick") && !memberNames.Contains("add_DocumentLockModeChanged") && !memberNames.Contains("ShowModelessDialog"),
};
var report = new { framework, expectedCadApi, flags = flags.ToString(), references, checks, passed = checks.Values.Count(v => v), failed = checks.Values.Count(v => !v), target_cad_executed = false };
Console.WriteLine(JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
return checks.Values.All(v => v) ? 0 : 1;
