"""Build the one-page Chinese trial guide with the bundled document runtime."""
from pathlib import Path
import argparse
from xml.sax.saxutils import escape
import shutil

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "output/pdf"
LEGACY = ROOT / "legacy/AutoCAD2014"
TITLE = "CAD 2014 标号插件安装使用教程"

INSTALL = [
    "把收到的 ZIP 压缩包完整解压，打开解压后的文件夹。",
    "启动 AutoCAD 2014，打开一张空白图纸，结束当前命令或对话框。",
    "双击 Install2014.cmd。看到 Installed: PatentLabel AutoCAD 2014，即安装成功。",
    "保存工作，退出并重新启动 CAD。看到“专利附图标号 0.3.1-2014 已加载”，即可使用。",
]
USE = [
    "在 CAD 命令行输入 BH，按回车。",
    "第一次点击：点击要标记的零件位置，即引线指向点。",
    "移动鼠标，预览整条折线和编号；第二次点击：确定编号中心的位置。",
    "首条默认编号为 1，直接按空格或回车确认；也可先输入其它编号再确认。本条完成后，命令结束。",
    "再按一次空格，开始下一条标号，默认编号自动递增。",
]
COMMANDS = [
    ("修改编号", "输入 BHXG，点选标号，在命令行输入新编号，按空格确认；引线间隙同步调整。"),
    ("移动编号", "输入 BHYD，点选标号，移动鼠标预览整条引线，点击新编号位置；零件端保持原位。"),
    ("调整设置", "输入 BHSZ，可设置字高、折线长度、文字间隙、确认键及加粗状态。"),
    ("取消与撤销", "Esc 取消当前操作；U 或 Ctrl+Z 撤销已完成的操作。"),
    ("原生修改", "双击编号改字，或拖动编号属性夹点；结束操作后引线自动同步。移动整块会整体移动。"),
]
PROBLEMS = [
    "安装报错：确认打开的是 AutoCAD 2014，已有图纸，当前命令或对话框已结束，再运行安装脚本。",
    "BH 提示未知命令或没有预览：先确认安装后已重启 CAD。若仍有问题，输入 BHVER，把提示、报错截图和操作步骤发回。",
]


def main(year=2014):
    if year not in (2014, 2019):
        raise ValueError("Supported guide targets: 2014, 2019")
    legacy = ROOT / f"legacy/AutoCAD{year}"
    title_text = TITLE.replace("2014", str(year))
    OUT.mkdir(parents=True, exist_ok=True)
    pdfmetrics.registerFont(TTFont("GuideBody", "C:/Windows/Fonts/simsun.ttc", subfontIndex=0))
    pdfmetrics.registerFont(TTFont("GuideHeading", "C:/Windows/Fonts/simhei.ttf"))
    body = ParagraphStyle("Body", fontName="GuideBody", fontSize=10.5, leading=15.4,
                          textColor=colors.black, wordWrap="CJK", spaceAfter=3.8,
                          allowWidows=0, allowOrphans=0)
    title = ParagraphStyle("Title", parent=body, fontName="GuideHeading", fontSize=19,
                           leading=26, spaceAfter=7)
    heading = ParagraphStyle("Heading", parent=body, fontName="GuideHeading", fontSize=12.2,
                             leading=18, spaceBefore=8.5, spaceAfter=4.5, keepWithNext=True)
    intro = ParagraphStyle("Intro", parent=body, fontSize=9.5, leading=14, spaceAfter=5)
    note = ParagraphStyle("Note", parent=body, fontName="GuideHeading", fontSize=10.3,
                          leading=15, spaceAfter=5)
    cell = ParagraphStyle("Cell", parent=body, fontSize=10.1, leading=14.7, spaceAfter=0)
    label = ParagraphStyle("Label", parent=cell, fontName="GuideHeading")
    small = ParagraphStyle("Small", parent=body, fontSize=9.3, leading=13.5, spaceAfter=2)
    def p(text, style=body):
        return Paragraph(escape(text.replace("2014", str(year))), style)
    def steps(items):
        return [p(f"{index}. {text}") for index, text in enumerate(items, 1)]

    story = [p(TITLE, title), p("适用 Windows 完整版 AutoCAD 2014，32 位或 64 位。版本 0.3.1-2014。请先在空白图纸中试用。", intro)]
    story += [p("一 首次安装", heading)] + steps(INSTALL)
    story += [p("安装只做一次。以后启动 CAD、打开或新建图纸均自动加载，无需逐张图纸重新 APPLOAD。", note)]
    story += [p("二 开始标号", heading)] + steps(USE)
    story += [p("两次空格分开按：第一次确认当前标号，第二次开始下一条。", note)]
    story += [p("编号可用 123、A、A01 等，最多 32 个字符。新标号默认黑体、不加粗。如果期间执行过其它 CAD 命令，重新输入 BH 开始标号。", small)]
    story += [p("三 修改与常用操作", heading)]
    rows = [[p(name, label), p(text, cell)] for name, text in COMMANDS]
    table = Table(rows, colWidths=[29*mm, 143*mm], hAlign="LEFT")
    table.setStyle(TableStyle([
        ("VALIGN", (0,0), (-1,-1), "TOP"),
        ("LEFTPADDING", (0,0), (-1,-1), 6), ("RIGHTPADDING", (0,0), (-1,-1), 6),
        ("TOPPADDING", (0,0), (-1,-1), 5), ("BOTTOMPADDING", (0,0), (-1,-1), 5),
        ("BACKGROUND", (0,0), (0,-1), colors.HexColor("#F2F2F2")),
        ("LINEBELOW", (0,0), (-1,-1), .3, colors.HexColor("#D8D8D8")),
    ]))
    story += [table, p("四 遇到问题", heading)] + [p(text, small) for text in PROBLEMS]
    story += [p("不再试用时：打开 CAD 2014 图纸，运行 Uninstall2014.cmd，然后重启 CAD。", small)]
    def footer(canvas, doc):
        canvas.setFont("GuideBody", 8.2)
        canvas.setFillColor(colors.HexColor("#555555"))
        canvas.drawString(19*mm, 11.5*mm, f"试用提示：本包尚待 CAD {year} 实机验证，请将异常情况反馈给发送人。")
        canvas.drawRightString(A4[0]-19*mm, 11.5*mm, str(doc.page))

    destination = OUT / f"CAD{year}标号插件安装使用教程.pdf"
    doc = SimpleDocTemplate(str(destination), pagesize=A4, rightMargin=19*mm, leftMargin=19*mm,
                            topMargin=16*mm, bottomMargin=19*mm, title=title_text,
                            author="PatentLabel", subject=f"AutoCAD {year} 试用安装与基本操作")
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    pages = PdfReader(str(destination)).pages
    if len(pages) != 1:
        raise RuntimeError(f"Quick-start must be one readable page, got {len(pages)}")
    extracted = pages[0].extract_text()
    for required in ["Install2014.cmd", "BHXG", "BHSZ", "BHVER", "Uninstall2014.cmd", "自动加载", "两次空格"]:
        assert required.replace("2014", str(year)) in extracted, required
    shutil.copy2(destination, legacy / "先看这里.pdf")

    lines = [TITLE, "", "适用 Windows 完整版 AutoCAD 2014，32 位或 64 位。版本 0.3.1-2014。", "请先在空白图纸中试用。", "", "一、首次安装"]
    lines += [f"{index}. {text}" for index, text in enumerate(INSTALL, 1)]
    lines += ["", "安装只做一次。以后启动 CAD、打开或新建图纸均自动加载，无需逐张图纸重新 APPLOAD。", "", "二、开始标号"]
    lines += [f"{index}. {text}" for index, text in enumerate(USE, 1)]
    lines += ["", "两次空格分开按：第一次确认当前标号，第二次开始下一条。", "编号可用 123、A、A01 等，最多 32 个字符。默认黑体、不加粗。", "如果期间执行过其它 CAD 命令，重新输入 BH 开始标号。", "", "三、修改与常用操作"]
    lines += [f"{name}：{text}" for name, text in COMMANDS]
    lines += ["", "四、遇到问题"] + PROBLEMS
    lines += ["", "不再试用时：打开 CAD 2014 图纸，运行 Uninstall2014.cmd，然后重启 CAD。", "", "试用提示：本包尚待 CAD 2014 实机验证，请将异常情况反馈给发送人。"]
    (legacy / "先看这里.txt").write_bytes(b"\xef\xbb\xbf" + "\r\n".join(lines).replace("2014", str(year)).encode("utf-8"))
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, choices=(2014, 2019), default=2014)
    main(parser.parse_args().year)
