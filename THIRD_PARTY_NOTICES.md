# Third-party components

PatentLabel source code and its own documentation are licensed under MIT.

- AutoCAD is a product and trademark of Autodesk. This project is independent of Autodesk.
- AutoCAD itself, ObjectARX SDK files and Autodesk managed assemblies are not part of this repository or its installable ZIPs. You need a separately installed, supported AutoCAD product to run the plug-in.
- Builds use Autodesk's official `AutoCAD.NET.Core` and `AutoCAD.NET.Model` reference packages, or developer-supplied ObjectARX 2013/2014 references for the 2014 target. Those components retain their original terms. `PrivateAssets`/`ExcludeAssets` and explicit package file lists keep Autodesk DLLs out of the release ZIPs.
- .NET Framework reference assemblies are build-time dependencies provided by Microsoft. They are not distributed in the installable ZIPs.
- Fonts are loaded from the user's Windows installation. Font files are not shipped. The English build uses Arial; the Chinese build uses SimHei. Font rights remain with their respective owners.
- Python documentation helpers can use ReportLab, pypdf and python-docx. These authoring dependencies are not required to run PatentLabel and are not bundled with the plug-in.
