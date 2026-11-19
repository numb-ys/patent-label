"""Render the English manual using standard PDF fonts (no Windows font dependency)."""
from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]


def main():
    destination = ROOT / "docs/USER_GUIDE_EN.pdf"
    source = (ROOT / "docs/USER_GUIDE_EN.md").read_text(encoding="ascii")
    body = ParagraphStyle("Body", fontName="Helvetica", fontSize=9.6, leading=13.4, spaceAfter=5)
    title = ParagraphStyle("Title", parent=body, fontName="Helvetica-Bold", fontSize=20, leading=25, spaceAfter=11)
    heading = ParagraphStyle("Heading", parent=body, fontName="Helvetica-Bold", fontSize=12, leading=17,
                             spaceBefore=11, spaceAfter=5, keepWithNext=True)
    bullet = ParagraphStyle("Bullet", parent=body, leftIndent=10, firstLineIndent=-10, spaceAfter=5)
    story = []
    for block in source.strip().split("\n\n"):
        if block.startswith("# "):
            story.append(Paragraph(escape(block[2:]), title))
        elif block.startswith("## "):
            if block == "## Edit labels and settings":
                story.append(PageBreak())
            story.append(Paragraph(escape(block[3:]), heading))
        elif block.startswith("- ") or block.startswith("1. "):
            for line in block.splitlines():
                story.append(Paragraph(escape(line), bullet))
        else:
            story.append(Paragraph(escape(" ".join(block.splitlines())), body))
    def footer(canvas, doc):
        canvas.setFont("Helvetica", 8)
        canvas.setFillColor(colors.HexColor("#555555"))
        canvas.drawString(19*mm, 11.5*mm, "PatentLabel 0.3.0 English preview | AutoCAD 2014 / 2019 / 2026")
        canvas.drawRightString(A4[0]-19*mm, 11.5*mm, str(doc.page))
    document = SimpleDocTemplate(str(destination), pagesize=A4, leftMargin=19*mm, rightMargin=19*mm,
                                  topMargin=16*mm, bottomMargin=20*mm, title="PatentLabel English user guide", author="numb-ys")
    document.build(story, onFirstPage=footer, onLaterPages=footer)
    reader = PdfReader(str(destination))
    extracted = "\n".join(page.extract_text() for page in reader.pages)
    for value in ("Install.cmd", "Uninstall.cmd", "BHXG", "BHVER", "Space again", "2014", "2019", "2026"):
        assert value in extracted, value
    print(f"{destination}: {len(reader.pages)} pages")


if __name__ == "__main__":
    main()
