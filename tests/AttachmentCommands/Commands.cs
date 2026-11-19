using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using CoreApp = Autodesk.AutoCAD.ApplicationServices.Core.Application;
using System.Text.Json;
using Autodesk.AutoCAD.PlottingServices;

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

    private static Entity? previewClone;
    private static GripDataCollection? previewGrips;
    private static ObjectId previewSource;
    private static GripDataCollection Grips(Entity entity)
    {
        var grips = new GripDataCollection();
        entity.GetGripPoints(grips, 1, 5, Vector3d.ZAxis, (GetGripPointsFlags)0);
        return grips;
    }
    private static void ReleaseGrips(GripDataCollection grips, ObjectId id)
    {
        foreach (GripData grip in grips) grip.OnGripStatusChanged(id, GripData.Status.GripAbort);
        using var tr = id.Database.TransactionManager.StartOpenCloseTransaction();
        var entity = (Entity)tr.GetObject(id, OpenMode.ForRead);
        entity.SetGripStatus(GripStatus.GripsToBeDeleted);
        entity.SetGripStatus(GripStatus.GripsDone);
    }
    [LispFunction("pltest:grip-info")]
    public static string GripInfo(ResultBuffer arguments)
    {
        var db = CoreApp.DocumentManager.MdiActiveDocument.Database;
        using var tr = db.TransactionManager.StartOpenCloseTransaction();
        var id = db.GetObjectId(false, new Handle(Convert.ToInt64((string)arguments.AsArray()[0].Value, 16)), 0);
        var entity = (Entity)tr.GetObject(id, OpenMode.ForRead);
        var grips = Grips(entity);
        var result = JsonSerializer.Serialize(new { count = grips.Count,
            grips = grips.Cast<GripData>().Select(g => new { type = g.GetType().Name,
                point = new[] { g.GripPoint.X, g.GripPoint.Y, g.GripPoint.Z } }).ToArray() });
        ReleaseGrips(grips, id);
        return result;
    }
    [LispFunction("pltest:grip-clear")]
    public static bool ClearGripPreview(ResultBuffer? arguments = null)
    {
        if (previewGrips is not null) ReleaseGrips(previewGrips, previewSource);
        previewClone?.Dispose();
        previewClone = null; previewGrips = null;
        return true;
    }
    [LispFunction("pltest:grip-preview")]
    public static string GripPreview(ResultBuffer arguments)
    {
        ClearGripPreview();
        var values = arguments.AsArray();
        var db = CoreApp.DocumentManager.MdiActiveDocument.Database;
        using var tr = db.TransactionManager.StartOpenCloseTransaction();
        previewSource = db.GetObjectId(false, new Handle(Convert.ToInt64((string)values[0].Value, 16)), 0);
        var entity = (Entity)tr.GetObject(previewSource, OpenMode.ForRead);
        previewGrips = Grips(entity);
        previewClone = (Entity)entity.Clone();
        previewClone.MoveGripPointsAt(previewGrips,
            new Vector3d(Convert.ToDouble(values[1].Value), Convert.ToDouble(values[2].Value), 0), (MoveGripPointsFlags)0);
        return PreviewInfo();
    }
    private static string PreviewInfo()
    {
        var bounds = previewClone!.GeometricExtents;
        return JsonSerializer.Serialize(new { clone = previewClone.ObjectId.IsNull,
            min = new[] { bounds.MinPoint.X, bounds.MinPoint.Y, bounds.MinPoint.Z },
            max = new[] { bounds.MaxPoint.X, bounds.MaxPoint.Y, bounds.MaxPoint.Z } });
    }
    [LispFunction("pltest:grip-sample")]
    public static string SampleGrip(ResultBuffer arguments)
    {
        var values = arguments.AsArray();
        using var tr = previewSource.Database.TransactionManager.StartOpenCloseTransaction();
        var entity = (Entity)tr.GetObject(previewSource, OpenMode.ForRead);
        previewClone!.Dispose();
        previewClone = (Entity)entity.Clone();
        previewClone.MoveGripPointsAt(previewGrips!, new Vector3d(Convert.ToDouble(values[0].Value),
            Convert.ToDouble(values[1].Value), 0), (MoveGripPointsFlags)0);
        return PreviewInfo();
    }
    private static void CommitGrip(bool abort)
    {
        ClearGripPreview();
        var db = CoreApp.DocumentManager.MdiActiveDocument.Database;
        using var tr = db.TransactionManager.StartTransaction();
        var id = db.GetObjectId(false, new Handle(Convert.ToInt64(handle, 16)), 0);
        var entity = (Entity)tr.GetObject(id, OpenMode.ForWrite);
        var grips = Grips(entity);
        try { entity.MoveGripPointsAt(grips, offset, (MoveGripPointsFlags)0); }
        finally { ReleaseGrips(grips, id); }
        if (abort) tr.Abort(); else tr.Commit();
    }
    [CommandMethod("PLTEST_GRIP_COMMIT")]
    public static void CommitGrip() => CommitGrip(false);
    [CommandMethod("PLTEST_GRIP_ABORT")]
    public static void AbortGrip() => CommitGrip(true);

    [LispFunction("pltest:grip-render")]
    public static bool RenderGrip(ResultBuffer arguments)
    {
        ClearGripPreview();
        var db = CoreApp.DocumentManager.MdiActiveDocument.Database;
        var values = arguments.AsArray();
        var id = db.GetObjectId(false, new Handle(Convert.ToInt64((string)values[0].Value, 16)), 0);
        ObjectId imageId;
        var visible = new List<ObjectId>();
        using (var tr = db.TransactionManager.StartTransaction())
        {
            var entity = (Entity)tr.GetObject(id, OpenMode.ForRead);
            previewSource = id; previewGrips = Grips(entity);
            previewClone = (Entity)entity.Clone();
            previewClone.MoveGripPointsAt(previewGrips, new Vector3d(10,5,0), (MoveGripPointsFlags)0);
            var space = (BlockTableRecord)tr.GetObject(db.CurrentSpaceId, OpenMode.ForWrite);
            foreach (ObjectId item in space)
                if (tr.GetObject(item, OpenMode.ForWrite) is Entity candidate && candidate.Visible)
                { visible.Add(item); candidate.Visible = false; }
            imageId = space.AppendEntity(previewClone);
            tr.AddNewlyCreatedDBObject(previewClone, true);
            tr.Commit();
        }
        // Test only: the drag clone is temporarily resident so the headless plot engine can call WorldDraw.
        try
        {
            using var tr = db.TransactionManager.StartOpenCloseTransaction();
            var space = (BlockTableRecord)tr.GetObject(db.CurrentSpaceId, OpenMode.ForRead);
            var layout = (Layout)tr.GetObject(space.LayoutId, OpenMode.ForRead);
            using var settings = new PlotSettings(layout.ModelType);
            settings.CopyFrom(layout);
            var validator = PlotSettingsValidator.Current;
            validator.SetPlotConfigurationName(settings, "DWG To PDF.pc3", "ISO_full_bleed_A4_(297.00_x_210.00_MM)");
            validator.SetPlotPaperUnits(settings, PlotPaperUnit.Millimeters);
            validator.SetPlotRotation(settings, PlotRotation.Degrees000);
            validator.SetPlotWindowArea(settings, new Extents2d(-5,-5,45,30));
            validator.SetPlotType(settings, Autodesk.AutoCAD.DatabaseServices.PlotType.Window);
            validator.SetUseStandardScale(settings, true);
            validator.SetStdScaleType(settings, StdScaleType.ScaleToFit);
            validator.SetPlotCentered(settings, true);
            using var info = new PlotInfo { Layout = layout.ObjectId, OverrideSettings = settings };
            using var check = new PlotInfoValidator { MediaMatchingPolicy = MatchingPolicy.MatchEnabled };
            check.Validate(info);
            using var engine = PlotFactory.CreatePublishEngine();
            engine.BeginPlot(null, null);
            engine.BeginDocument(info, "Grip preview test", null, 1, true, (string)values[1].Value);
            using var page = new PlotPageInfo();
            engine.BeginPage(page, info, true, null);
            engine.BeginGenerateGraphics(null); engine.EndGenerateGraphics(null);
            engine.EndPage(null); engine.EndDocument(null); engine.EndPlot(null);
        }
        finally
        {
            ClearGripPreview();
            using var tr = db.TransactionManager.StartTransaction();
            ((Entity)tr.GetObject(imageId, OpenMode.ForWrite)).Erase();
            foreach (var item in visible) ((Entity)tr.GetObject(item, OpenMode.ForWrite)).Visible = true;
            tr.Commit();
        }
        return true;
    }
}
