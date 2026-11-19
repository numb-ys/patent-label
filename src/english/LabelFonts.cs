using System;
using System.IO;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.GraphicsInterface;

namespace PatentLabel.English;

internal static class LabelFonts
{
    internal const string BoldStyle = "PATENT_LABEL_ARIAL_BOLD";
    internal const string RegularStyle = "PATENT_LABEL_ARIAL_REGULAR";

    internal static bool Ensure(Database database)
    {
        var changed = false;
        using var tr = database.TransactionManager.StartTransaction();
        var styles = (TextStyleTable)tr.GetObject(database.TextStyleTableId, OpenMode.ForRead);
        foreach (var bold in new[] { true, false })
        {
            var name = bold ? BoldStyle : RegularStyle;
            var file = bold ? "arialbd.ttf" : "arial.ttf";
            TextStyleTableRecord style;
            if (styles.Has(name))
            {
                style = (TextStyleTableRecord)tr.GetObject(styles[name], OpenMode.ForRead);
                var font = style.Font;
                if (font.Bold == bold && !font.Italic &&
                    font.TypeFace.Equals("Arial", StringComparison.OrdinalIgnoreCase) &&
                    Path.GetFileName(style.FileName).Equals(file, StringComparison.OrdinalIgnoreCase)) continue;
                style.UpgradeOpen();
            }
            else
            {
                if (!styles.IsWriteEnabled) styles.UpgradeOpen();
                style = new TextStyleTableRecord { Name = name, TextSize = 0, XScale = 1 };
                styles.Add(style);
                tr.AddNewlyCreatedDBObject(style, true);
            }
            style.FileName = file;
            style.Font = new FontDescriptor("Arial", bold, false, 0, 34);
            changed = true;
        }
        tr.Commit();
        return changed;
    }
}
