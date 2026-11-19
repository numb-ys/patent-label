using System;
using System.Collections.Generic;
using System.Linq;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.GraphicsInterface;
using Autodesk.AutoCAD.Runtime;
using AcPolyline = Autodesk.AutoCAD.DatabaseServices.Polyline;

namespace PatentLabel.UI;

/// <summary>Native NUMBER grip; drag clones have graphics only, committed edits use a transaction.</summary>
internal static class LabelGripEditing
{
    private static readonly GripRule grips = new();
    private static readonly DrawRule drawing = new();
    private static readonly ExtentsRule bounds = new();
    private static readonly Dictionary<IntPtr, Preview> previews = new();
    private static readonly object gate = new();
    private static bool started;
    internal static int Samples, Draws, Commits;
    internal static string LastError = "";
    internal static int Active { get { lock (gate) return previews.Count; } }
    internal static string Geometry = "{}";

    internal static void Start()
    {
        if (started) return;
        grips.SetXDataFilter("PATENT_LABEL");
        drawing.SetXDataFilter("PATENT_LABEL");
        bounds.SetXDataFilter("PATENT_LABEL");
        var type = RXObject.GetClass(typeof(BlockReference));
        Overrule.AddOverrule(type, grips, false);
        Overrule.AddOverrule(type, drawing, false);
        Overrule.AddOverrule(type, bounds, false);
        Overrule.Overruling = true;
        started = true;
    }

    internal static void Stop()
    {
        if (!started) return;
        var type = RXObject.GetClass(typeof(BlockReference));
        Overrule.RemoveOverrule(type, grips);
        Overrule.RemoveOverrule(type, drawing);
        Overrule.RemoveOverrule(type, bounds);
        lock (gate)
        {
            foreach (var preview in previews.Values.Distinct().ToArray()) Remove(preview.Grip);
            previews.Clear();
        }
        started = false;
    }

    internal static void Close(Database db)
    {
        lock (gate)
            foreach (var preview in previews.Values.Where(p => p.Grip.Database == db).Distinct().ToArray()) Remove(preview.Grip);
    }

    private static void Remove(LabelGrip grip)
    {
        lock (gate)
        {
            if (grip.Preview is null) return;
            foreach (var key in previews.Where(p => p.Value == grip.Preview).Select(p => p.Key).ToArray()) previews.Remove(key);
            grip.Preview.Dispose();
            grip.Preview = null;
        }
    }

    private sealed class LabelGrip : GripData
    {
        internal readonly Database Database;
        internal readonly LabelAttachment.Snapshot State;
        internal Preview? Preview;
        internal LabelGrip(Database db, LabelAttachment.Snapshot state)
        {
            Database = db; State = state;
            GripPoint = state.Center.TransformBy(state.Transform);
        }
        public override string GetTooltip() => "移动编号（零件端保持不动）";
        public override void OnGripStatusChanged(ObjectId entityId, Status status)
        {
            if (status == Status.GripEnd || status == Status.GripAbort) Remove(this);
            base.OnGripStatusChanged(entityId, status);
        }
    }

    private sealed class GripRule : GripOverrule
    {
        public override void GetGripPoints(Entity entity, GripDataCollection result, double viewSize,
                                           int gripSize, Vector3d viewDirection, GetGripPointsFlags flags)
        {
            try
            {
                if (entity is BlockReference && !entity.ObjectId.IsNull)
                {
                    using var tr = entity.Database.TransactionManager.StartOpenCloseTransaction();
                    var state = LabelAttachment.Read(entity.Database, tr, entity.ObjectId);
                    if (state is not null)
                    {
                        // Replace the block-origin and attribute grips with one unambiguous label grip.
                        result.Add(new LabelGrip(entity.Database, state));
                        return;
                    }
                }
            }
            catch (System.Exception error) { LastError = error.Message; }
            base.GetGripPoints(entity, result, viewSize, gripSize, viewDirection, flags);
        }

        public override void MoveGripPointsAt(Entity entity, GripDataCollection data, Vector3d offset, MoveGripPointsFlags flags)
        {
            var grip = data.Cast<GripData>().OfType<LabelGrip>().FirstOrDefault();
            if (grip is null) { base.MoveGripPointsAt(entity, data, offset, flags); return; }
            try
            {
                var state = grip.State;
                var local = (state.Center.TransformBy(state.Transform) + offset).TransformBy(state.Transform.Inverse());
                var center = new Point3d(local.X, local.Y, 0);
                if (entity.ObjectId.IsNull)
                {
                    lock (gate)
                    {
                        if (grip.Preview is null) grip.Preview = new Preview(grip);
                        // The host can discard and recreate a drag clone for each mouse sample.
                        foreach (var key in previews.Where(p => p.Value == grip.Preview).Select(p => p.Key).ToArray()) previews.Remove(key);
                        grip.Preview.Update(center);
                        previews[entity.UnmanagedObject] = grip.Preview;
                        Geometry = grip.Preview.Snapshot();
                    }
                    entity.RecordGraphicsModified(true);
                    Samples++;
                }
                else
                {
                    using var tr = entity.Database.TransactionManager.StartTransaction();
                    LabelAttachment.MoveCenter(entity.Database, tr, entity.ObjectId, center.TransformBy(state.Transform));
                    tr.Commit();
                    Commits++;
                    Remove(grip);
                }
                LastError = "";
            }
            catch (System.Exception error) { LastError = error.Message; Remove(grip); }
        }

        public override void OnGripStatusChanged(Entity entity, GripStatus status)
        {
            if (status == GripStatus.GripsDone)
                lock (gate)
                    foreach (var preview in previews.Values.Where(p => p.Grip.State.Block == entity.ObjectId).Distinct().ToArray()) Remove(preview.Grip);
            base.OnGripStatusChanged(entity, status);
        }
    }

    private sealed class Preview : IDisposable
    {
        internal readonly LabelGrip Grip;
        private readonly AcPolyline line = new();
        private readonly DBText text = new();
        private Point3d center;
        internal Preview(LabelGrip grip)
        {
            Grip = grip;
            line.SetDatabaseDefaults(grip.Database);
            text.SetDatabaseDefaults(grip.Database);
            var state = grip.State;
            line.LayerId = text.LayerId = state.Layer;
            line.ColorIndex = state.LineColor;
            text.ColorIndex = state.TextColor;
            line.LineWeight = state.LineWeight;
            text.TextStyleId = state.Style;
            text.Height = state.Height;
            text.WidthFactor = state.WidthFactor;
            text.TextString = state.Number;
            text.HorizontalMode = TextHorizontalMode.TextCenter;
            text.VerticalMode = TextVerticalMode.TextVerticalMid;
            for (var i = 0; i < 3; i++) line.AddVertexAt(i, Point2d.Origin, 0, 0, 0);
        }
        internal void Update(Point3d value)
        {
            center = value;
            var points = LabelAttachment.Vertices(Grip.State, center);
            for (var i = 0; i < 3; i++) line.SetPointAt(i, points[i]);
            text.Position = center;
            text.AlignmentPoint = center;
            text.AdjustAlignment(Grip.Database);
        }
        internal string Snapshot()
        {
            var transform = Grip.State.Transform;
            var world = center.TransformBy(transform);
            var points = Enumerable.Range(0, 3).Select(i => line.GetPoint3dAt(i).TransformBy(transform))
                .Select(p => new[] { p.X, p.Y, p.Z }).ToArray();
            return System.Text.Json.JsonSerializer.Serialize(new { points, center = new[] { world.X, world.Y, world.Z } });
        }
        internal bool Draw(WorldDraw draw)
        {
            if (draw.Geometry is null) return true;
            draw.Geometry.PushModelTransform(Grip.State.Transform);
            try { draw.Geometry.Draw(line); draw.Geometry.Draw(text); Draws++; }
            finally { draw.Geometry.PopModelTransform(); }
            return true;
        }
        internal Extents3d Bounds()
        {
            var extents = line.GeometricExtents;
            extents.AddExtents(text.GeometricExtents);
            extents.TransformBy(Grip.State.Transform);
            return extents;
        }
        public void Dispose() { line.Dispose(); text.Dispose(); }
    }

    private sealed class DrawRule : DrawableOverrule
    {
        public override bool WorldDraw(Drawable drawable, WorldDraw draw)
        {
            lock (gate)
                if (previews.TryGetValue(drawable.UnmanagedObject, out var preview)) return preview.Draw(draw);
            return base.WorldDraw(drawable, draw);
        }
    }

    private sealed class ExtentsRule : GeometryOverrule
    {
        public override Extents3d GetGeomExtents(Entity entity)
        {
            lock (gate)
                if (previews.TryGetValue(entity.UnmanagedObject, out var preview)) return preview.Bounds();
            return base.GetGeomExtents(entity);
        }
    }
}
