using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using CoreApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;

[assembly: CommandClass(typeof(AttachmentTestCommands))]

// Test-only assembly. Never copied into an end-user package.
public sealed class AttachmentTestCommands
{
    private static string handle = "", text = "";
    private static Vector3d offset;
    [LispFunction("pltest:configure")]
    public static bool Configure(ResultBuffer args)
    {
        var values = args.AsArray();
        handle = (string)values[0].Value;
        offset = new Vector3d(Convert.ToDouble(values[1].Value), Convert.ToDouble(values[2].Value), 0);
        text = (string)values[3].Value;
        return true;
    }
    private static void Change(bool move, bool abort = false)
    {
        var db = CoreApp.DocumentManager.MdiActiveDocument.Database;
        using var tr = db.TransactionManager.StartTransaction();
        var id = db.GetObjectId(false, new Handle(Convert.ToInt64(handle, 16)), 0);
        var block = (BlockReference)tr.GetObject(id, OpenMode.ForRead);
        foreach (ObjectId item in block.AttributeCollection)
        {
            if (tr.GetObject(item, OpenMode.ForWrite) is not AttributeReference attribute || attribute.Tag != "NUMBER") continue;
            if (move)
            {
                attribute.Position += offset;
                attribute.AlignmentPoint += offset;
            }
            else attribute.TextString = text;
            attribute.AdjustAlignment(db);
        }
        if (abort) tr.Abort(); else tr.Commit();
    }
    [CommandMethod("PLTEST_ATTR_MOVE")]
    public static void Move() => Change(true);
    [CommandMethod("PLTEST_ATTR_TEXT")]
    public static void Text() => Change(false);
    [CommandMethod("PLTEST_ABORT_MOVE")]
    public static void Abort() => Change(true, true);
}
