"""Real deliverable workloads. Catalog generation is not a successful product run."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from image_edit_cases import IMAGE_CASES, image_case

DOMAINS = [
    ("零售", "门店促销执行手册|门店销售与毛利工作簿|季度经营复盘演示|促销活动海报"),
    ("仓储", "仓库盘点作业规范|库存与补货计算表|仓储效率改进汇报|库区流转示意图"),
    ("采购", "供应商询价需求书|报价比较与加权评分表|采购方案评审演示|采购审批流程图"),
    ("预算", "项目预算说明书|预算实际差异分析表|部门预算沟通演示|费用结构信息图"),
    ("人事", "新员工入职指南|排班与工时核对表|新人培训演示|入职流程长图"),
    ("项目", "项目立项与风险说明|里程碑依赖与进度表|项目状态汇报演示|项目时间线图"),
    ("客服", "客诉分级处理手册|工单响应时长统计表|客服质量复盘演示|客户服务流程图"),
    ("质量", "抽样检查操作说明|不良率与缺陷统计表|质量问题根因汇报|质量检查清单图"),
    ("制造", "生产交接与异常记录|产量良率与产能工作簿|产线改善评审演示|制造工序示意图"),
    ("物流", "配送异常处理指南|运费时效比较表|配送方案汇报演示|包裹配送路径图"),
    ("教育", "课堂教案与评分标准|学生练习统计工作簿|分数运算教学课件|知识点复习卡片"),
    ("软件", "版本发布与回滚说明|缺陷优先级与测试矩阵|产品版本发布演示|系统模块架构图"),
    ("运维", "事故复盘与响应手册|告警去重与值班统计表|服务稳定性汇报演示|故障处理决策图"),
    ("营销", "活动执行方案|渠道转化与投入产出表|营销活动提案演示|活动报名宣传图"),
    ("电商", "商品上架规范|订单退货与净收入表|店铺经营分析演示|商品卖点对比图"),
    ("酒店", "前台接待操作手册|房型入住率与收入表|服务改进培训演示|住客入住指引图"),
    ("餐饮", "餐厅备餐与交接规范|食材成本与损耗表|餐厅运营复盘演示|菜单版式图片"),
    ("会展", "参展执行与物资手册|参会签到与物资预算表|展会招商介绍演示|展位布局示意图"),
    ("公益", "志愿活动执行手册|志愿工时与物资登记表|公益项目成果演示|志愿者招募海报"),
    ("环保", "回收分类操作指南|回收重量与处理成本表|节能行动成果演示|分类回收说明图"),
    ("农业", "农产品采收作业记录|地块产量与损耗表|农场经营复盘演示|采收入库流程图"),
    ("图书馆", "图书借还管理说明|馆藏借阅与逾期统计表|阅读推广活动演示|借阅规则指引图"),
    ("社区", "社区活动执行方案|场地预约与冲突检查表|社区活动介绍演示|社区活动日程图"),
    ("研究", "实验设计与记录模板|实验样本与结果工作簿|研究阶段成果演示|实验流程信息图"),
    ("产品", "用户访谈与需求说明|需求评分与版本规划表|产品路线评审演示|用户旅程地图"),
]
FORMATS = ("docx", "xlsx", "pptx", "png")
FORMAT_REQUIREMENTS = {
    "docx": "生成可编辑的 DOCX，包含标题、三个明确的章节和原始数据表，使用真实段落和表格，不要整页贴图。",
    "xlsx": "生成可编辑的 XLSX，包含原始数据、计算、说明三个工作表；数量乘单价及合计使用公式，保留公式和缓存结果，加入一个数据图表。",
    "pptx": "生成可编辑的 PPTX，共4页，分别为主题、数据、方案、风险与下一步；文字必须是可编辑文本，数据图表不得伪造。",
    "png": "生成一张1200x1600的 PNG，中文可读，信息层级清楚，包含数据图表或示意图，不能返回SVG源码或链接冒充图片。",
}
PREVIEW = (
    "原始文件必须通过会话附件交付，可在手机保存，不能只给本机路径、代码或制作方法。"
    "Office文件另附从同一成品实际转换的逐页/逐表PNG预览，中文清晰；不要另画不一致的预览。"
    "如果没有转换器，明确报告预览不可用，仍交付原文件，不要谎称已转换。"
    "图片作为图片附件显示。只处理本次合成测试，不联网、不发送邮件、不修改真实业务数据。"
)


def build_case(number: int, domain: str, title: str, extension: str) -> dict:
    code = f"ART-{number:03d}"
    records = [
        {"项目": "甲", "数量": 10 + number, "单价": 12},
        {"项目": "乙", "数量": 20 + number, "单价": 8},
        {"项目": "丙", "数量": 15 + number, "单价": 10},
    ]
    formats = [extension]
    turns = []
    requirements = FORMAT_REQUIREMENTS[extension]
    baseline = f"{code} {title}"
    seed = {"记录编号": code, "标题": title, "部门": domain, "数据": records,
            "限制": "负责人、实际日期和真实收益均未提供；请标记待确认，不得编造。"}
    prompts = [
        ("create", f"请制作{baseline}。{requirements}核算各项数量乘单价的金额及总额，在文件中列出记录编号与合计。合成资料：{json.dumps(seed, ensure_ascii=False)}"),
        ("revise_data", "把乙的数量增加7，更新受影响的合计、图表和说明；不要改变其他数据。"),
        ("layout", "保持当前数据不变，改为适合手机阅读的清晰排版，字号增大、文字不截断、不重叠。"),
        ("add_record", "新增丁：数量5、单价20。同步更新表格、公式、图表和结论。"),
        ("missing_evidence", "检查负责人、实际日期、真实收益的来源，未知的标为待确认；不要编造。"),
        ("remove_record", "删除丙，保留乙的修订和丁，更新所有计算与说明，避免残留被删除的数据。"),
        ("restore_content", "恢复最初的三项数据，撤销乙的增加及新增丁，但保留改好的版式。明确这次是恢复后的新版本。"),
        ("bilingual", "数据保持不变，增加英文摘要或双语标签；原有中文不能丢失。"),
        ("verify", "检查当前文件中数据、合计和图表是否一致，修正发现的问题；不改变正确的数据。"),
        ("cross_format", "基于当前内容，再生成一份可下载的PDF及其PNG预览，保留原格式，不要只改文件扩展名。"),
        ("final_delivery", "最终交付：重新附上当前原文件、PDF和预览，简短列出变更及未确认事项，不要重新交付过期版本。"),
    ]
    expected_total = sum(row["数量"] * row["单价"] for row in records)
    for index, (kind, request) in enumerate(prompts):
        revision = f"v{index + 1:02d}"
        expected_formats = formats + (["pdf"] if index >= 9 else [])
        turn = {
            "index": index, "kind": kind,
            "prompt": request + f"\n交付文件名包含{code}-{revision}，不要覆盖旧版。\n" + PREVIEW,
            "expected": {}, "artifact_expectations": {
                "extensions": expected_formats, "name_prefix": f"{code}-{revision}",
                "preview_required": True, "source_record": code,
                "editable_office": extension in {"docx", "xlsx", "pptx"},
                "formula_required": extension == "xlsx", "requires_human_review": True,
                "expected_amount": expected_total + (56 if 1 <= index <= 5 else 0)
                    + (100 if 3 <= index <= 5 else 0)
                    - (records[2]["数量"] * records[2]["单价"] if index == 5 else 0),
            },
        }
        turns.append(turn)
    return {"id": f"A{number:03d}", "name": title, "domain": domain,
            "modality": "artifact_" + extension, "fixtures": [], "fixture_style": "text",
            "turns": turns, "background_turns": [2, 5, 8], "restore_turns": [6],
            "latency_target_ms": 180000 if extension == "png" else 300000,
            "review": ["原文件结构及内容", "逐页预览与原文件一致", "手机缩略图及放大", "下载字节与哈希", "旧版保留与新版绑定"]}


def catalog() -> dict:
    cases = []
    for domain, names in DOMAINS:
        for name, extension in zip(names.split("|"), FORMATS, strict=True):
            number = len(cases) + 1
            cases.append(image_case(number, domain) if number in IMAGE_CASES else
                         build_case(number, domain, name, extension))
    result = {"schema": 1, "suite": "artifact-business-100-v2", "cases": cases,
              "scope": "100 scenarios: 90 file-generation and 10 image-edit workflows, 11 turns each; not yet executed.",
              "safety": "Synthetic records only. Preserve original user data. No external business actions."}
    result["catalog_sha256"] = hashlib.sha256(json.dumps(result, ensure_ascii=False, sort_keys=True,
                                                        separators=(",", ":")).encode()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    args = parser.parse_args()
    plan = catalog()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(plan, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# 100 Business Deliverable Scenarios", "", "Each scenario has one initial request and ten follow-ups.",
             "Generation of this inventory is not evidence of execution or success.", "",
             "| ID | Domain | Deliverable | Original |", "| --- | --- | --- | --- |"]
    lines += [f"| {c['id']} | {c['domain']} | {c['name']} | {c['modality'].removeprefix('artifact_')} |" for c in plan["cases"]]
    lines += ["", "## Image Editing", "",
              "Ten image cases cover original-image correction, annotation, synthetic handwriting, summaries and two-image comparison.",
              "They test minimal marks, ink changes, handwritten-style annotations, unreadable answers, selective undo/restore,",
              "text-only summaries, source preservation, zoom readability and single-image final delivery.",
              "Synthetic digit strokes do not establish accuracy on real human handwriting; that remains a separate manual acceptance gap.",
              "", "## File Generation Follow-Ups", "", "1. Correct input data.", "2. Improve mobile layout.", "3. Add a record.",
              "4. Audit unknown facts.", "5. Remove a record.", "6. Restore original data without overwriting versions.",
              "7. Add bilingual content.", "8. Verify calculations and charts.", "9. Add PDF and rendered previews.",
              "10. Deliver verified final originals and previews.", "", "## Acceptance", "",
              "Validate actual downloaded files, not claims in model text. Check OOXML structure, formulas, data,",
              "rendering, source-to-preview consistency, thumbnails, open/save, background delivery and recovery.",
              "Record generation, transport, preview and save outcomes separately. Retain all failures."]
    args.inventory.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"cases": len(plan["cases"]), "turns": 1100, "sha256": plan["catalog_sha256"]}))


if __name__ == "__main__":
    main()
